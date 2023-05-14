package audio_plugin

import "core:strings"

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
    kind: Parameter_Event_Kind,
    id: int,
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
    id: int,
    name: string,
    min_value: f64,
    max_value: f64,
    default_value: f64,
    flags: bit_set[Parameter_Flag],
    module: string,
}

Audio_Plugin_VTable :: struct {
	on_init: proc(plugin: ^Audio_Plugin),
    on_destroy: proc(plugin: ^Audio_Plugin),
    on_activate: proc(plugin: ^Audio_Plugin),
    on_deactivate: proc(plugin: ^Audio_Plugin),
    on_reset: proc(plugin: ^Audio_Plugin),
    on_parameter_event: proc(plugin: ^Audio_Plugin, event: Parameter_Event),
    on_transport_event: proc(plugin: ^Audio_Plugin, event: Transport_Event),
    on_midi_event: proc(plugin: ^Audio_Plugin, event: Midi_Event),
    // on_process: proc(plugin: ^Audio_Plugin, frame_count: int),
    save_preset: proc(plugin: ^Audio_Plugin, builder: ^strings.Builder) -> bool,
    load_preset: proc(plugin: ^Audio_Plugin, data: []byte),
}