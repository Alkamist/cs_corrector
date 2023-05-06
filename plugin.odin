package main

import "core:fmt"
import "core:runtime"
import "core:sync"
import "core:slice"
import "core:strings"
import "clap"
import "midi"
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

Plugin_Instance :: struct {
    is_active: bool,
    sample_rate: f64,
    midi_port: int,
    latency: int,
    cs_corrector: cs.State,
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

cs_corrector_encode_midi_message :: proc(msg: ^cs.Note_Event) -> midi.Encoded_Message {
    kind: midi.Note_Message_Kind
    switch msg.kind {
    case .On: kind = .On
    case .Off: kind = .Off
    }
    return midi.encode_note_message(midi.Note_Message{
        kind = kind,
        channel = 0,
        key = msg.key,
        velocity = msg.velocity,
    })
}

on_midi_event :: proc(instance: ^Plugin_Instance, process: ^clap.Process, event: ^clap.Event_Midi) {
    if event.port_index == u16(instance.midi_port) {
        note_message, ok := midi.decode_note_message(event.data)
        if ok {
            switch note_message.kind {
            case .Off:
                cs.process_note_off(
                    &instance.cs_corrector,
                    int(event.header.time),
                    note_message.key,
                    note_message.velocity,
                )
            case .On:
                cs.process_note_on(
                    &instance.cs_corrector,
                    int(event.header.time),
                    note_message.key,
                    note_message.velocity,
                )
            }
        } else {
            process.out_events->try_push(&event.header)
        }
    }
}

on_process :: proc(instance: ^Plugin_Instance, process: ^clap.Process) {
    frame_count := int(process.frames_count)
    note_events := cs.extract_note_events(&instance.cs_corrector, frame_count)
    defer delete(note_events)

    // for event in note_events {
    //     clap_event := clap.Event_Midi{
    //         header = {
    //             size = size_of(clap.Event_Midi),
    //             time = u32(event.time),
    //             space_id = clap.CORE_EVENT_SPACE_ID,
    //             type = .Midi,
    //             flags = 0,
    //         },
    //         port_index = u16(instance.midi_port),
    //         data = cs_corrector_encode_midi_message(event),
    //     }
    //     process.out_events->try_push(&clap_event.header)
    // }
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
    cs.destroy(&instance.cs_corrector)
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
    context = runtime.default_context()
    instance := get_instance(plugin)
    instance.is_active = false
    cs.reset(&instance.cs_corrector)
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
    // case clap.EXT_GUI: return &gui_extension
    case: return nil
    }
}

instance_on_main_thread :: proc "c" (plugin: ^clap.Plugin) {
}