package main

import "core:fmt"
import "core:sync"
import "core:strings"
import nq "note_queue"
import "reaper"

// =====================================================================
ID :: "com.alkamist.CssCorrector"
NAME :: "Css Corrector"
VENDOR :: "Alkamist Audio"
URL :: ""
MANUAL_URL :: ""
SUPPORT_URL :: ""
VERSION :: "0.1.0"
DESCRIPTION :: "A MIDI timing corrector for Cinematic Studio Strings."
// =====================================================================

Parameter :: enum {
    Legato_First_Note_Delay,
    Legato_Portamento_Delay,
    Legato_Slow_Delay,
    Legato_Medium_Delay,
    Legato_Fast_Delay,
}

Audio_Plugin :: struct {
    using base: Audio_Plugin_Base,
    is_playing: bool,
    was_playing: bool,
    debug_string_mutex: sync.Mutex,
    debug_string_builder: strings.Builder,
    debug_string_changed: bool,
    logic: Cs_Corrector_Logic,
}

on_create :: proc(plugin: ^Audio_Plugin) {
    reaper_plugin_info := cast(^reaper.Plugin_Info)plugin.clap_host->get_extension("cockos.reaper_extension")
    reaper.load_functions(reaper_plugin_info)

    plugin.debug_string_builder = strings.builder_make_none()

    register_timer(plugin, "Debug_Timer", 0, proc(plugin: ^Audio_Plugin) {
        if plugin.debug_string_changed {
            sync.lock(&plugin.debug_string_mutex)
            debug_cstring := strings.clone_to_cstring(strings.to_string(plugin.debug_string_builder))
            defer delete(debug_cstring)
            reaper.show_console_msg(debug_cstring)
            strings.builder_reset(&plugin.debug_string_builder)
            plugin.debug_string_changed = false
            sync.unlock(&plugin.debug_string_mutex)
        }
    })

    plugin.logic.plugin = plugin
    plugin.logic.note_queue = nq.create(0, 1024)
    plugin.logic.legato_delay_velocities[0] = 20
    plugin.logic.legato_delay_velocities[1] = 64
    plugin.logic.legato_delay_velocities[2] = 100
    plugin.logic.legato_delay_velocities[3] = 128
    update_logic_parameters(plugin)
}

on_destroy :: proc(plugin: ^Audio_Plugin) {
    unregister_timer(plugin, "Debug_Timer")
    strings.builder_destroy(&plugin.debug_string_builder)
    cs_corrector_destroy(&plugin.logic)
}

on_activate :: proc(plugin: ^Audio_Plugin) {
    update_logic_parameters(plugin)
}

on_deactivate :: proc(plugin: ^Audio_Plugin) {
}

on_reset :: proc(plugin: ^Audio_Plugin) {
    cs_corrector_reset(&plugin.logic)
}

on_parameter_event :: proc(plugin: ^Audio_Plugin, event: Parameter_Event) {
    update_logic_parameters(plugin)
}

on_transport_event :: proc(plugin: ^Audio_Plugin, event: Transport_Event) {
    process_transport_event(&plugin.logic, event)
}

on_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {
    process_midi_event(&plugin.logic, event)
}

on_process :: proc(plugin: ^Audio_Plugin, frame_count: int) {
    send_note_events(&plugin.logic, frame_count)
}

save_preset :: proc(plugin: ^Audio_Plugin, builder: ^strings.Builder) -> bool {
    preset := Css_Corrector_Preset_V1{
        size = size_of(Css_Corrector_Preset_V1),
        preset_version = 1,
        parameter_offset = i64le(offset_of(Css_Corrector_Preset_V1, parameters)),
        parameter_count = len(Parameter),
    }
    for id in Parameter {
        preset.parameters[id] = f64le(parameter(plugin, id))
    }
    preset_data := transmute([size_of(preset)]byte)preset
    strings.write_bytes(builder, preset_data[:])
    return true
}

load_preset :: proc(plugin: ^Audio_Plugin, data: []byte) {
    preset := (cast(^Css_Corrector_Preset_V1)&data[0])^
    for id in Parameter {
        set_parameter(plugin, id, f64(preset.parameters[id]))
    }
    update_logic_parameters(plugin)
}

parameter_info := [len(Parameter)]Parameter_Info{
    make_param(.Legato_First_Note_Delay, "Legato First Note Delay", -60.0),
    make_param(.Legato_Portamento_Delay, "Legato Portamento Delay", -300.0),
    make_param(.Legato_Slow_Delay, "Legato Slow Delay", -300.0),
    make_param(.Legato_Medium_Delay, "Legato Medium Delay", -300.0),
    make_param(.Legato_Fast_Delay, "Legato Fast Delay", -150.0),
}

make_param :: proc(id: Parameter, name: string, default_value: f64) -> Parameter_Info {
    return {id, name, -500.0, 500.0, default_value, {.Is_Automatable}, ""}
}

debug :: proc(plugin: ^Audio_Plugin, arg: any) {
    msg := fmt.aprint(arg)
    defer delete(msg)
    msg_with_newline := strings.concatenate({msg, "\n"})
    defer delete(msg_with_newline)
    sync.lock(&plugin.debug_string_mutex)
    strings.write_string(&plugin.debug_string_builder, msg_with_newline)
    plugin.debug_string_changed = true
    sync.unlock(&plugin.debug_string_mutex)
}

update_logic_parameters :: proc(plugin: ^Audio_Plugin) {
    plugin.logic.legato_first_note_delay = milliseconds_to_samples(plugin, parameter(plugin, .Legato_First_Note_Delay))
    plugin.logic.legato_delay_times[0] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Portamento_Delay))
    plugin.logic.legato_delay_times[1] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Slow_Delay))
    plugin.logic.legato_delay_times[2] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Medium_Delay))
    plugin.logic.legato_delay_times[3] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Fast_Delay))
    set_latency(plugin, required_latency(&plugin.logic))
}





Css_Corrector_Preset_V1 :: struct {
    size: i64le,
    preset_version: i64le,
    parameter_offset: i64le,
    parameter_count: i64le,
    parameters: [Parameter]f64le,
}