package main

import "core:fmt"
import "core:sync"
import "core:strings"

// =====================================================================
ID :: "com.alkamist.CsCorrector"
NAME :: "Cs Corrector"
VENDOR :: "Alkamist Audio"
URL :: ""
MANUAL_URL :: ""
SUPPORT_URL :: ""
VERSION :: "0.1.0"
DESCRIPTION :: "A MIDI timing corrector for Cinematic Studios libraries."
// =====================================================================

Audio_Plugin :: struct {
    using base: Audio_Plugin_Base,
    is_playing: bool,
    was_playing: bool,
    notes: [KEY_COUNT][dynamic]Note,
    held_key: Maybe(int),
    hold_pedal_is_physically_held: bool,
    hold_pedal_is_virtually_held: bool,
    debug_string_mutex: sync.Mutex,
    debug_string_builder: strings.Builder,
    debug_string_changed: bool,
}

on_create :: proc(plugin: ^Audio_Plugin) {
    reaper_plugin_info := cast(^Reaper_Plugin_Info)plugin.clap_host->get_extension("cockos.reaper_extension")
    reaper_load_functions(reaper_plugin_info)

    plugin.debug_string_builder = strings.builder_make_none()

    register_timer(plugin, "Debug_Timer", 0, proc(plugin: ^Audio_Plugin) {
        if plugin.debug_string_changed {
            sync.lock(&plugin.debug_string_mutex)
            debug_cstring := strings.clone_to_cstring(strings.to_string(plugin.debug_string_builder))
            defer delete(debug_cstring)
            show_console_msg(debug_cstring)
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

on_parameter_event :: proc(plugin: ^Audio_Plugin, event: Parameter_Event) {
}

on_transport_event :: proc(plugin: ^Audio_Plugin, event: Transport_Event) {
    // msg := fmt.aprint(event)
    // defer delete(msg)
    // debug(plugin, fmt.aprint(event))
}

on_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {
    // msg := fmt.aprint(event)
    // defer delete(msg)
    // debug(plugin, fmt.aprint(event))
}

on_process :: proc(plugin: ^Audio_Plugin, frame_count: int) {
}

debug :: proc(plugin: ^Audio_Plugin, msg: string) {
    msg_with_newline := strings.concatenate({msg, "\n"})
    defer delete(msg_with_newline)
    sync.lock(&plugin.debug_string_mutex)
    strings.write_string(&plugin.debug_string_builder, msg_with_newline)
    plugin.debug_string_changed = true
    sync.unlock(&plugin.debug_string_mutex)
}