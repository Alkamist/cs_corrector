package main

import "core:mem"
import "core:fmt"
import "core:sync"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:runtime"

CLAP_VERSION :: Clap_Version{1, 1, 8}

Midi_Event :: struct {
    time: int,
    port: int,
    data: [3]u8,
}

Parameter_Event_Kind :: enum {
    Value,
    Modulation,
}

Parameter_Event :: struct {
    id: Parameter,
    kind: Parameter_Event_Kind,
    note_id: int,
    port: int,
    channel: int,
    key: int,
    value: f64,
}

Time_Signature :: struct {
    numerator: int,
    denominator: int,
}

Transport_Flag :: enum {
    Is_Playing,
    Is_Recording,
    Loop_Is_Active,
    Is_Within_Pre_Roll,
}

Transport_Event :: struct {
    flags: bit_set[Transport_Flag],
    song_position_seconds: Maybe(f64),
    loop_start_seconds: Maybe(f64),
    loop_end_seconds: Maybe(f64),
    song_position_beats: Maybe(f64),
    loop_start_beats: Maybe(f64),
    loop_end_beats: Maybe(f64),
    tempo: Maybe(f64),
    tempo_increment: Maybe(f64),
    bar_start_beats: Maybe(f64),
    bar_number: Maybe(int),
    time_signature: Maybe(Time_Signature),
}

Parameter_Flag :: enum {
    Is_Stepped,
    Is_Periodic,
    Is_Hidden,
    Is_Read_Only,
    Is_Bypass,
    Is_Automatable,
    Is_Automatable_Per_Note_Id,
    Is_Automatable_Per_Key,
    Is_Automatable_Per_Channel,
    Is_Automatable_Per_Port,
    Is_Modulatable,
    Is_Modulatable_Per_Note_Id,
    Is_Modulatable_Per_Key,
    Is_Modulatable_Per_Channel,
    Is_Modulatable_Per_Port,
    Requires_Process,
}

Parameter_Info :: struct {
    id: Parameter,
    name: string,
    min_value: f64,
    max_value: f64,
    default_value: f64,
    flags: bit_set[Parameter_Flag],
    module: string,
}

Audio_Plugin_Base :: struct {
    sample_rate: f64,
    min_frame_count: int,
    max_frame_count: int,
    latency: int,
    is_active: bool,
    clap_plugin: Clap_Plugin,
    clap_host: ^Clap_Host,
    clap_host_log: ^Clap_Host_Log,
    clap_host_latency: ^Clap_Host_Latency,
    clap_host_timer_support: ^Clap_Host_Timer_Support,
    timer_name_to_id: map[string]Clap_Id,
    timer_id_to_proc: map[Clap_Id]proc(plugin: ^Audio_Plugin),
    parameter_values: [Parameter]f64,
    output_events: [dynamic]Clap_Event_Union,
}

milliseconds_to_samples :: proc(plugin: ^Audio_Plugin, milliseconds: f64) -> int {
    return int(plugin.sample_rate * milliseconds * 0.001)
}

parameter :: proc(plugin: ^Audio_Plugin, id: Parameter) -> f64 {
    return sync.atomic_load(&plugin.parameter_values[id])
}

set_parameter :: proc(plugin: ^Audio_Plugin, id: Parameter, value: f64) {
    sync.atomic_store(&plugin.parameter_values[id], value)
}

reset_parameter_to_default :: proc(plugin: ^Audio_Plugin, id: Parameter) {
    set_parameter(plugin, id, parameter_info[id].default_value)
}

register_timer :: proc(plugin: ^Audio_Plugin, name: string, period_ms: int, timer_proc: proc(plugin: ^Audio_Plugin)) {
    if plugin.clap_host_timer_support == nil ||
       plugin.clap_host_timer_support.register_timer == nil {
        return
    }
    id: Clap_Id
    plugin.clap_host_timer_support.register_timer(plugin.clap_host, u32(period_ms), &id)
    plugin.timer_name_to_id[name] = id
    plugin.timer_id_to_proc[id] = timer_proc
}

unregister_timer :: proc(plugin: ^Audio_Plugin, name: string) {
    if plugin.clap_host_timer_support == nil ||
       plugin.clap_host_timer_support.unregister_timer == nil {
        return
    }
    if id, ok := plugin.timer_name_to_id[name]; ok {
        id := plugin.timer_name_to_id[name]
        plugin.clap_host_timer_support.unregister_timer(plugin.clap_host, id)
        plugin.timer_id_to_proc[id] = nil
    }
}

set_latency :: proc(plugin: ^Audio_Plugin, value: int) {
    plugin.latency = value
    if plugin.clap_host_latency == nil ||
       plugin.clap_host_latency.changed == nil ||
       plugin.clap_host.request_restart == nil {
        return
    }

    // Inform the host of the latency change.
    plugin.clap_host_latency.changed(plugin.clap_host)
    if plugin.is_active {
        plugin.clap_host->request_restart()
    }
}

send_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {
    append(&plugin.output_events, Clap_Event_Midi{
        header = {
            size = size_of(Clap_Event_Midi),
            // after the bug in reaper gets fixed: time = u32(event.time)
            time = u32(event.time - plugin.latency),
            space_id = CLAP_CORE_EVENT_SPACE_ID,
            type = .Midi,
            flags = 0,
        },
        port_index = u16(event.port),
        data = event.data,
    })
}


// ==============================================================================
// Implementation
// ==============================================================================


Clap_Event_Union :: union {
    Clap_Event_Midi,
    Clap_Event_Param_Value,
}

clap_plugin_descriptor := Clap_Plugin_Descriptor{
    clap_version = CLAP_VERSION,
    id = ID,
    name = NAME,
    vendor = VENDOR,
    url = URL,
    manual_url = MANUAL_URL,
    support_url = SUPPORT_URL,
    version = VERSION,
    description = DESCRIPTION,
    // features = raw_data([]cstring{CLAP_PLUGIN_FEATURE_NOTE_EFFECT, CLAP_PLUGIN_FEATURE_UTILITY, nil}),
}

get_instance :: proc "c" (plugin: ^Clap_Plugin) -> ^Audio_Plugin {
    return cast(^Audio_Plugin)plugin.plugin_data
}

clap_plugin_init :: proc "c" (plugin: ^Clap_Plugin) -> bool {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    // plugin.clap_host_log = cast(^Clap_Host_Log)(plugin.clap_host->get_extension(CLAP_EXT_LOG))
    plugin.clap_host_timer_support = cast(^Clap_Host_Timer_Support)plugin.clap_host->get_extension(CLAP_EXT_TIMER_SUPPORT)
    plugin.clap_host_latency = cast(^Clap_Host_Latency)(plugin.clap_host->get_extension(CLAP_EXT_LATENCY))
    reserve(&plugin.output_events, 16384)
    on_create(plugin)
    return true
}

clap_plugin_destroy :: proc "c" (plugin: ^Clap_Plugin) {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    on_destroy(plugin)
    delete(plugin.timer_name_to_id)
    delete(plugin.timer_id_to_proc)
    delete(plugin.output_events)
}

clap_plugin_activate :: proc "c" (plugin: ^Clap_Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    plugin.sample_rate = sample_rate
    plugin.min_frame_count = int(min_frames_count)
    plugin.max_frame_count = int(max_frames_count)
    plugin.is_active = true
    on_activate(plugin)
    return true
}

clap_plugin_deactivate :: proc "c" (plugin: ^Clap_Plugin) {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    plugin.is_active = false
    on_deactivate(plugin)
}

clap_plugin_start_processing :: proc "c" (plugin: ^Clap_Plugin) -> bool {
    return true
}

clap_plugin_stop_processing :: proc "c" (plugin: ^Clap_Plugin) {
}

clap_plugin_reset :: proc "c" (plugin: ^Clap_Plugin) {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    resize(&plugin.output_events, 0)
}

clap_plugin_process :: proc "c" (plugin: ^Clap_Plugin, process: ^Clap_Process) -> Clap_Process_Status {
    context = runtime.default_context()
    plugin := get_instance(plugin)

    frame_count := process.frames_count
    event_count := process.in_events->size()
    event_index: u32 = 0
    next_event_index: u32 = 0
    if event_count == 0 {
        next_event_index = frame_count
    }
    frame: u32 = 0

    dispatch_transport_event(plugin, process.transport)

    for frame < frame_count {
        for event_index < event_count && next_event_index == frame {
            event_header := process.in_events->get(event_index)
            if event_header.time != frame {
                next_event_index = event_header.time
                break
            }

            if event_header.space_id == CLAP_CORE_EVENT_SPACE_ID {
                dispatch_parameter_event(plugin, event_header)
                dispatch_midi_event(plugin, event_header)
            }

            event_index += 1

            if (event_index == event_count) {
                next_event_index = frame_count
                break
            }
        }

        // Audio processing will happen here eventually.

        frame = next_event_index
    }

    on_process(plugin, int(process.frames_count))

    // Sort and send output events, then clear the buffer.
    slice.sort_by(plugin.output_events[:], proc(i, j: Clap_Event_Union) -> bool {
        i := i
        j := j
        i_header := cast(^Clap_Event_Header)&i
        j_header := cast(^Clap_Event_Header)&j
        return i_header.time < j_header.time
    })
    for event in &plugin.output_events {
        process.out_events->try_push(cast(^Clap_Event_Header)&event)
    }
    resize(&plugin.output_events, 0)

    return .Continue
}

clap_plugin_get_extension :: proc "c" (plugin: ^Clap_Plugin, id: cstring) -> rawptr {
    switch id {
    case CLAP_EXT_NOTE_PORTS: return &clap_extension_note_ports
    case CLAP_EXT_LATENCY: return &clap_extension_latency
    case CLAP_EXT_PARAMS: return &clap_extension_parameters
    case CLAP_EXT_TIMER_SUPPORT: return &clap_extension_timer
    case CLAP_EXT_STATE: return &clap_extension_state
    // case CLAP_EXT_GUI: return &clap_extension_gui
    case: return nil
    }
}

clap_plugin_on_main_thread :: proc "c" (plugin: ^Clap_Plugin) {
}

clap_extension_parameters := Clap_Plugin_Params{
    count = proc "c" (plugin: ^Clap_Plugin) -> u32 {
        context = runtime.default_context()
        plugin := get_instance(plugin)
        return len(Parameter)
    },
    get_info = proc "c" (plugin: ^Clap_Plugin, param_index: u32, param_info: ^Clap_Param_Info) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)
        if len(Parameter) == 0 {
            return false
        }
        param_info.id = u32(parameter_info[param_index].id)
        param_info.flags = parameter_flags_to_clap_flags(parameter_info[param_index].flags)
        write_string(param_info.name[:], parameter_info[param_index].name)
        write_string(param_info.module[:], parameter_info[param_index].module)
        param_info.min_value = parameter_info[param_index].min_value
        param_info.max_value = parameter_info[param_index].max_value
        param_info.default_value = parameter_info[param_index].default_value
        return true
    },
    get_value = proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, out_value: ^f64) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)
        if len(Parameter) == 0 {
            return false
        }
        out_value^ = parameter(plugin, Parameter(param_id))
        return true
    },
    value_to_text = proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, value: f64, out_buffer: [^]byte, out_buffer_capacity: u32) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)
        if len(Parameter) == 0 {
            return false
        }
        value_string := fmt.aprintf("%v", value)
        write_string(out_buffer[:out_buffer_capacity], value_string)
        return true
    },
    text_to_value = proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, param_value_text: cstring, out_value: ^f64) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)
        if len(Parameter) == 0 {
            return false
        }
        value, ok := strconv.parse_f64(cast(string)param_value_text)
        if ok {
            out_value^ = value
            return true
        } else {
            return false
        }
    },
    flush = proc "c" (plugin: ^Clap_Plugin, input: ^Clap_Input_Events, output: ^Clap_Output_Events) {
        context = runtime.default_context()
        plugin := get_instance(plugin)
        event_count := input->size()
        for i in 0 ..< event_count {
            event_header := input->get(i)
            dispatch_parameter_event(plugin, event_header)
        }
    },
}

clap_extension_latency := Clap_Plugin_Latency{
    get = proc "c" (plugin: ^Clap_Plugin) -> u32 {
        plugin := get_instance(plugin)
        return u32(max(0, plugin.latency))
    },
}

clap_extension_note_ports := Clap_Plugin_Note_Ports{
    count = proc "c" (plugin: ^Clap_Plugin, is_input: bool) -> u32 {
        return 1
    },
    get = proc "c" (plugin: ^Clap_Plugin, index: u32, is_input: bool, info: ^Clap_Note_Port_Info) -> bool {
        info.id = 0
        info.supported_dialects = {.Midi}
        info.preferred_dialect = {.Midi}
        write_string(info.name[:], "MIDI Port 1")
        return true
    },
}

clap_extension_timer := Clap_Plugin_Timer_Support{
    on_timer = proc "c" (clap_plugin: ^Clap_Plugin, timer_id: Clap_Id) {
        context = runtime.default_context()
        plugin := get_instance(clap_plugin)
        if timer_proc, ok := plugin.timer_id_to_proc[timer_id]; ok {
            timer_proc(plugin)
        }
    },
}

clap_extension_state := Clap_Plugin_State{
    save = proc "c" (plugin: ^Clap_Plugin, stream: ^Clap_Ostream) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)

        builder := strings.builder_make_none()
        defer strings.builder_destroy(&builder)

        if save_preset(plugin, &builder) == false {
            return false
        }
        if len(builder.buf) == 0 {
            return false
        }

        write_ptr := &builder.buf[0]
        bytes_to_write := i64(len(builder.buf))
        for {
            bytes_written := stream.write(stream, write_ptr, u64(bytes_to_write))

            // Success
            if bytes_written == bytes_to_write {
                break
            }

            // An error happened
            if bytes_written <= 0 || bytes_written > bytes_to_write {
                return false
            }

            bytes_to_write -= bytes_written
            write_ptr = mem.ptr_offset(write_ptr, bytes_written)
        }

        return true
    },
    load = proc "c" (plugin: ^Clap_Plugin, stream: ^Clap_Istream) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)

        preset_data: [dynamic]byte
        defer delete(preset_data)

        for {
            data_byte: byte
            bytes_read := stream.read(stream, &data_byte, 1)

            // Hit the end of the stream
            if bytes_read == 0 {
                break
            }

            // Possibly more to read so keep going
            if bytes_read == 1 {
                append(&preset_data, data_byte)
                continue
            }

            // An error happened
            if bytes_read < 0 {
                return false
            }
        }

        load_preset(plugin, preset_data[:])

        return true
    },
}

clap_plugin_factory := Clap_Plugin_Factory{
    get_plugin_count = proc "c" (factory: ^Clap_Plugin_Factory) -> u32 {
        return 1
    },
    get_plugin_descriptor = proc "c" (factory: ^Clap_Plugin_Factory, index: u32) -> ^Clap_Plugin_Descriptor {
        return &clap_plugin_descriptor
    },
    create_plugin = proc "c" (factory: ^Clap_Plugin_Factory, host: ^Clap_Host, plugin_id: cstring) -> ^Clap_Plugin {
        context = runtime.default_context()
        if !clap_version_is_compatible(host.clap_version) {
            return nil
        }
        if plugin_id == clap_plugin_descriptor.id {
            plugin := new(Audio_Plugin)
            plugin.clap_host = host
            plugin.clap_plugin = {
                desc = &clap_plugin_descriptor,
                plugin_data = plugin,
                init = clap_plugin_init,
                destroy = clap_plugin_destroy,
                activate = clap_plugin_activate,
                deactivate = clap_plugin_deactivate,
                start_processing = clap_plugin_start_processing,
                stop_processing = clap_plugin_stop_processing,
                reset = clap_plugin_reset,
                process = clap_plugin_process,
                get_extension = clap_plugin_get_extension,
                on_main_thread = clap_plugin_on_main_thread,
            }
            return &plugin.clap_plugin
        }
        return nil
    },
}

@export
clap_entry := Clap_Plugin_Entry{
	clap_version = CLAP_VERSION,
	init = proc "c" (plugin_path: cstring) -> bool {
        return true
    },
	deinit = proc "c" () {
    },
	get_factory = proc "c" (factory_id: cstring) -> rawptr {
        if factory_id == CLAP_PLUGIN_FACTORY_ID {
            return &clap_plugin_factory
        }
        return nil
    },
}

write_string :: proc "c" (buffer: []byte, value: string) {
    n := copy(buffer, value)
    // Make it null terminated
    buffer[min(n, len(buffer) - 1)] = 0
}

from_beat_time :: proc "c" (time: Clap_Beat_Time) -> f64 {
    return f64(time) / f64(CLAP_BEATTIME_FACTOR)
}

from_sec_time :: proc "c" (time: Clap_Beat_Time) -> f64 {
    return f64(time) / f64(CLAP_SECTIME_FACTOR)
}

parameter_flags_to_clap_flags :: proc "c" (flags: bit_set[Parameter_Flag]) -> bit_set[Clap_Param_Info_Flag; u32] {
    result: bit_set[Clap_Param_Info_Flag; u32]
    if .Is_Stepped in flags do result += {.Is_Stepped}
    if .Is_Periodic in flags do result += {.Is_Periodic}
    if .Is_Hidden in flags do result += {.Is_Hidden}
    if .Is_Read_Only in flags do result += {.Is_Read_Only}
    if .Is_Bypass in flags do result += {.Is_Bypass}
    if .Is_Automatable in flags do result += {.Is_Automatable}
    if .Is_Automatable_Per_Note_Id in flags do result += {.Is_Automatable_Per_Note_Id}
    if .Is_Automatable_Per_Key in flags do result += {.Is_Automatable_Per_Key}
    if .Is_Automatable_Per_Channel in flags do result += {.Is_Automatable_Per_Channel}
    if .Is_Automatable_Per_Port in flags do result += {.Is_Automatable_Per_Port}
    if .Is_Modulatable in flags do result += {.Is_Modulatable}
    if .Is_Modulatable_Per_Note_Id in flags do result += {.Is_Modulatable_Per_Note_Id}
    if .Is_Modulatable_Per_Key in flags do result += {.Is_Modulatable_Per_Key}
    if .Is_Modulatable_Per_Channel in flags do result += {.Is_Modulatable_Per_Channel}
    if .Is_Modulatable_Per_Port in flags do result += {.Is_Modulatable_Per_Port}
    if .Requires_Process in flags do result += {.Requires_Process}
    return result
}

dispatch_parameter_event :: proc(plugin: ^Audio_Plugin, event_header: ^Clap_Event_Header) {
    #partial switch event_header.type {
    case .Param_Value:
        clap_event := cast(^Clap_Event_Param_Value)event_header
        id := Parameter(clap_event.param_id)
        set_parameter(plugin, id, clap_event.value)
        on_parameter_event(plugin, Parameter_Event{
            id = id,
            kind = .Value,
            note_id = int(clap_event.note_id),
            port = int(clap_event.port_index),
            channel = int(clap_event.channel),
            key = int(clap_event.key),
            value = clap_event.value,
        })
    }
}

dispatch_transport_event :: proc(plugin: ^Audio_Plugin, clap_event: ^Clap_Event_Transport) {
    if clap_event != nil {
        event: Transport_Event
        if .Is_Playing in clap_event.flags {
            event.flags += {.Is_Playing}
        }
        if .Is_Recording in clap_event.flags {
            event.flags += {.Is_Recording}
        }
        if .Is_Loop_Active in clap_event.flags {
            event.flags += {.Loop_Is_Active}
        }
        if .Is_Within_Pre_Roll in clap_event.flags {
            event.flags += {.Is_Within_Pre_Roll}
        }
        if .Has_Time_Signature in clap_event.flags {
            event.time_signature = Time_Signature{
                numerator = int(clap_event.tsig_num),
                denominator = int(clap_event.tsig_denom),
            }
        }
        if .Has_Tempo in clap_event.flags {
            event.tempo = clap_event.tempo
            event.tempo_increment = clap_event.tempo_inc
        }
        if .Has_Beats_Timeline in clap_event.flags {
            event.song_position_beats = from_beat_time(clap_event.song_pos_beats)
            event.loop_start_beats = from_beat_time(clap_event.loop_start_beats)
            event.loop_end_beats = from_beat_time(clap_event.loop_end_beats)
            event.bar_start_beats = from_beat_time(clap_event.bar_start)
            event.bar_number = int(clap_event.bar_number)
        }
        if .Has_Seconds_Timeline in clap_event.flags {
            event.song_position_seconds = from_sec_time(clap_event.song_pos_seconds)
            event.loop_start_seconds = from_sec_time(clap_event.loop_start_seconds)
            event.loop_end_seconds = from_sec_time(clap_event.loop_end_seconds)
        }
        on_transport_event(plugin, event)
    }
}

dispatch_midi_event :: proc(plugin: ^Audio_Plugin, event_header: ^Clap_Event_Header) {
    clap_event := cast(^Clap_Event_Midi)event_header
    on_midi_event(plugin, Midi_Event{
        time = int(event_header.time),
        port = int(clap_event.port_index),
        data = clap_event.data,
    })
}