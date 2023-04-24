package main

import "core:runtime"
import "core:sync"
import "core:slice"
import "clap"
import cs "cs_corrector"

plugin_descriptor := clap.Plugin_Descriptor{
	id = "com.alkamist.cs_corrector",
	name = "Cs Corrector",
	vendor = "Alkamist Audio",
	url = "",
	manual_url = "",
	support_url = "",
	version = "0.1.0",
	description = "",
}

Plugin :: struct {
    clap_plugin: clap.Plugin,
    cs_corrector: cs.Cs_Corrector,
    sample_rate: f64,
    midi_port: u16,
    latency: u32,
    parameters_main_thread: [PARAMETER_COUNT]Parameter,
    parameters_audio_thread: [PARAMETER_COUNT]Parameter,
    parameter_mutex: sync.Mutex,
}

Cs_Corrector_Context :: struct {
    midi_port: u16,
    out_events: ^clap.Output_Events,
}

millis_to_samples :: proc "c" (plugin: ^Plugin, seconds: f64) -> i32 {
    return i32(plugin.sample_rate * seconds * 0.001)
}

push_midi_event_from_cs_corrector :: proc(event: ^cs.Midi_Event) {
    ctx := cast(^Cs_Corrector_Context)context.user_ptr
    clap_event := clap.Event_Midi{
        header = {
            size = size_of(clap.Event_Midi),
            time = u32(event.time),
            space_id = clap.CORE_EVENT_SPACE_ID,
            type = .Midi,
            flags = 0,
        },
        port_index = ctx.midi_port,
        data = event.data,
    }
    ctx.out_events.try_push(ctx.out_events, &clap_event.header)
}

get_plugin :: proc "c" (clap_plugin: ^clap.Plugin) -> ^Plugin {
    return cast(^Plugin)clap_plugin.plugin_data
}

plugin_create_instance :: proc() -> ^clap.Plugin {
    plugin := new(Plugin)
    plugin.clap_plugin = {
        desc = &plugin_descriptor,
        plugin_data = plugin,
        init = plugin_init,
        destroy = plugin_destroy,
        activate = plugin_activate,
        deactivate = plugin_deactivate,
        start_processing = plugin_start_processing,
        stop_processing = plugin_stop_processing,
        reset = plugin_reset,
        process = plugin_process,
        get_extension = plugin_get_extension,
        on_main_thread = plugin_on_main_thread,
    }
    return &plugin.clap_plugin
}

plugin_init :: proc "c" (clap_plugin: ^clap.Plugin) -> bool {
    plugin := get_plugin(clap_plugin)
    return true
}

plugin_destroy :: proc "c" (clap_plugin: ^clap.Plugin) {
    context = runtime.default_context()
    plugin := get_plugin(clap_plugin)
    cs.destroy(&plugin.cs_corrector)
    free(plugin)
}

plugin_activate :: proc "c" (clap_plugin: ^clap.Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool {
    plugin := get_plugin(clap_plugin)
    plugin.sample_rate = sample_rate
    plugin.latency = 0
    plugin.cs_corrector.legato_first_delay = millis_to_samples(plugin, -60.0)
    plugin.cs_corrector.legato_level0_delay = millis_to_samples(plugin, -300.0)
    plugin.cs_corrector.legato_level1_delay = millis_to_samples(plugin, -300.0)
    plugin.cs_corrector.legato_level2_delay = millis_to_samples(plugin, -300.0)
    plugin.cs_corrector.legato_level3_delay = millis_to_samples(plugin, -300.0)
    return true
}

plugin_deactivate :: proc "c" (clap_plugin: ^clap.Plugin) {
}

plugin_start_processing :: proc "c" (clap_plugin: ^clap.Plugin) -> bool {
    return true
}

plugin_stop_processing :: proc "c" (clap_plugin: ^clap.Plugin) {
}

plugin_reset :: proc "c" (clap_plugin: ^clap.Plugin) {
}

plugin_process :: proc "c" (clap_plugin: ^clap.Plugin, clap_process: ^clap.Process) -> clap.Process_Status {
    context = runtime.default_context()
    plugin := get_plugin(clap_plugin)

    frame_count := clap_process.frames_count
    event_count := clap_process.in_events.size(clap_process.in_events)
    event_index := u32(0)
    next_event_index := u32(0)
    if event_count == 0 {
        next_event_index = frame_count
    }
    frame := u32(0)

    parameters_sync_main_to_audio(plugin, clap_process.out_events)

    for frame < frame_count {
        for event_index < event_count && next_event_index == frame {
            event_header := clap_process.in_events.get(clap_process.in_events, event_index)
            if event_header.time != frame {
                next_event_index = event_header.time
                break
            }

            if event_header.space_id == clap.CORE_EVENT_SPACE_ID {
                #partial switch event_header.type {

                case .Param_Value:
                    event := cast(^clap.Event_Param_Value)event_header
                    sync.lock(&plugin.parameter_mutex)
                    plugin.parameters_audio_thread[event.param_id].value = event.value
                    plugin.parameters_audio_thread[event.param_id].changed = true
                    sync.unlock(&plugin.parameter_mutex)

                case .Midi:
                    event := (cast(^clap.Event_Midi)event_header)
                    if event.port_index == plugin.midi_port {
                        cs.append_event(&plugin.cs_corrector, cs.Midi_Event{
                            time = event.header.time,
                            data = event.data,
                        })
                    }

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

    context.user_ptr = &Cs_Corrector_Context{
        midi_port = plugin.midi_port,
        out_events = clap_process.out_events,
    }
    cs.push_midi_events(&plugin.cs_corrector, frame_count, push_midi_event_from_cs_corrector)

    return .Continue
}

plugin_get_extension :: proc "c" (clap_plugin: ^clap.Plugin, id: cstring) -> rawptr {
    switch id {
    case clap.EXT_NOTE_PORTS: return &note_ports_extension
    case clap.EXT_LATENCY: return &latency_extension
    case clap.EXT_PARAMS: return &parameters_extension
    case: return nil
    }
}

plugin_on_main_thread :: proc "c" (clap_plugin: ^clap.Plugin) {
}