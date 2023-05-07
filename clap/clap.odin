package clap

import "core:c"

NAME_SIZE :: 256
PATH_SIZE :: 1024
CORE_EVENT_SPACE_ID :: 0
PLUGIN_FACTORY_ID :: "clap.plugin-factory"
EXT_NOTE_PORTS :: "clap.note-ports"
EXT_LATENCY :: "clap.latency"
EXT_PARAMS :: "clap.params"
EXT_TIMER_SUPPORT :: "clap.timer-support"
EXT_STATE :: "clap.state"
EXT_GUI :: "clap.gui"

WINDOW_API_WIN32 :: "win32"
WINDOW_API_COCOA :: "cocoa"
WINDOW_API_X11 :: "x11"
WINDOW_API_WAYLAND :: "wayland"
when ODIN_OS == .Windows {
	WINDOW_API :: WINDOW_API_WIN32
} else when ODIN_OS == .Darwin {
	WINDOW_API :: WINDOW_API_COCOA
} else when ODIN_OS == .Linux {
	WINDOW_API :: WINDOW_API_X11
}

Id :: u32
Beat_Time :: i64
Sec_Time :: i64

version_is_compatible :: proc "c" (v: Version) -> bool {
    return v.major >= 1;
}

Note_Dialect :: enum u32 {
    Clap,
    Midi,
    Midi_Mpe,
    Midi2,
}

Event_Type :: enum u16 {
    Note_On,
    Note_Off,
    Note_Choke,
    Note_End,
    Note_Expression,
    Param_Value,
    Param_Mod,
    Param_Gesture_Begin,
    Param_Gesture_End,
    Transport,
    Midi,
    Midi_Sysex,
    Midi2,
}

Event_Header :: struct {
    size: u32,
    time: u32,
    space_id: u16,
    type: Event_Type,
    flags: u32,
}

Event_Param_Value :: struct {
    header: Event_Header,
    param_id: Id,
    cookie: rawptr,
    note_id: i32,
    port_index: i16,
    channel: i16,
    key: i16,
    value: f64,
}

Event_Midi :: struct {
    header: Event_Header,
    port_index: u16,
    data: [3]u8,
}

Transport_Event_Flags :: enum {
    Has_Tempo,
    Has_Beats_Timeline,
    Has_Seconds_Timeline,
    Has_Time_Signature,
    Is_Playing,
    Is_Recording,
    Is_Loop_Active,
    Is_Within_Pre_Roll,
}

Event_Transport :: struct {
    header: Event_Header,
    flags: bit_set[Transport_Event_Flags; u32],
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
    Error,
    Continue,
    Continue_If_Not_Quiet,
    Tail,
    Sleep,
}

Gui_Resize_Hints :: struct{
    can_resize_horizontally: bool,
    can_resize_vertically: bool,
    preserve_aspect_ratio: bool,
    aspect_ratio_width: u32,
    aspect_ratio_height: u32,
}

Hwnd :: distinct rawptr
Nsview :: distinct rawptr
Xwnd :: c.ulong

Window :: struct {
    api: cstring,
    handle: union{Nsview, Xwnd, Hwnd, rawptr},
}

Plugin_Gui :: struct{
    is_api_supported: proc "c" (plugin: ^Plugin, api: cstring, is_floating: bool) -> bool,
    get_preferred_api: proc "c" (plugin: ^Plugin, api: ^cstring, is_floating: ^bool) -> bool,
    create: proc "c" (plugin: ^Plugin, api: cstring, is_floating: bool) -> bool,
    destroy: proc "c" (plugin: ^Plugin),
    set_scale: proc "c" (plugin: ^Plugin, scale: f64) -> bool,
    get_size: proc "c" (plugin: ^Plugin, width, height: ^u32) -> bool,
    can_resize: proc "c" (plugin: ^Plugin) -> bool,
    get_resize_hints: proc "c" (plugin: ^Plugin, hints: ^Gui_Resize_Hints) -> bool,
    adjust_size: proc "c" (plugin: ^Plugin, width, height: ^u32) -> bool,
    set_size: proc "c" (plugin: ^Plugin, width, height: u32) -> bool,
    set_parent: proc "c" (plugin: ^Plugin, window: ^Window) -> bool,
    set_transient: proc "c" (plugin: ^Plugin, window: ^Window) -> bool,
    suggest_title: proc "c" (plugin: ^Plugin, title: cstring),
    show: proc "c" (plugin: ^Plugin) -> bool,
    hide: proc "c" (plugin: ^Plugin) -> bool,
}

Host_Latency :: struct {
    changed: proc "c" (host: ^Host),
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
    supported_dialects: bit_set[Note_Dialect; u32],
    preferred_dialect: bit_set[Note_Dialect; u32],
    name: [NAME_SIZE]byte,
}

Plugin_Note_Ports :: struct {
    count: proc "c" (plugin: ^Plugin, is_input: bool) -> u32,
    get: proc "c" (plugin: ^Plugin, index: u32, is_input: bool, info: ^Note_Port_Info) -> bool,
}

I_Stream :: struct {
    ctx: rawptr,
    read: proc "c" (stream: ^I_Stream, buffer: rawptr, size: u64) -> i64,
}

O_Stream :: struct {
    ctx: rawptr,
    write: proc "c" (stream: ^O_Stream, buffer: rawptr, size: u64) -> i64,
}

Plugin_State :: struct {
    save: proc "c" (plugin: ^Plugin, stream: ^O_Stream) -> bool,
    load: proc "c" (plugin: ^Plugin, stream: ^I_Stream) -> bool,
}

Param_Info_Flags :: enum u32 {
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

Param_Info :: struct {
    id: Id,
    flags: bit_set[Param_Info_Flags; u32],
    cookie: rawptr,
    name: [NAME_SIZE]byte,
    module: [PATH_SIZE]byte,
    min_value: f64,
    max_value: f64,
    default_value: f64,
}

Plugin_Params :: struct {
    count: proc "c" (plugin: ^Plugin) -> u32,
    get_info: proc "c" (plugin: ^Plugin, param_index: u32, param_info: ^Param_Info) -> bool,
    get_value: proc "c" (plugin: ^Plugin, param_id: Id, out_value: ^f64) -> bool,
    value_to_text: proc "c" (plugin: ^Plugin, param_id: Id, value: f64, out_buffer: [^]byte, out_buffer_capacity: u32) -> bool,
    text_to_value: proc "c" (plugin: ^Plugin, param_id: Id, param_value_text: cstring, out_value: ^f64) -> bool,
    flush: proc "c" (plugin: ^Plugin, input: ^Input_Events, output: ^Output_Events),
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
    features: [^]cstring,
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

Plugin_Timer_Support :: struct {
    on_timer: proc "c" (plugin: ^Plugin, timer_id: Id),
}

Host_Timer_Support :: struct {
    register_timer: proc "c" (host: ^Host, period_ms: u32, timer_id: ^Id) -> bool,
    unregister_timer: proc "c" (host: ^Host, timer_id: Id) -> bool,
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