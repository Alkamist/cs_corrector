package main

import "core:fmt"
import "core:runtime"
import "core:sync"
import "core:slice"
import "core:strings"
import "clap"

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

Plugin_Instance :: struct {
    is_active: bool,
    sample_rate: f64,
    midi_port: int,
    latency: int,
    clap_host: ^clap.Host,
    clap_plugin: clap.Plugin,
    main_thread_parameter_value: [PARAMETER_COUNT]f64,
    main_thread_parameter_changed: [PARAMETER_COUNT]bool,
    audio_thread_parameter_value: [PARAMETER_COUNT]f64,
    audio_thread_parameter_changed: [PARAMETER_COUNT]bool,
    parameter_mutex: sync.Mutex,
    timer_name_to_id: map[string]clap.Id,
    timer_id_to_proc: map[clap.Id]proc(instance: ^Plugin_Instance),
}

instance_init :: proc "c" (plugin: ^clap.Plugin) -> bool {
    context = runtime.default_context()
    instance := get_instance(plugin)

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
    delete(instance.timer_name_to_id)
    delete(instance.timer_id_to_proc)
    free(instance)
}

instance_activate :: proc "c" (plugin: ^clap.Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool {
    instance := get_instance(plugin)
    instance.is_active = true
    instance.sample_rate = sample_rate
    instance.latency = 0
    return true
}

instance_deactivate :: proc "c" (plugin: ^clap.Plugin) {
    // context = runtime.default_context()
    instance := get_instance(plugin)
    instance.is_active = false
}

instance_start_processing :: proc "c" (plugin: ^clap.Plugin) -> bool {
    return true
}

instance_stop_processing :: proc "c" (plugin: ^clap.Plugin) {
}

instance_reset :: proc "c" (plugin: ^clap.Plugin) {
}

instance_process :: proc "c" (plugin: ^clap.Plugin, process: ^clap.Process) -> clap.Process_Status {
    context = runtime.default_context()
    instance := get_instance(plugin)

    frame_count := process.frames_count
    event_count := process.in_events.size(process.in_events)
    event_index: u32 = 0
    next_event_index: u32 = 0
    if event_count == 0 {
        next_event_index = frame_count
    }
    frame: u32 = 0

    parameters_sync_main_to_audio(instance, process.out_events)

    for frame < frame_count {
        for event_index < event_count && next_event_index == frame {
            event_header := process.in_events.get(process.in_events, event_index)
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

                // case .Midi:
                //     event := (cast(^clap.Event_Midi)event_header)
                //     if event.port_index == instance.midi_port {
                //         cs.process_event(&instance.cs_corrector, cs.Midi_Event{
                //             time = int(event.header.time),
                //             data = event.data,
                //         })
                //     }

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

    // context.user_ptr = &Cs_Corrector_Context{
    //     midi_port = plugin.midi_port,
    //     out_events = clap_process.out_events,
    // }
    // cs.push_events(&plugin.cs_corrector, int(frame_count), push_midi_event_from_cs_corrector)

    return .Continue
}

instance_get_extension :: proc "c" (plugin: ^clap.Plugin, id: cstring) -> rawptr {
    switch id {
    case clap.EXT_NOTE_PORTS: return &note_ports_extension
    case clap.EXT_LATENCY: return &latency_extension
    case clap.EXT_PARAMS: return &parameters_extension
    case clap.EXT_TIMER_SUPPORT: return &timer_extension
    // case clap.EXT_GUI: return &gui_extension
    case: return nil
    }
}

instance_on_main_thread :: proc "c" (plugin: ^clap.Plugin) {
}