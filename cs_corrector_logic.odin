package main

import "core:slice"

KEY_COUNT :: 128

Note_Event_Kind :: enum {
    On,
    Off,
}

Note :: struct {
    on: ^Note_Event,
    off: Maybe(^Note_Event),
}

Note_Event :: struct {
    kind: Note_Event_Kind,
    channel: int,
    time: int,
    key: int,
    velocity: int,
    is_sent: bool,
}

required_latency :: proc(plugin: ^Audio_Plugin) -> int {
    return -min(
        0,
        _legato_first_note_delay(plugin),
        _legato_portamento_delay(plugin),
        _legato_slow_delay(plugin),
        _legato_medium_delay(plugin),
        _legato_fast_delay(plugin),
    ) * 2
}

free_notes :: proc(plugin: ^Audio_Plugin) {
    for key in 0 ..< KEY_COUNT {
        for note in plugin.notes[key] {
            _free_note(note)
        }
        delete(plugin.notes[key])
    }
}

reset_notes :: proc(plugin: ^Audio_Plugin) {
    plugin.held_key = nil
    for key in 0 ..< KEY_COUNT {
        for note in plugin.notes[key] {
            _free_note(note)
        }
        resize(&plugin.notes[key], 0)
    }
}

process_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {
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
        _process_note_off(plugin, event.time, int(msg[1]), int(msg[2]))
        return
    }

    is_note_on := status_code == 0x90
    if is_note_on {
        _process_note_on(plugin, event.time, int(msg[1]), int(msg[2]))
        return
    }

    is_cc := status_code == 0xB0
    is_hold_pedal := is_cc && msg[1] == 64
    if is_hold_pedal {
        is_held := msg[2] > 63
        _process_hold_pedal(plugin, is_held)
        // Don't return because we need to send the hold pedal information
    }

    // Pass any events that aren't note on or off straight to the host
    event := event
    event.time += plugin.latency
    send_midi_event(plugin, event)
}

send_note_events :: proc(plugin: ^Audio_Plugin, frame_count: int) {
    sorted_events := _get_sorted_note_events(plugin)
    defer delete(sorted_events)

    for event in sorted_events {
        if event.time < frame_count {
            if !event.is_sent {
                event.is_sent = true
                send_midi_event(plugin, _note_event_to_midi_event(event^))
            }
        } else {
            break
        }
    }

    _remove_sent_notes(plugin)
    _fix_note_overlaps(plugin)
    _decrease_event_times(plugin, frame_count)
}

// =========================================================================

_process_hold_pedal :: proc(plugin: ^Audio_Plugin, is_held: bool) {
    plugin.hold_pedal_is_physically_held = is_held
    if is_held {
        // Only hold down the virtual hold pedal if there is already a key held
        if _key_is_held(plugin) {
            plugin.hold_pedal_is_virtually_held = true
        }
    } else {
        // The virtual hold pedal is always released with the real one
        plugin.hold_pedal_is_virtually_held = false
    }
}

_process_note_on :: proc(plugin: ^Audio_Plugin, time, key, velocity: int) {
    delay := 0

    if _key_is_held(plugin) || plugin.hold_pedal_is_virtually_held {
        if velocity <= 20 {
            delay = _legato_portamento_delay(plugin)
        } else if velocity > 20 && velocity <= 64 {
            delay = _legato_slow_delay(plugin)
        } else if velocity > 64 && velocity <= 100 {
            delay = _legato_medium_delay(plugin)
        } else {
            delay = _legato_fast_delay(plugin)
        }
    } else {
        delay = _legato_first_note_delay(plugin)
    }

    plugin.held_key = key

    note_event := new(Note_Event)
    note_event.kind = .On
    note_event.time = time + required_latency(plugin) + delay
    note_event.key = key
    note_event.velocity = velocity

    append(&plugin.notes[key], Note{on = note_event})

    // The virtual hold pedal waits to activate until after the first note on
    if plugin.hold_pedal_is_physically_held {
        plugin.hold_pedal_is_virtually_held = true
    }
}

_process_note_off :: proc(plugin: ^Audio_Plugin, time, key, velocity: int) {
    held_key, _key_is_held := plugin.held_key.?

    if _key_is_held && held_key == key {
        plugin.held_key = nil
    }

    // Add a note off to the first incomplete note
    for note in &plugin.notes[key] {
        _, note_is_complete := note.off.?
        if !note_is_complete {
            note_event := new(Note_Event)
            note_event.kind = .Off
            note_event.time = time + required_latency(plugin)
            note_event.key = key
            note_event.velocity = velocity
            note.off = note_event
            break
        }
    }
}

_key_is_held :: proc(plugin: ^Audio_Plugin) -> bool {
    _, _key_is_held := plugin.held_key.?
    return _key_is_held
}

_decrease_event_times :: proc(plugin: ^Audio_Plugin, frame_count: int) {
    for key in 0 ..< KEY_COUNT {
        for note in plugin.notes[key] {
            note.on.time -= frame_count
            if note_off, ok := note.off.?; ok {
                note_off.time -= frame_count
            }
        }
    }
}

_fix_note_overlaps :: proc(plugin: ^Audio_Plugin) {
    for key in 0 ..< KEY_COUNT {
        sorted_notes := _get_sorted_notes(plugin, key)
        defer delete(sorted_notes)
        for i in 1 ..< len(sorted_notes) {
            prev_note := sorted_notes[i - 1]
            note := sorted_notes[i]
            if prev_note_off, ok := prev_note.off.?; ok {
                if prev_note_off.time > note.on.time {
                    prev_note_off.time = note.on.time
                }
            }
        }
    }
}

_remove_sent_notes :: proc(plugin: ^Audio_Plugin) {
    for key in 0 ..< KEY_COUNT {
        keep_notes: [dynamic]Note

        for note in &plugin.notes[key] {
            if _note_is_sent(note) {
                _free_note(note)
            } else {
                append(&keep_notes, note)
            }
        }

        delete(plugin.notes[key])
        plugin.notes[key] = keep_notes
    }
}

_get_sorted_notes :: proc(plugin: ^Audio_Plugin, key: int) -> [dynamic]Note {
    result := make([dynamic]Note, len(plugin.notes[key]))
    for note, i in plugin.notes[key] {
        result[i] = note
    }
    slice.sort_by(result[:], proc(i, j: Note) -> bool {
        if i.on.time < j.on.time {
            return true
        } else {
            return false
        }
    })
    return result
}

_get_sorted_note_events :: proc(plugin: ^Audio_Plugin) -> (result: [dynamic]^Note_Event) {
    for key in 0 ..< KEY_COUNT {
        for note in plugin.notes[key] {
            append(&result, note.on)
            note_off, note_off_exists := note.off.?
            if note_off_exists {
                append(&result, note_off)
            }
        }
    }
    slice.sort_by(result[:], proc(i, j: ^Note_Event) -> bool {
        if i.time < j.time {
            return true
        } else {
            return false
        }
    })
    return
}

_note_is_sent :: proc(note: Note) -> bool {
    note_off, note_off_exists := note.off.?
    return note_off_exists && note_off.is_sent
}

_note_event_to_midi_event :: proc(event: Note_Event) -> Midi_Event {
    status := event.channel
    switch event.kind {
    case .Off: status += 0x80
    case .On: status += 0x90
    }
    return Midi_Event{
        time = event.time,
        port = 0,
        data = {u8(status), u8(event.key), u8(event.velocity)},
    }
}

_legato_first_note_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_First_Note_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

_legato_portamento_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Portamento_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

_legato_slow_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Slow_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

_legato_medium_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Medium_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

_legato_fast_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Fast_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

_free_note :: proc(note: Note) {
    free(note.on)
    if note_off, ok := note.off.?; ok {
        free(note_off)
    }
}