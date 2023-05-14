package audio_plugin

import "core:c"

CLAP_NAME_SIZE :: 256
CLAP_PATH_SIZE :: 1024
CLAP_CORE_EVENT_SPACE_ID :: 0
CLAP_PLUGIN_FACTORY_ID :: "clap.plugin-factory"
CLAP_EXT_NOTE_PORTS :: "clap.note-ports"
CLAP_EXT_LATENCY :: "clap.latency"
CLAP_EXT_PARAMS :: "clap.params"
CLAP_EXT_TIMER_SUPPORT :: "clap.timer-support"
CLAP_EXT_STATE :: "clap.state"
CLAP_EXT_GUI :: "clap.gui"
CLAP_EXT_LOG :: "clap.log"

CLAP_WINDOW_API_WIN32 :: "win32"
CLAP_WINDOW_API_COCOA :: "cocoa"
CLAP_WINDOW_API_X11 :: "x11"
CLAP_WINDOW_API_WAYLAND :: "wayland"
when ODIN_OS == .Windows {
	CLAP_WINDOW_API :: CLAP_WINDOW_API_WIN32
} else when ODIN_OS == .Darwin {
	CLAP_WINDOW_API :: CLAP_WINDOW_API_COCOA
} else when ODIN_OS == .Linux {
	CLAP_WINDOW_API :: CLAP_WINDOW_API_X11
}

CLAP_PLUGIN_FEATURE_INSTRUMENT :: "instrument"
CLAP_PLUGIN_FEATURE_AUDIO_EFFECT :: "audio-effect"
CLAP_PLUGIN_FEATURE_NOTE_EFFECT :: "note-effect"
CLAP_PLUGIN_FEATURE_NOTE_DETECTOR :: "note-detector"
CLAP_PLUGIN_FEATURE_ANALYZER :: "analyzer"
CLAP_PLUGIN_FEATURE_SYNTHESIZER :: "synthesizer"
CLAP_PLUGIN_FEATURE_SAMPLER :: "sampler"
CLAP_PLUGIN_FEATURE_DRUM :: "drum"
CLAP_PLUGIN_FEATURE_DRUM_MACHINE :: "drum-machine"
CLAP_PLUGIN_FEATURE_FILTER :: "filter"
CLAP_PLUGIN_FEATURE_PHASER :: "phaser"
CLAP_PLUGIN_FEATURE_EQUALIZER :: "equalizer"
CLAP_PLUGIN_FEATURE_DEESSER :: "de-esser"
CLAP_PLUGIN_FEATURE_PHASE_VOCODER :: "phase-vocoder"
CLAP_PLUGIN_FEATURE_GRANULAR :: "granular"
CLAP_PLUGIN_FEATURE_FREQUENCY_SHIFTER :: "frequency-shifter"
CLAP_PLUGIN_FEATURE_PITCH_SHIFTER :: "pitch-shifter"
CLAP_PLUGIN_FEATURE_DISTORTION :: "distortion"
CLAP_PLUGIN_FEATURE_TRANSIENT_SHAPER :: "transient-shaper"
CLAP_PLUGIN_FEATURE_COMPRESSOR :: "compressor"
CLAP_PLUGIN_FEATURE_EXPANDER :: "expander"
CLAP_PLUGIN_FEATURE_GATE :: "gate"
CLAP_PLUGIN_FEATURE_LIMITER :: "limiter"
CLAP_PLUGIN_FEATURE_FLANGER :: "flanger"
CLAP_PLUGIN_FEATURE_CHORUS :: "chorus"
CLAP_PLUGIN_FEATURE_DELAY :: "delay"
CLAP_PLUGIN_FEATURE_REVERB :: "reverb"
CLAP_PLUGIN_FEATURE_TREMOLO :: "tremolo"
CLAP_PLUGIN_FEATURE_GLITCH :: "glitch"
CLAP_PLUGIN_FEATURE_UTILITY :: "utility"
CLAP_PLUGIN_FEATURE_PITCH_CORRECTION :: "pitch-correction"
CLAP_PLUGIN_FEATURE_RESTORATION :: "restoration"
CLAP_PLUGIN_FEATURE_MULTI_EFFECTS :: "multi-effects"
CLAP_PLUGIN_FEATURE_MIXING :: "mixing"
CLAP_PLUGIN_FEATURE_MASTERING :: "mastering"
CLAP_PLUGIN_FEATURE_MONO :: "mono"
CLAP_PLUGIN_FEATURE_STEREO :: "stereo"
CLAP_PLUGIN_FEATURE_SURROUND :: "surround"
CLAP_PLUGIN_FEATURE_AMBISONIC :: "ambisonic"

CLAP_BEATTIME_FACTOR :: 1 << 31
CLAP_SECTIME_FACTOR :: 1 << 31

Clap_Id :: u32
Clap_Beat_Time :: i64
Clap_Sec_Time :: i64

clap_version_is_compatible :: proc "c" (v: Clap_Version) -> bool {
    return v.major >= 1;
}

Clap_Note_Dialect :: enum u32 {
    Clap,
    Midi,
    Midi_Mpe,
    Midi2,
}

Clap_Event_Type :: enum u16 {
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

Clap_Event_Header :: struct {
    size: u32,
    time: u32,
    space_id: u16,
    type: Clap_Event_Type,
    flags: u32,
}

Clap_Event_Param_Value :: struct {
    header: Clap_Event_Header,
    param_id: Clap_Id,
    cookie: rawptr,
    note_id: i32,
    port_index: i16,
    channel: i16,
    key: i16,
    value: f64,
}

Clap_Event_Midi :: struct {
    header: Clap_Event_Header,
    port_index: u16,
    data: [3]u8,
}

Clap_Transport_Event_Flag :: enum {
    Has_Tempo,
    Has_Beats_Timeline,
    Has_Seconds_Timeline,
    Has_Time_Signature,
    Is_Playing,
    Is_Recording,
    Is_Loop_Active,
    Is_Within_Pre_Roll,
}

Clap_Event_Transport :: struct {
    header: Clap_Event_Header,
    flags: bit_set[Clap_Transport_Event_Flag; u32],
    song_pos_beats: Clap_Beat_Time,
    song_pos_seconds: Clap_Sec_Time,
    tempo: f64,
    tempo_inc: f64,
    loop_start_beats: Clap_Beat_Time,
    loop_end_beats: Clap_Beat_Time,
    loop_start_seconds: Clap_Sec_Time,
    loop_end_seconds: Clap_Sec_Time,
    bar_start: Clap_Beat_Time,
    bar_number: i32,
    tsig_num: u16,
    tsig_denom: u16,
}

Clap_Audio_Buffer :: struct {
    data32: [^][^]f32,
    data64: [^][^]f64,
    channel_count: u32,
    latency: u32,
    constant_mask: u64,
}

Clap_Input_Events :: struct {
    ctx: rawptr,
    size: proc "c" (list: ^Clap_Input_Events) -> u32,
    get: proc "c" (list: ^Clap_Input_Events, index: u32) -> ^Clap_Event_Header,
}

Clap_Output_Events :: struct {
    ctx: rawptr,
    try_push: proc "c" (list: ^Clap_Output_Events, event: ^Clap_Event_Header) -> bool,
}

Clap_Process_Status :: enum i32 {
    Error,
    Continue,
    Continue_If_Not_Quiet,
    Tail,
    Sleep,
}

Clap_Gui_Resize_Hints :: struct{
    can_resize_horizontally: bool,
    can_resize_vertically: bool,
    preserve_aspect_ratio: bool,
    aspect_ratio_width: u32,
    aspect_ratio_height: u32,
}

Clap_Hwnd :: distinct rawptr
Clap_Nsview :: distinct rawptr
Clap_Xwnd :: c.ulong

Clap_Window :: struct {
    api: cstring,
    handle: union{Clap_Nsview, Clap_Xwnd, Clap_Hwnd, rawptr},
}

Clap_Plugin_Gui :: struct{
    is_api_supported: proc "c" (plugin: ^Clap_Plugin, api: cstring, is_floating: bool) -> bool,
    get_preferred_api: proc "c" (plugin: ^Clap_Plugin, api: ^cstring, is_floating: ^bool) -> bool,
    create: proc "c" (plugin: ^Clap_Plugin, api: cstring, is_floating: bool) -> bool,
    destroy: proc "c" (plugin: ^Clap_Plugin),
    set_scale: proc "c" (plugin: ^Clap_Plugin, scale: f64) -> bool,
    get_size: proc "c" (plugin: ^Clap_Plugin, width, height: ^u32) -> bool,
    can_resize: proc "c" (plugin: ^Clap_Plugin) -> bool,
    get_resize_hints: proc "c" (plugin: ^Clap_Plugin, hints: ^Clap_Gui_Resize_Hints) -> bool,
    adjust_size: proc "c" (plugin: ^Clap_Plugin, width, height: ^u32) -> bool,
    set_size: proc "c" (plugin: ^Clap_Plugin, width, height: u32) -> bool,
    set_parent: proc "c" (plugin: ^Clap_Plugin, window: ^Clap_Window) -> bool,
    set_transient: proc "c" (plugin: ^Clap_Plugin, window: ^Clap_Window) -> bool,
    suggest_title: proc "c" (plugin: ^Clap_Plugin, title: cstring),
    show: proc "c" (plugin: ^Clap_Plugin) -> bool,
    hide: proc "c" (plugin: ^Clap_Plugin) -> bool,
}

Clap_Host_Latency :: struct {
    changed: proc "c" (host: ^Clap_Host),
}

Clap_Plugin_Latency :: struct {
    get: proc "c" (plugin: ^Clap_Plugin) -> u32,
}

Clap_Process :: struct {
    steady_time: i64,
    frames_count: u32,
    transport: ^Clap_Event_Transport,
    audio_inputs: [^]Clap_Audio_Buffer,
    audio_outputs: [^]Clap_Audio_Buffer,
    audio_inputs_count: u32,
    audio_outputs_count: u32,
    in_events: ^Clap_Input_Events,
    out_events: ^Clap_Output_Events,
}

Clap_Note_Port_Info :: struct {
    id: Clap_Id,
    supported_dialects: bit_set[Clap_Note_Dialect; u32],
    preferred_dialect: bit_set[Clap_Note_Dialect; u32],
    name: [CLAP_NAME_SIZE]byte,
}

Clap_Plugin_Note_Ports :: struct {
    count: proc "c" (plugin: ^Clap_Plugin, is_input: bool) -> u32,
    get: proc "c" (plugin: ^Clap_Plugin, index: u32, is_input: bool, info: ^Clap_Note_Port_Info) -> bool,
}

Clap_Istream :: struct {
    ctx: rawptr,
    read: proc "c" (stream: ^Clap_Istream, buffer: rawptr, size: u64) -> i64,
}

Clap_Ostream :: struct {
    ctx: rawptr,
    write: proc "c" (stream: ^Clap_Ostream, buffer: rawptr, size: u64) -> i64,
}

Clap_Plugin_State :: struct {
    save: proc "c" (plugin: ^Clap_Plugin, stream: ^Clap_Ostream) -> bool,
    load: proc "c" (plugin: ^Clap_Plugin, stream: ^Clap_Istream) -> bool,
}

Clap_Log_Severity :: enum {
    Debug,
    Info,
    Warning,
    Error,
    Fatal,
    Host_Misbehaving,
    Plugin_Misbehaving,
}

Clap_Host_Log :: struct {
    log: proc "c" (host: ^Clap_Host, severity: Clap_Log_Severity, msg: cstring),
}

Clap_Param_Info_Flag :: enum u32 {
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

Clap_Param_Info :: struct {
    id: Clap_Id,
    flags: bit_set[Clap_Param_Info_Flag; u32],
    cookie: rawptr,
    name: [CLAP_NAME_SIZE]byte,
    module: [CLAP_PATH_SIZE]byte,
    min_value: f64,
    max_value: f64,
    default_value: f64,
}

Clap_Plugin_Params :: struct {
    count: proc "c" (plugin: ^Clap_Plugin) -> u32,
    get_info: proc "c" (plugin: ^Clap_Plugin, param_index: u32, param_info: ^Clap_Param_Info) -> bool,
    get_value: proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, out_value: ^f64) -> bool,
    value_to_text: proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, value: f64, out_buffer: [^]byte, out_buffer_capacity: u32) -> bool,
    text_to_value: proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, param_value_text: cstring, out_value: ^f64) -> bool,
    flush: proc "c" (plugin: ^Clap_Plugin, input: ^Clap_Input_Events, output: ^Clap_Output_Events),
}

Clap_Plugin_Descriptor :: struct {
    clap_version: Clap_Version,
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

Clap_Plugin :: struct {
    desc: ^Clap_Plugin_Descriptor,
    plugin_data: rawptr,
    init: proc "c" (plugin: ^Clap_Plugin) -> bool,
    destroy: proc "c" (plugin: ^Clap_Plugin),
    activate: proc "c" (plugin: ^Clap_Plugin, sample_rate: f64, min_frames_count, max_frames_count: u32) -> bool,
    deactivate: proc "c" (plugin: ^Clap_Plugin),
    start_processing: proc "c" (plugin: ^Clap_Plugin) -> bool,
    stop_processing: proc "c" (plugin: ^Clap_Plugin),
    reset: proc "c" (plugin: ^Clap_Plugin),
    process: proc "c" (plugin: ^Clap_Plugin, process: ^Clap_Process) -> Clap_Process_Status,
    get_extension: proc "c" (plugin: ^Clap_Plugin, id: cstring) -> rawptr,
    on_main_thread: proc "c" (plugin: ^Clap_Plugin),
}

Clap_Version :: struct {
    major: u32,
    minor: u32,
    revision: u32,
}

Clap_Plugin_Timer_Support :: struct {
    on_timer: proc "c" (plugin: ^Clap_Plugin, timer_id: Clap_Id),
}

Clap_Host_Timer_Support :: struct {
    register_timer: proc "c" (host: ^Clap_Host, period_ms: u32, timer_id: ^Clap_Id) -> bool,
    unregister_timer: proc "c" (host: ^Clap_Host, timer_id: Clap_Id) -> bool,
}

Clap_Host :: struct {
    clap_version: Clap_Version,
    host_data: rawptr,
    name: cstring,
    vendor: cstring,
    url: cstring,
    version: cstring,
    get_extension: proc "c" (host: ^Clap_Host, extension_id: cstring) -> rawptr,
    request_restart: proc "c" (host: ^Clap_Host),
    request_process: proc "c" (host: ^Clap_Host),
    request_callback: proc "c" (host: ^Clap_Host),
}

Clap_Plugin_Factory :: struct {
    get_plugin_count: proc "c" (factory: ^Clap_Plugin_Factory) -> u32,
    get_plugin_descriptor: proc "c" (factory: ^Clap_Plugin_Factory, index: u32) -> ^Clap_Plugin_Descriptor,
    create_plugin: proc "c" (factory: ^Clap_Plugin_Factory, host: ^Clap_Host, plugin_id: cstring) -> ^Clap_Plugin,
}

Clap_Plugin_Entry :: struct {
    clap_version: Clap_Version,
    init: proc "c" (plugin_path: cstring) -> bool,
    deinit: proc "c" (),
    get_factory: proc "c" (factory_id: cstring) -> rawptr,
}