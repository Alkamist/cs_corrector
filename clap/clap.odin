package clap

name_size :: 256
path_size :: 1024
plugin_factory_id :: "clap.plugin-factory"
ext_note_ports :: "clap.note-ports"
ext_latency :: "clap.latency"
core_event_space_id :: 0

// make_name :: proc(name: string) -> [name_size]u8 {
//     name_len := len(name)
//     result: [name_size]u8
//     for i in 0 ..< name_size {
//         if i < name_len {
//             result[i] = name[i]
//         } else {
//             result[i] = 0
//         }
//     }
//     return result
// }

// write_name :: proc(name_slot: ^[name_size]u8, name: string) {
//     name_len := len(name)
//     for i in 0 ..< name_size {
//         if i < name_len {
//             name_slot[i] = name[i]
//         } else {
//             name_slot[i] = 0
//         }
//     }
// }

Note_Dialect :: enum u32 {
    Clap,
    Midi,
    Midi_Mpe,
    Midi2,
}

Event_Type :: enum u16 {
    Note_On = 0,
    Note_Off = 1,
    Note_Choke = 2,
    Note_End = 3,
    Note_Expression = 4,
    Param_Value = 5,
    Param_Mod = 6,
    Param_Gesture_Begin = 7,
    Param_Gesture_End = 8,
    Transport = 9,
    Midi = 10,
    Midi_Sysex = 11,
    Midi2 = 12,
}

version_is_compatible :: proc "c" (v: Version) -> bool {
    // versions 0.x.y were used during development stage and aren't compatible
    return v.major >= 1;
}

Id :: u32

Event_Header :: struct {
    size: u32,
    time: u32,
    space_id: u16,
    type: Event_Type,
    flags: u32,
}

Event_Midi :: struct {
    header: Event_Header,
    port_index: u16,
    data: [3]u8,
}

Beat_Time :: i64
Sec_Time :: i64

Event_Transport :: struct {
    header: Event_Header,
    flags: u32,
    song_pos_beats: Beat_Time,
    song_pos_seconds: Sec_Time,
    tempo: f64,
    tempo_inc: f64,
    loop_start_beats: Beat_Time,
    loop_end_beats: Beat_Time,
    loop_start_seconds: Sec_Time,
    loop_end_seconds: Sec_Time,
    bar_start: Beat_Time,
    bar_number: i32,
    tsig_num: u16,
    tsig_denom: u16,
}

Audio_Buffer :: struct {
    data32: [^][^]f32,
    data64: [^][^]f64,
    channel_count: u32,
    latency: u32,
    constant_mask: u64,
}

Input_Events :: struct {
    ctx: rawptr,
    size: proc "c" (list: ^Input_Events) -> u32,
    get: proc "c" (list: ^Input_Events, index: u32) -> ^Event_Header,
}

Output_Events :: struct {
    ctx: rawptr,
    try_push: proc "c" (list: ^Output_Events, event: ^Event_Header) -> bool,
}

Process_Status :: enum i32 {
    Error = 0,

    // Processing succeeded, keep processing.
    Continue = 1,

    // Processing succeeded, keep processing if the output is not quiet.
    Continue_If_Not_Quiet = 2,

    // Rely upon the plugin's tail to determine if the plugin should continue to process.
    // see clap_plugin_tail
    Tail = 3,

    // Processing succeeded, but no more processing is required,
    // until the next event or variation in audio input.
    Sleep = 4,
}

Plugin_Latency :: struct {
    get: proc "c" (plugin: ^Plugin) -> u32,
}

Process :: struct {
    steady_time: i64,
    frames_count: u32,
    transport: ^Event_Transport,
    audio_inputs: [^]Audio_Buffer,
    audio_outputs: [^]Audio_Buffer,
    audio_inputs_count: u32,
    audio_outputs_count: u32,
    in_events: ^Input_Events,
    out_events: ^Output_Events,
}

Note_Port_Info :: struct {
    id: Id,
    supported_dialects: bit_set[Note_Dialect],
    preferred_dialect: bit_set[Note_Dialect],
    name: [name_size]u8,
}

Plugin_Note_Ports :: struct {
    count: proc "c" (plugin: ^Plugin, is_input: bool) -> u32,
    get: proc "c" (plugin: ^Plugin, index: u32, is_input: bool, info: ^Note_Port_Info) -> bool,
}

Plugin_Descriptor :: struct {
    clap_version: Version,
    id: cstring,
    name: cstring,
    vendor: cstring,
    url: cstring,
    manual_url: cstring,
    support_url: cstring,
    version: cstring,
    description: cstring,
    features: ^cstring,
}

Plugin :: struct {
    desc: ^Plugin_Descriptor,
    plugin_data: rawptr,
    init: proc "c" (plugin: ^Plugin) -> bool,
    destroy: proc "c" (plugin: ^Plugin),
    activate: proc "c" (plugin: ^Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool,
    deactivate: proc "c" (plugin: ^Plugin),
    start_processing: proc "c" (plugin: ^Plugin) -> bool,
    stop_processing: proc "c" (plugin: ^Plugin),
    reset: proc "c" (plugin: ^Plugin),
    process: proc "c" (plugin: ^Plugin, process: ^Process) -> Process_Status,
    get_extension: proc "c" (plugin: ^Plugin, id: cstring) -> rawptr,
    on_main_thread: proc "c" (plugin: ^Plugin),
}

Version :: struct {
    major: u32,
    minor: u32,
    revision: u32,
}

Host :: struct {
    clap_version: Version,
    host_data: rawptr,
    name: cstring,
    vendor: cstring,
    url: cstring,
    version: cstring,
    get_extension: proc "c" (host: ^Host, extension_id: cstring) -> rawptr,
    request_restart: proc "c" (host: ^Host),
    request_process: proc "c" (host: ^Host),
    request_callback: proc "c" (host: ^Host),
}

Plugin_Factory :: struct {
    get_plugin_count: proc "c" (factory: ^Plugin_Factory) -> u32,
    get_plugin_descriptor: proc "c" (factory: ^Plugin_Factory, index: u32) -> ^Plugin_Descriptor,
    create_plugin: proc "c" (factory: ^Plugin_Factory, host: ^Host, plugin_id: cstring) -> ^Plugin,
}

Plugin_Entry :: struct {
    clap_version: Version,
    init: proc "c" (plugin_path: cstring) -> bool,
    deinit: proc "c" (),
    get_factory: proc "c" (factory_id: cstring) -> rawptr,
}