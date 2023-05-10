// This is a generic interface for an audio plugin.
//
// Define these:
//     ID :: "com.your-company.YourPlugin"
//     NAME :: "Plugin Name"
//     VENDOR :: "Vendor"
//     URL :: "https://your-domain.com/your-plugin"
//     MANUAL_URL :: "https://your-domain.com/your-plugin/manual"
//     SUPPORT_URL :: "https://your-domain.com/support"
//     VERSION :: "1.4.2"
//     DESCRIPTION :: "The plugin description."
//
// Define an enum named Parameter, and info named parameter_info:
//     Parameter :: enum {
//         Gain,
//     }
//     parameter_info := [len(Parameter)]Parameter_Info{
//         {
//             id = .Gain,
//             flags = {.Is_Automatable},
//             name = "Gain",
//             module = "",
//             min_value = 0.0,
//             max_value = 1.0,
//             default_value = 1.0,
//         }
//     }
//
// Implement these:
//     on_create :: proc(plugin: ^Audio_Plugin) {}
//     on_destroy :: proc(plugin: ^Audio_Plugin) {}
//     on_reset :: proc(plugin: ^Audio_Plugin) {}
//     on_parameter_event :: proc(plugin: ^Audio_Plugin, event: Parameter_Event) {}
//     on_transport_event :: proc(plugin: ^Audio_Plugin, event: Transport_Event) {}
//     on_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {}
//     on_process :: proc(plugin: ^Audio_Plugin, frame_count: int) {}
//     save_preset :: proc(plugin: ^Audio_Plugin, builder: ^strings.Builder) -> bool {}
//     load_preset :: proc(plugin: ^Audio_Plugin, data: []byte) {}

package main

import "core:sync"

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
    latency: int,
    is_active: bool,
    clap_plugin: Clap_Plugin,
    clap_host: ^Clap_Host,
    clap_host_log: ^Clap_Host_Log,
    clap_host_latency: ^Clap_Host_Latency,
    clap_host_timer_support: ^Clap_Host_Timer_Support,
    timer_name_to_id: map[string]Clap_Id,
    timer_id_to_proc: map[Clap_Id]proc(plugin: ^Audio_Plugin),
    parameter_mutex: sync.Mutex,
    main_thread_parameter_value: [Parameter]f64,
    main_thread_parameter_changed: [Parameter]bool,
    audio_thread_parameter_value: [Parameter]f64,
    audio_thread_parameter_changed: [Parameter]bool,
    output_midi_events: [dynamic]Clap_Event_Midi,
}

milliseconds_to_samples :: proc(plugin: ^Audio_Plugin, milliseconds: f64) -> int {
    return int(plugin.sample_rate * milliseconds * 0.001)
}

write_string :: proc "c" (buffer: []byte, value: string) {
    n := copy(buffer, value)
    // Make it null terminated
    buffer[min(n, len(buffer) - 1)] = 0
}

audio_plugin_base_init :: proc(plugin: ^Audio_Plugin_Base) {
    for parameter in Parameter {
        plugin.audio_thread_parameter_value[parameter] = parameter_info[parameter].default_value
        plugin.main_thread_parameter_value[parameter] = parameter_info[parameter].default_value
    }
}

audio_plugin_base_destroy :: proc(plugin: ^Audio_Plugin_Base) {
    delete(plugin.timer_name_to_id)
    delete(plugin.timer_id_to_proc)
    free(plugin)
}