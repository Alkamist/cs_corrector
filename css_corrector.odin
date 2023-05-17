package main

import "core:fmt"
import "core:sync"
import "core:strings"
import "reaper"
import nq "note_queue"

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
    note_queue: nq.Note_Queue,
    is_playing: bool,
    was_playing: bool,
    debug_string_mutex: sync.Mutex,
    debug_string_builder: strings.Builder,
    debug_string_changed: bool,

    held_key: Maybe(int),
    hold_pedal_is_virtually_held: bool,
    hold_pedal_is_physically_held: bool,
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

    plugin.note_queue = nq.create(0, 1024)
}

on_destroy :: proc(plugin: ^Audio_Plugin) {
    unregister_timer(plugin, "Debug_Timer")
    strings.builder_destroy(&plugin.debug_string_builder)
    nq.destroy(&plugin.note_queue)
}

on_activate :: proc(plugin: ^Audio_Plugin) {
    set_latency(plugin, required_latency(plugin))
}

on_deactivate :: proc(plugin: ^Audio_Plugin) {
}

on_reset :: proc(plugin: ^Audio_Plugin) {
    nq.reset(&plugin.note_queue)
}

on_parameter_event :: proc(plugin: ^Audio_Plugin, event: Parameter_Event) {
    set_latency(plugin, required_latency(plugin))
}

on_transport_event :: proc(plugin: ^Audio_Plugin, event: Transport_Event) {
    if .Is_Playing in event.flags {
        plugin.was_playing = plugin.is_playing
        plugin.is_playing = true
    } else {
        plugin.was_playing = plugin.is_playing
        plugin.is_playing = false
        // Reset the note queue on playback stop.
        if plugin.was_playing && !plugin.is_playing {
            nq.reset(&plugin.note_queue)
        }
    }
}

on_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {
    // Don't process when project is not playing back so there isn't
    // an annoying delay when drawing notes on the piano roll
    if !plugin.is_playing {
        send_midi_event(plugin, event)
        return
    }

    msg := event.data
    status_code := msg[0] & 0xF0

    is_note_off := status_code == 0x80
    if is_note_off {
        process_note_off(plugin, event.time, int(msg[1]), f64(msg[2]))
        return
    }

    is_note_on := status_code == 0x90
    if is_note_on {
        process_note_on(plugin, event.time, int(msg[1]), f64(msg[2]))
        return
    }

    is_cc := status_code == 0xB0
    is_hold_pedal := is_cc && msg[1] == 64
    if is_hold_pedal {
        is_held := msg[2] > 63
        process_hold_pedal(plugin, is_held)
        // Don't return because we need to send the hold pedal information
    }

    // Pass any events that aren't note on or off straight to the host
    event := event
    event.time += plugin.latency
    send_midi_event(plugin, event)
}

on_process :: proc(plugin: ^Audio_Plugin, frame_count: int) {
    nq.send_events(&plugin.note_queue, frame_count, plugin,
        proc(plugin: rawptr, kind: nq.Note_Event_Kind, time, channel, key: int, velocity: f64)
    {
        plugin := cast(^Audio_Plugin)plugin
        send_midi_event(plugin, encode_note_as_midi_event(kind, time, channel, key, velocity))
    })
    // debug(plugin, fmt.tprint(plugin.note_queue.key_notes))
    // free_all(context.temp_allocator)
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

encode_note_as_midi_event :: proc(kind: nq.Note_Event_Kind, time, channel, key: int, velocity: f64) -> Midi_Event {
    status := channel
    switch kind {
    case .Off: status += 0x80
    case .On: status += 0x90
    }
    return Midi_Event{
        time = time,
        port = 0,
        data = {u8(status), u8(key), u8(velocity)},
    }
}





required_latency :: proc(plugin: ^Audio_Plugin) -> int {
    return -min(
        0,
        legato_first_note_delay(plugin),
        legato_portamento_delay(plugin),
        legato_slow_delay(plugin),
        legato_medium_delay(plugin),
        legato_fast_delay(plugin),
    ) * 2
}

process_note_on :: proc(plugin: ^Audio_Plugin, time, key: int, velocity: f64) {
    delay := required_latency(plugin)

    _, key_is_held := plugin.held_key.?

    if key_is_held || plugin.hold_pedal_is_virtually_held {
        if velocity <= 20 {
            delay += legato_portamento_delay(plugin)
        } else if velocity > 20 && velocity <= 64 {
            delay += legato_slow_delay(plugin)
        } else if velocity > 64 && velocity <= 100 {
            delay += legato_medium_delay(plugin)
        } else {
            delay += legato_fast_delay(plugin)
        }
    } else {
        delay += legato_first_note_delay(plugin)
    }

    plugin.held_key = key

    nq.add_event(
        &plugin.note_queue,
        .On,
        time + delay,
        0, key, velocity,
    )

    // The virtual hold pedal waits to activate until after the first note on
    if plugin.hold_pedal_is_physically_held {
        plugin.hold_pedal_is_virtually_held = true
    }
}

process_note_off :: proc(plugin: ^Audio_Plugin, time, key: int, velocity: f64) {
    held_key, _key_is_held := plugin.held_key.?

    if _key_is_held && held_key == key {
        plugin.held_key = nil
    }

    delay := required_latency(plugin)

    nq.add_event(
        &plugin.note_queue,
        .Off,
        time + delay,
        0, key, velocity,
    )
}

process_hold_pedal :: proc(plugin: ^Audio_Plugin, is_held: bool) {
    plugin.hold_pedal_is_physically_held = is_held
    if is_held {
        // Only hold down the virtual hold pedal if there is already a key held
        _, key_is_held := plugin.held_key.?
        if key_is_held {
            plugin.hold_pedal_is_virtually_held = true
        }
    } else {
        // The virtual hold pedal is always released with the real one
        plugin.hold_pedal_is_virtually_held = false
    }
}

legato_first_note_delay :: proc(plugin: ^Audio_Plugin) -> int {
    return milliseconds_to_samples(plugin, parameter(plugin, .Legato_First_Note_Delay))
}

legato_portamento_delay :: proc(plugin: ^Audio_Plugin) -> int {
    return milliseconds_to_samples(plugin, parameter(plugin, .Legato_Portamento_Delay))
}

legato_slow_delay :: proc(plugin: ^Audio_Plugin) -> int {
    return milliseconds_to_samples(plugin, parameter(plugin, .Legato_Slow_Delay))
}

legato_medium_delay :: proc(plugin: ^Audio_Plugin) -> int {
    return milliseconds_to_samples(plugin, parameter(plugin, .Legato_Medium_Delay))
}

legato_fast_delay :: proc(plugin: ^Audio_Plugin) -> int {
    return milliseconds_to_samples(plugin, parameter(plugin, .Legato_Fast_Delay))
}