package main

import "core:runtime"
import "core:sync"
// import "core:slice"
import "clap"

plugin_descriptor := clap.Plugin_Descriptor{
	id = "com.alkamist.gain",
	name = "Gain",
	vendor = "Alkamist Audio",
	url = "",
	manual_url = "",
	support_url = "",
	version = "0.1.0",
	description = "",
}

Plugin :: struct {
    clap_plugin: clap.Plugin,
    midi_events: [dynamic]clap.Event_Midi,
    parameters_main_thread: [PARAMETER_COUNT]Parameter,
    parameters_audio_thread: [PARAMETER_COUNT]Parameter,
    parameter_mutex: sync.Mutex,
    latency: u32,
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

get_plugin :: proc "c" (clap_plugin: ^clap.Plugin) -> ^Plugin {
    return cast(^Plugin)clap_plugin.plugin_data
}

// decrease_midi_events_time :: proc(plugin: ^Plugin, time: u32) {
//     for _, i in plugin.midi_events {
//         plugin.midi_events[i].header.time -= time
//     }
// }

// sort_midi_events_by_time :: proc(plugin: ^Plugin) {
//     slice.sort_by(plugin.midi_events[:], proc(i, j: clap.Event_Midi) -> bool {
//         if i.header.time < j.header.time {
//             return true
//         } else {
//             return false
//         }
//     })
// }

// push_midi_events :: proc(plugin: ^Plugin, frame_count: u32, out_events: ^clap.Output_Events) {
//     sort_midi_events_by_time(plugin)
//     last_index_in_block := 0
//     for _, i in plugin.midi_events {
//         if plugin.midi_events[i].header.time < frame_count {
//             out_events.try_push(out_events, &plugin.midi_events[i].header)
//             last_index_in_block = i
//         } else {
//             break
//         }
//     }
//     if last_index_in_block > 0 && last_index_in_block < len(plugin.midi_events) {
//         remove_range(&plugin.midi_events, 0, last_index_in_block)
//     }
// }

plugin_init :: proc "c" (clap_plugin: ^clap.Plugin) -> bool {
    plugin := get_plugin(clap_plugin)
    plugin.latency = 2048
    return true
}

plugin_destroy :: proc "c" (clap_plugin: ^clap.Plugin) {
    context = runtime.default_context()
    plugin := get_plugin(clap_plugin)
    delete(plugin.midi_events)
    free(plugin)
}

plugin_activate :: proc "c" (clap_plugin: ^clap.Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool {
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

// plugin_process :: proc "c" (clap_plugin: ^clap.Plugin, clap_process: ^clap.Process) -> clap.Process_Status {
//     context = runtime.default_context()
//     plugin := get_plugin(clap_plugin)

//     // frame_count := clap_process.frames_count
//     event_count := clap_process.in_events.size(clap_process.in_events)

//     for event_index in 0 ..< event_count {
//         event_header := clap_process.in_events.get(clap_process.in_events, event_index)
//         if event_header.space_id == clap.CORE_EVENT_SPACE_ID {
//             #partial switch event_header.type {
//             case .Midi:
//                 // event := (cast(^clap.Event_Midi)event_header)^
//                 clap_process.out_events.try_push(clap_process.out_events, event_header)
//             }
//         }
//     }

//     return .Continue
// }

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
                // case .Midi:
                //     event := (cast(^clap.Event_Midi)event_header)^
                //     // event.header.time += 2048
                //     append(&plugin.midi_events, event)
                }
            }

            event_index += 1

            if (event_index == event_count) {
                next_event_index = frame_count
                break
            }
        }

        // push_midi_events(plugin, clap_process.frames_count, clap_process.out_events)

        frame = next_event_index
    }

    // decrease_midi_events_time(plugin, clap_process.frames_count)

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