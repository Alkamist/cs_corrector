package main

import "core:runtime"

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
    audio_plugin_base_init(plugin)
    // plugin.clap_host_log = cast(^Clap_Host_Log)(plugin.clap_host->get_extension(CLAP_EXT_LOG))
    plugin.clap_host_timer_support = cast(^Clap_Host_Timer_Support)plugin.clap_host->get_extension(CLAP_EXT_TIMER_SUPPORT)
    plugin.clap_host_latency = cast(^Clap_Host_Latency)(plugin.clap_host->get_extension(CLAP_EXT_LATENCY))
    on_create(plugin)
    return true
}

clap_plugin_destroy :: proc "c" (plugin: ^Clap_Plugin) {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    on_destroy(plugin)
    audio_plugin_base_destroy(plugin)
}

clap_plugin_activate :: proc "c" (plugin: ^Clap_Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    plugin.sample_rate = sample_rate
    plugin.is_active = true
    return true
}

clap_plugin_deactivate :: proc "c" (plugin: ^Clap_Plugin) {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    plugin.is_active = false
}

clap_plugin_start_processing :: proc "c" (plugin: ^Clap_Plugin) -> bool {
    return true
}

clap_plugin_stop_processing :: proc "c" (plugin: ^Clap_Plugin) {
}

clap_plugin_reset :: proc "c" (plugin: ^Clap_Plugin) {
    context = runtime.default_context()
    plugin := get_instance(plugin)
    on_reset(plugin)
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

    parameters_sync_main_to_audio(plugin, process.out_events)
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

        // Audio processing will happen here eventually

        frame = next_event_index
    }

    on_process(plugin, int(frame_count))
    send_output_midi_events_to_host(plugin, process.out_events)

    return .Continue
}

clap_plugin_get_extension :: proc "c" (plugin: ^Clap_Plugin, id: cstring) -> rawptr {
    switch id {
    case CLAP_EXT_NOTE_PORTS: return &clap_extension_note_ports
    case CLAP_EXT_LATENCY: return &clap_extension_latency
    case CLAP_EXT_PARAMS: return &clap_extension_parameters
    case CLAP_EXT_TIMER_SUPPORT: return &clap_extension_timer
    // case CLAP_EXT_STATE: return &clap_extension_state
    // case CLAP_EXT_GUI: return &clap_extension_gui
    case: return nil
    }
}

clap_plugin_on_main_thread :: proc "c" (plugin: ^Clap_Plugin) {
}

send_output_midi_events_to_host :: proc(plugin: ^Audio_Plugin, out_events: ^Clap_Output_Events) {
    for event in &plugin.output_midi_events {
        out_events->try_push(&event.header)
    }
    resize(&plugin.output_midi_events, 0)
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
            event.song_position_beats = _from_beat_time(clap_event.song_pos_beats)
            event.loop_start_beats = _from_beat_time(clap_event.loop_start_beats)
            event.loop_end_beats = _from_beat_time(clap_event.loop_end_beats)
            event.bar_start_beats = _from_beat_time(clap_event.bar_start)
            event.bar_number = int(clap_event.bar_number)
        }
        if .Has_Seconds_Timeline in clap_event.flags {
            event.song_position_seconds = _from_sec_time(clap_event.song_pos_seconds)
            event.loop_start_seconds = _from_sec_time(clap_event.loop_start_seconds)
            event.loop_end_seconds = _from_sec_time(clap_event.loop_end_seconds)
        }
        on_transport_event(plugin, event)
    }
}

_from_beat_time :: proc(time: Clap_Beat_Time) -> f64 {
    return f64(time) / f64(CLAP_BEATTIME_FACTOR)
}

_from_sec_time :: proc(time: Clap_Beat_Time) -> f64 {
    return f64(time) / f64(CLAP_SECTIME_FACTOR)
}