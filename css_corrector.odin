package main

import "core:fmt"
import "core:sync"
import "core:strings"
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
    debug_string_mutex: sync.Mutex,
    debug_string_builder: strings.Builder,
    debug_string_changed: bool,
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
}

on_destroy :: proc(plugin: ^Audio_Plugin) {
    unregister_timer(plugin, "Debug_Timer")
    strings.builder_destroy(&plugin.debug_string_builder)
}

on_activate :: proc(plugin: ^Audio_Plugin) {
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
}

on_deactivate :: proc(plugin: ^Audio_Plugin) {
}

on_reset :: proc(plugin: ^Audio_Plugin) {
}

on_parameter_event :: proc(plugin: ^Audio_Plugin, event: Parameter_Event) {
}

on_transport_event :: proc(plugin: ^Audio_Plugin, event: Transport_Event) {
    // debug(plugin, fmt.tprint(event))
    // free_all(context.temp_allocator)
}

on_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {
    send_midi_event(plugin, event)
}

save_preset :: proc(plugin: ^Audio_Plugin, builder: ^strings.Builder) -> bool {
    return false
}

load_preset :: proc(plugin: ^Audio_Plugin, data: []byte) {
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

debug :: proc(plugin: ^Audio_Plugin, msg: string) {
    msg_with_newline := strings.concatenate({msg, "\n"})
    defer delete(msg_with_newline)
    sync.lock(&plugin.debug_string_mutex)
    strings.write_string(&plugin.debug_string_builder, msg_with_newline)
    plugin.debug_string_changed = true
    sync.unlock(&plugin.debug_string_mutex)
}