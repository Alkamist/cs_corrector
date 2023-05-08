package main

import "core:fmt"
import "core:runtime"
import "core:sync"
import "core:slice"
import "core:strings"
import "clap"
import cs "cs_corrector"

CLAP_VERSION :: clap.Version{1, 1, 8}

plugin_descriptor := clap.Plugin_Descriptor{
    clap_version = CLAP_VERSION,
    id = "com.alkamist.CsCorrector",
    name = "Cs Corrector",
    vendor = "Alkamist Audio",
    url = "",
    manual_url = "",
    support_url = "",
    version = "0.1.0",
    description = "A MIDI timing corrector for Cinematic Studios libraries.",
    features = raw_data([]cstring{clap.PLUGIN_FEATURE_NOTE_EFFECT, clap.PLUGIN_FEATURE_UTILITY, nil}),
}

Plugin_Instance :: struct {
    is_active: bool,
    is_playing: bool,
    sample_rate: f64,
    latency: int,
    cs_corrector: cs.State,
    clap_host: ^clap.Host,
    clap_host_log: ^clap.Host_Log,
    clap_host_timer_support: ^clap.Host_Timer_Support,
    clap_host_latency: ^clap.Host_Latency,
    clap_plugin: clap.Plugin,
    main_thread_parameter_value: [PARAMETER_COUNT]f64,
    main_thread_parameter_changed: [PARAMETER_COUNT]bool,
    audio_thread_parameter_value: [PARAMETER_COUNT]f64,
    audio_thread_parameter_changed: [PARAMETER_COUNT]bool,
    parameter_mutex: sync.Mutex,
    timer_name_to_id: map[string]clap.Id,
    timer_id_to_proc: map[clap.Id]proc(instance: ^Plugin_Instance),
}

millis_to_samples :: proc(instance: ^Plugin_Instance, millis: f64) -> int {
    return int(instance.sample_rate * millis * 0.001)
}

cs_corrector_update_parameters :: proc(instance: ^Plugin_Instance) {
    instance.cs_corrector.legato_first_note_delay = millis_to_samples(instance, parameter(instance, .Legato_First_Note_Delay))
    instance.cs_corrector.legato_portamento_delay = millis_to_samples(instance, parameter(instance, .Legato_Portamento_Delay))
    instance.cs_corrector.legato_slow_delay = millis_to_samples(instance, parameter(instance, .Legato_Slow_Delay))
    instance.cs_corrector.legato_medium_delay = millis_to_samples(instance, parameter(instance, .Legato_Medium_Delay))
    instance.cs_corrector.legato_fast_delay = millis_to_samples(instance, parameter(instance, .Legato_Fast_Delay))
    set_latency(instance, cs.required_latency(&instance.cs_corrector))
}

cs_corrector_encode_midi_message :: proc(msg: cs.Note_Event) -> [3]u8 {
    channel := 0
    status := channel
    switch msg.kind {
    case .Off: status += 0x80
    case .On: status += 0x90
    }
    return {
        u8(status),
        u8(msg.key),
        u8(msg.velocity),
    }
}

on_midi_event :: proc(instance: ^Plugin_Instance, process: ^clap.Process, event: ^clap.Event_Midi) {
    event := event

    // Don't process when project is not playing back so there isn't
    // an annoying delay when drawing notes on the piano roll
    if !instance.is_playing {
        event.header.time -= u32(instance.latency)
        process.out_events->try_push(&event.header)
        return
    }

    msg := event.data
    status_code := msg[0] & 0xF0

    is_note_off := status_code == 0x80
    if is_note_off {
        cs.process_note_off(
            &instance.cs_corrector,
            int(event.header.time),
            int(msg[1]),
            int(msg[2]),
        )
        return
    }

    is_note_on := status_code == 0x90
    if is_note_on {
        cs.process_note_on(
            &instance.cs_corrector,
            int(event.header.time),
            int(msg[1]),
            int(msg[2]),
        )
        return
    }

    is_cc := status_code == 0xB0
    is_hold_pedal := is_cc && msg[1] == 64
    if is_hold_pedal {
        is_held := msg[2] > 63
        cs.process_hold_pedal(&instance.cs_corrector, is_held)
        // Don't return because we need to send the hold pedal information
    }

    // Pass any events that aren't note on or off straight to the host
    process.out_events->try_push(&event.header)
}

on_process :: proc(instance: ^Plugin_Instance, process: ^clap.Process) {
    frame_count := int(process.frames_count)
    note_events := cs.extract_note_events(&instance.cs_corrector, frame_count)
    defer delete(note_events)

    for event in note_events {
        clap_event := clap.Event_Midi{
            header = {
                size = size_of(clap.Event_Midi),
                time = u32(event.time - instance.latency),
                space_id = clap.CORE_EVENT_SPACE_ID,
                type = .Midi,
                flags = 0,
            },
            port_index = 0,
            data = cs_corrector_encode_midi_message(event),
        }
        process.out_events->try_push(&clap_event.header)
    }
}

instance_init :: proc "c" (plugin: ^clap.Plugin) -> bool {
    context = runtime.default_context()
    instance := get_instance(plugin)

    instance.clap_host_log = cast(^clap.Host_Log)(instance.clap_host->get_extension(clap.EXT_LOG))
    instance.clap_host_timer_support = cast(^clap.Host_Timer_Support)instance.clap_host->get_extension(clap.EXT_TIMER_SUPPORT)
    instance.clap_host_latency = cast(^clap.Host_Latency)(instance.clap_host->get_extension(clap.EXT_LATENCY))

    for parameter in Parameter {
        instance.audio_thread_parameter_value[parameter] = parameter_info[parameter].default_value
        instance.main_thread_parameter_value[parameter] = parameter_info[parameter].default_value
    }

    // register_timer(instance, "Debug_Timer", 0, proc(instance: ^Plugin_Instance) {
    // })

    return true
}

instance_destroy :: proc "c" (plugin: ^clap.Plugin) {
    context = runtime.default_context()
    instance := get_instance(plugin)
    // unregister_timer(instance, "Debug_Timer")
    cs.destroy(&instance.cs_corrector)
    delete(instance.timer_name_to_id)
    delete(instance.timer_id_to_proc)
    free(instance)
}

instance_activate :: proc "c" (plugin: ^clap.Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool {
    context = runtime.default_context()
    instance := get_instance(plugin)
    instance.sample_rate = sample_rate
    cs_corrector_update_parameters(instance)
    instance.is_active = true
    return true
}

instance_deactivate :: proc "c" (plugin: ^clap.Plugin) {
    context = runtime.default_context()
    instance := get_instance(plugin)
    instance.is_active = false
}

instance_start_processing :: proc "c" (plugin: ^clap.Plugin) -> bool {
    return true
}

instance_stop_processing :: proc "c" (plugin: ^clap.Plugin) {
}

instance_reset :: proc "c" (plugin: ^clap.Plugin) {
    context = runtime.default_context()
    instance := get_instance(plugin)
    cs.reset(&instance.cs_corrector)
}

instance_process :: proc "c" (plugin: ^clap.Plugin, process: ^clap.Process) -> clap.Process_Status {
    context = runtime.default_context()
    instance := get_instance(plugin)

    frame_count := process.frames_count
    event_count := process.in_events->size()
    event_index: u32 = 0
    next_event_index: u32 = 0
    if event_count == 0 {
        next_event_index = frame_count
    }
    frame: u32 = 0

    parameters_sync_main_to_audio(instance, process.out_events)

    log(instance, .Debug, "Yee")

    transport_event := process.transport
    if transport_event != nil {
        if .Is_Playing in transport_event.flags {
            instance.is_playing = true
        } else {
            instance.is_playing = false
            cs.reset(&instance.cs_corrector)
        }
    }

    for frame < frame_count {
        for event_index < event_count && next_event_index == frame {
            event_header := process.in_events->get(event_index)
            if event_header.time != frame {
                next_event_index = event_header.time
                break
            }

            if event_header.space_id == clap.CORE_EVENT_SPACE_ID {
                #partial switch event_header.type {

                case .Param_Value:
                    event := cast(^clap.Event_Param_Value)event_header
                    sync.lock(&instance.parameter_mutex)
                    instance.audio_thread_parameter_value[event.param_id] = event.value
                    instance.audio_thread_parameter_changed[event.param_id] = true
                    sync.unlock(&instance.parameter_mutex)
                    cs_corrector_update_parameters(instance)

                case .Midi:
                    event := (cast(^clap.Event_Midi)event_header)
                    on_midi_event(instance, process, event)
                }
            }

            event_index += 1

            if (event_index == event_count) {
                next_event_index = frame_count
                break
            }
        }

        frame = next_event_index
    }

    on_process(instance, process)

    return .Continue
}

instance_get_extension :: proc "c" (plugin: ^clap.Plugin, id: cstring) -> rawptr {
    switch id {
    case clap.EXT_NOTE_PORTS: return &note_ports_extension
    case clap.EXT_LATENCY: return &latency_extension
    case clap.EXT_PARAMS: return &parameters_extension
    case clap.EXT_TIMER_SUPPORT: return &timer_extension
    case clap.EXT_STATE: return &state_extension
    // case clap.EXT_GUI: return &gui_extension
    case: return nil
    }
}

instance_on_main_thread :: proc "c" (plugin: ^clap.Plugin) {
}