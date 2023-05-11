package main

import "core:fmt"
import "core:sync"
import "core:strings"
import lta "legato_time_adjuster"

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
    note_index: [lta.KEY_COUNT]int,
    lta: lta.Legato_Time_Adjuster,
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

    plugin.lta.legato_velocities[0] = 20
    plugin.lta.legato_velocities[1] = 64
    plugin.lta.legato_velocities[2] = 100
    plugin.lta.legato_velocities[3] = 128
}

on_destroy :: proc(plugin: ^Audio_Plugin) {
    unregister_timer(plugin, "Debug_Timer")
    strings.builder_destroy(&plugin.debug_string_builder)
    lta.destroy(&plugin.lta)
}

on_reset :: proc(plugin: ^Audio_Plugin) {
    lta.reset(&plugin.lta)
    for i in 0 ..< lta.KEY_COUNT do plugin.note_index[i] = 0
}

on_parameter_event :: proc(plugin: ^Audio_Plugin, event: Parameter_Event) {
    switch event.id {
    case .Legato_First_Note_Delay ..= .Legato_Fast_Delay:
        _update_legato_time_adjuster(plugin)
    }
}

on_transport_event :: proc(plugin: ^Audio_Plugin, event: Transport_Event) {
    if .Is_Playing in event.flags {
        plugin.was_playing = plugin.is_playing
        plugin.is_playing = true
    } else {
        plugin.was_playing = plugin.is_playing
        plugin.is_playing = false
        // Reset the CsCorrector notes on playback stop
        if plugin.was_playing && !plugin.is_playing {
            lta.reset(&plugin.lta)
            for i in 0 ..< lta.KEY_COUNT do plugin.note_index[i] = 0
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
        // channel := int(msg[0] & 0x0F)
        key := int(msg[1])
        velocity := f64(msg[2])
        lta.process_note_off(&plugin.lta, plugin.note_index[key], event.time, key, velocity)
        plugin.note_index[key] += 1
        return
    }

    is_note_on := status_code == 0x90
    if is_note_on {
        // channel := int(msg[0] & 0x0F)
        key := int(msg[1])
        velocity := f64(msg[2])
        lta.process_note_on(&plugin.lta, plugin.note_index[key], event.time, key, velocity)
        return
    }

    is_cc := status_code == 0xB0
    is_hold_pedal := is_cc && msg[1] == 64
    if is_hold_pedal {
        is_held := msg[2] > 63
        lta.process_hold_pedal(&plugin.lta, is_held)
        // Don't return because we need to send the hold pedal information
    }

    // Pass any events that aren't note on or off straight to the host
    event := event
    event.time += plugin.latency
    send_midi_event(plugin, event)
}

on_process :: proc(plugin: ^Audio_Plugin, frame_count: int) {
    context.user_ptr = plugin
    lta.send_note_events(&plugin.lta, frame_count, _send_note_event_proc)
    // for key in 0 ..< lta.KEY_COUNT {
    //     if len(plugin.lta.notes[key]) > 0 {
    //         debug(plugin, fmt.tprint(plugin.lta.notes[key]))
    //     }
    // }
}

save_preset :: proc(plugin: ^Audio_Plugin, builder: ^strings.Builder) -> bool {
    preset := Cs_Corrector_Preset_V1{
        size = size_of(Cs_Corrector_Preset_V1),
        preset_version = 1,
        parameter_offset = i64le(offset_of(Cs_Corrector_Preset_V1, parameters)),
        parameter_count = len(Parameter),
    }
    for id in Parameter {
        preset.parameters[id] = f64le(main_thread_parameter(plugin, id))
    }
    preset_data := transmute([size_of(preset)]byte)preset
    strings.write_bytes(builder, preset_data[:])
    return true
}

load_preset :: proc(plugin: ^Audio_Plugin, data: []byte) {
    preset := (cast(^Cs_Corrector_Preset_V1)&data[0])^
    for id in Parameter {
        set_main_thread_parameter(plugin, id, f64(preset.parameters[id]))
    }
    _update_legato_time_adjuster(plugin)
}

debug :: proc(plugin: ^Audio_Plugin, msg: string) {
    msg_with_newline := strings.concatenate({msg, "\n"})
    defer delete(msg_with_newline)
    sync.lock(&plugin.debug_string_mutex)
    strings.write_string(&plugin.debug_string_builder, msg_with_newline)
    plugin.debug_string_changed = true
    sync.unlock(&plugin.debug_string_mutex)
}

_send_note_event_proc :: proc(kind: lta.Note_Event_Kind, index, offset, key: int, velocity: f64) {
    plugin := cast(^Audio_Plugin)context.user_ptr
    channel := 0
    status := channel
    switch kind {
    case .Off: status += 0x80
    case .On: status += 0x90
    }
    send_midi_event(plugin, Midi_Event{
        time = offset,
        port = 0,
        data = {u8(status), u8(key), u8(min(127, velocity))},
    })
}

_update_legato_time_adjuster :: proc(plugin: ^Audio_Plugin) {
    plugin.lta.first_note_delay = milliseconds_to_samples(plugin, audio_thread_parameter(plugin, .Legato_First_Note_Delay))
    plugin.lta.legato_delays[0] = milliseconds_to_samples(plugin, audio_thread_parameter(plugin, .Legato_Portamento_Delay))
    plugin.lta.legato_delays[1] = milliseconds_to_samples(plugin, audio_thread_parameter(plugin, .Legato_Slow_Delay))
    plugin.lta.legato_delays[2] = milliseconds_to_samples(plugin, audio_thread_parameter(plugin, .Legato_Medium_Delay))
    plugin.lta.legato_delays[3] = milliseconds_to_samples(plugin, audio_thread_parameter(plugin, .Legato_Fast_Delay))
    set_latency(plugin, lta.required_latency(&plugin.lta))
}