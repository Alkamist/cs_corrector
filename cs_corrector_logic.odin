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
    time: int,
    key: int,
    velocity: int,
    is_sent: bool,
}

process_hold_pedal :: proc(plugin: ^Audio_Plugin, is_held: bool) {
    plugin.hold_pedal_is_physically_held = is_held
    if is_held {
        // Only hold down the virtual hold pedal if there is already a key held
        if key_is_held(plugin) {
            plugin.hold_pedal_is_virtually_held = true
        }
    } else {
        // The virtual hold pedal is always released with the real one
        plugin.hold_pedal_is_virtually_held = false
    }
}

process_note_on :: proc(plugin: ^Audio_Plugin, time, key, velocity: int) {
    delay := 0

    if key_is_held(plugin) || plugin.hold_pedal_is_virtually_held {
        if velocity <= 20 {
            delay = legato_portamento_delay(plugin)
        } else if velocity > 20 && velocity <= 64 {
            delay = legato_slow_delay(plugin)
        } else if velocity > 64 && velocity <= 100 {
            delay = legato_medium_delay(plugin)
        } else {
            delay = legato_fast_delay(plugin)
        }
    } else {
        delay = legato_first_note_delay(plugin)
    }

    plugin.held_key = key

    note_event := new(Note_Event)
    note_event.kind = .On
    note_event.time = time + required_latency(plugin) + delay
    note_event.key = key
    note_event.velocity = velocity

    append(&plugin.notes[key], Note{on = note_event})
}

process_note_off :: proc(plugin: ^Audio_Plugin, time, key, velocity: int) {
    held_key, key_is_held := plugin.held_key.?

    if key_is_held && held_key == key {
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

key_is_held :: proc(plugin: ^Audio_Plugin) -> bool {
    _, key_is_held := plugin.held_key.?
    return key_is_held
}

milliseconds_to_samples :: proc(plugin: ^Audio_Plugin, milliseconds: f64) -> int {
    return int(plugin.sample_rate * milliseconds * 0.001)
}

legato_first_note_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_First_Note_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

legato_portamento_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Portamento_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

legato_slow_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Slow_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

legato_medium_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Medium_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
}

legato_fast_delay :: proc(plugin: ^Audio_Plugin) -> int {
    value_milliseconds := audio_thread_parameter(plugin, .Legato_Fast_Delay)
    return milliseconds_to_samples(plugin, value_milliseconds)
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

extract_note_events :: proc(plugin: ^Audio_Plugin, frame_count: int) -> [dynamic]Note_Event {
    result: [dynamic]Note_Event

    sorted_events := get_sorted_note_events(plugin)
    defer delete(sorted_events)

    for event in sorted_events {
        if event.time < frame_count {
            if !event.is_sent {
                event.is_sent = true
                append(&result, event^)
            }
        } else {
            break
        }
    }

    remove_sent_notes(plugin)
    fix_note_overlaps(plugin)
    decrease_event_times(plugin, frame_count)

    return result
}

decrease_event_times :: proc(plugin: ^Audio_Plugin, frame_count: int) {
    for key in 0 ..< KEY_COUNT {
        for note in plugin.notes[key] {
            note.on.time -= frame_count
            if note_off, ok := note.off.?; ok {
                note_off.time -= frame_count
            }
        }
    }
}

fix_note_overlaps :: proc(plugin: ^Audio_Plugin) {
    for key in 0 ..< KEY_COUNT {
        sorted_notes := get_sorted_notes(plugin, key)
        defer delete(sorted_notes)

        for i in 1 ..< len(sorted_notes) {
            prev_note := sorted_notes[i - 1]
            note := sorted_notes[i]

            if prev_note_off, ok := prev_note.off.?; ok {
                if prev_note_off.time > note.on.time {
                    prev_note_off.time = note.on.time
                    if prev_note_off.time < prev_note.on.time {
                        prev_note_off.time = prev_note.on.time
                    }
                }
            }
        }
    }
}

remove_sent_notes :: proc(plugin: ^Audio_Plugin) {
    for key in 0 ..< KEY_COUNT {
        keep_notes: [dynamic]Note

        for note in &plugin.notes[key] {
            if note_is_sent(note) {
                free_note(note)
            } else {
                append(&keep_notes, note)
            }
        }

        delete(plugin.notes[key])
        plugin.notes[key] = keep_notes
    }
}

get_sorted_notes :: proc(plugin: ^Audio_Plugin, key: int) -> [dynamic]Note {
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

get_sorted_note_events :: proc(plugin: ^Audio_Plugin) -> (result: [dynamic]^Note_Event) {
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

note_is_sent :: proc(note: Note) -> bool {
    note_off, note_off_exists := note.off.?
    return note_off_exists && note_off.is_sent
}

free_note :: proc(note: Note) {
    free(note.on)
    if note_off, ok := note.off.?; ok {
        free(note_off)
    }
}

free_notes :: proc(plugin: ^Audio_Plugin, key: int) {
    for note in plugin.notes[key] {
        free_note(note)
    }
}