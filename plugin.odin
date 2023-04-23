package main

import "core:runtime"
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
    latency: u32,
}

plugin_create_instance :: proc() -> ^clap.Plugin {
    plugin := new(Plugin)
    plugin.clap_plugin.desc = &plugin_descriptor
    plugin.clap_plugin.plugin_data = plugin
    plugin.clap_plugin.init = plugin_init
    plugin.clap_plugin.destroy = plugin_destroy
    plugin.clap_plugin.activate = plugin_activate
    plugin.clap_plugin.deactivate = plugin_deactivate
    plugin.clap_plugin.start_processing = plugin_start_processing
    plugin.clap_plugin.stop_processing = plugin_stop_processing
    plugin.clap_plugin.reset = plugin_reset
    plugin.clap_plugin.process = plugin_process
    plugin.clap_plugin.get_extension = plugin_get_extension
    plugin.clap_plugin.on_main_thread = plugin_on_main_thread
	return &plugin.clap_plugin
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
    plugin := cast(^Plugin)clap_plugin.plugin_data
    plugin.latency = 2048
    return true
}

plugin_destroy :: proc "c" (clap_plugin: ^clap.Plugin) {
    context = runtime.default_context()
    plugin := cast(^Plugin)clap_plugin.plugin_data
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

plugin_process :: proc "c" (clap_plugin: ^clap.Plugin, clap_process: ^clap.Process) -> clap.Process_Status {
    context = runtime.default_context()
    plugin := cast(^Plugin)clap_plugin.plugin_data

    // frame_count := clap_process.frames_count
    event_count := clap_process.in_events.size(clap_process.in_events)

    for event_index in 0 ..< event_count {
        event_header := clap_process.in_events.get(clap_process.in_events, event_index)
        if event_header.space_id == clap.core_event_space_id {
            #partial switch event_header.type {
            case .Midi: {
                event := (cast(^clap.Event_Midi)event_header)^
                clap_process.out_events.try_push(clap_process.out_events, event_header)
            }
            }
        }
    }

    return .Continue
}

// plugin_process :: proc "c" (clap_plugin: ^clap.Plugin, clap_process: ^clap.Process) -> clap.Process_Status {
//     context = runtime.default_context()
//     plugin := cast(^Plugin)clap_plugin.plugin_data

//     frame_count := clap_process.frames_count
//     event_count := clap_process.in_events.size(clap_process.in_events)
//     event_index := u32(0)
//     next_event_index := u32(0)
//     if event_count == 0 {
//         next_event_index = frame_count
//     }
//     frame := u32(0)

//     for frame < frame_count {
//         for event_index < event_count && next_event_index == frame {
//             event_header := clap_process.in_events.get(clap_process.in_events, event_index)
//             if event_header.time != frame {
//                 next_event_index = event_header.time
//                 break
//             }

//             if event_header.space_id == clap.core_event_space_id {
//                 #partial switch event_header.type {
//                 case .Midi: {
//                     event := (cast(^clap.Event_Midi)event_header)^
//                     // event.header.time += 2048
//                     append(&plugin.midi_events, event)
//                 }
//                 }
//             }

//             event_index += 1

//             if (event_index == event_count) {
//                 next_event_index = frame_count
//                 break
//             }
//         }

//         push_midi_events(plugin, clap_process.frames_count, clap_process.out_events)

//         frame = next_event_index
//     }

//     decrease_midi_events_time(plugin, clap_process.frames_count)

//     return .Continue
// }

plugin_get_extension :: proc "c" (clap_plugin: ^clap.Plugin, id: cstring) -> rawptr {
    switch id {
    case clap.ext_note_ports: return &note_ports_extension
    case clap.ext_latency: return &latency_extension
    case: return nil
    }
}

plugin_on_main_thread :: proc "c" (clap_plugin: ^clap.Plugin) {
}