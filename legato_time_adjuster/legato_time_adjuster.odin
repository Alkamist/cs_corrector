package legato_time_adjuster

import "core:slice"

KEY_COUNT :: 128
LEGATO_DELAY_COUNT :: 4

Note_Event_Kind :: enum {
    Off,
    On,
}

Note :: struct {
    on: ^Note_Event,
    off: Maybe(^Note_Event),
}

Note_Event :: struct {
    kind: Note_Event_Kind,
    index: int,
    time: int,
    key: int,
    velocity: f64,
    is_sent: bool,
}

Legato_Time_Adjuster :: struct {
    time: int,
    notes: [KEY_COUNT][dynamic]Note,
    held_key: Maybe(int),
    hold_pedal_is_physically_held: bool,
    hold_pedal_is_virtually_held: bool,
    first_note_delay: int,
    legato_delays: [LEGATO_DELAY_COUNT]int,
    legato_velocities: [LEGATO_DELAY_COUNT]f64,
}

destroy :: proc(lta: ^Legato_Time_Adjuster) {
    for key in 0 ..< KEY_COUNT {
        _destroy_notes_on_key(lta, key)
        delete(lta.notes[key])
    }
    free(lta)
}

reset :: proc(lta: ^Legato_Time_Adjuster) {
    lta.time = 0
    for key in 0 ..< KEY_COUNT {
        _destroy_notes_on_key(lta, key)
        resize(&lta.notes[key], 0)
    }
}

required_latency :: proc(lta: ^Legato_Time_Adjuster) -> int {
    smallest_delay := lta.first_note_delay
    for i in 0 ..< LEGATO_DELAY_COUNT {
        if lta.legato_delays[i] < smallest_delay {
            smallest_delay = lta.legato_delays[i]
        }
    }
    return -min(0, smallest_delay) * 2
}

process_note_on :: proc(lta: ^Legato_Time_Adjuster, index, offset, key: int, velocity: f64) {
    delay := required_latency(lta)

    // Decide how to augment the note on timing based on some internal logic
    if _key_is_held(lta) || lta.hold_pedal_is_virtually_held {
        range_bottom := 0.0
        for i in 0 ..< LEGATO_DELAY_COUNT {
            range_top := lta.legato_velocities[i]
            if velocity > range_bottom && velocity <= range_top {
                delay += lta.legato_delays[i]
                break
            }
            range_bottom = range_top
        }
    } else {
        delay += lta.first_note_delay
    }

    lta.held_key = key

    note_event := new(Note_Event)
    note_event.kind = .On
    note_event.index = index
    note_event.time = lta.time + offset + delay
    note_event.key = key
    note_event.velocity = velocity

    append(&lta.notes[key], Note{on = note_event})

    // The virtual hold pedal waits to activate until after the first note on
    if lta.hold_pedal_is_physically_held {
        lta.hold_pedal_is_virtually_held = true
    }
}

process_note_off :: proc(lta: ^Legato_Time_Adjuster, index, offset, key: int, velocity: f64) {
    held_key, _key_is_held := lta.held_key.?

    if _key_is_held && held_key == key {
        lta.held_key = nil
    }

    // Add a note off to the first incomplete note
    for note in &lta.notes[key] {
        _, note_is_complete := note.off.?
        if !note_is_complete {
            note_event := new(Note_Event)
            note_event.kind = .Off
            note_event.time = lta.time + offset + required_latency(lta)
            note_event.key = key
            note_event.velocity = velocity
            note.off = note_event
            break
        }
    }
}

process_hold_pedal :: proc(lta: ^Legato_Time_Adjuster, is_held: bool) {
    lta.hold_pedal_is_physically_held = is_held
    if is_held {
        // Only hold down the virtual hold pedal if there is already a key held
        if _key_is_held(lta) {
            lta.hold_pedal_is_virtually_held = true
        }
    } else {
        // The virtual hold pedal is always released with the real one
        lta.hold_pedal_is_virtually_held = false
    }
}

send_note_events :: proc(
    lta: ^Legato_Time_Adjuster,
    frame_count: int,
    send_proc: proc(kind: Note_Event_Kind, index, offset, key: int, velocity: f64),
) {
    sorted_events := _get_sorted_note_events(lta)
    defer delete(sorted_events)

    for event in sorted_events {
        offset := event.time - lta.time
        if offset < frame_count {
            if !event.is_sent {
                event.is_sent = true
                send_proc(event.kind, event.index, offset, event.key, event.velocity)
            }
        } else {
            break
        }
    }

    _remove_dead_notes(lta)
    _fix_note_overlaps(lta)

    if len(lta.notes) > 0 {
        lta.time += frame_count
    } else {
        lta.time = 0
    }
}

_key_is_held :: proc(lta: ^Legato_Time_Adjuster) -> bool {
    _, _key_is_held := lta.held_key.?
    return _key_is_held
}

_note_is_dead :: proc(note: Note) -> bool {
    note_off, note_off_exists := note.off.?
    return note_off_exists && note_off.is_sent
}

_remove_dead_notes :: proc(lta: ^Legato_Time_Adjuster) {
    for key in 0 ..< KEY_COUNT {
        keep_notes: [dynamic]Note

        for note in &lta.notes[key] {
            if _note_is_dead(note) {
                _destroy_note(note)
            } else {
                append(&keep_notes, note)
            }
        }

        delete(lta.notes[key])
        lta.notes[key] = keep_notes
    }
}

_fix_note_overlaps :: proc(lta: ^Legato_Time_Adjuster) {
    for key in 0 ..< KEY_COUNT {
        sorted_notes := _get_sorted_notes(lta, key)
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

_get_sorted_notes :: proc(lta: ^Legato_Time_Adjuster, key: int) -> [dynamic]Note {
    result := make([dynamic]Note, len(lta.notes[key]))
    for note, i in lta.notes[key] {
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

_get_sorted_note_events :: proc(lta: ^Legato_Time_Adjuster) -> [dynamic]^Note_Event {
    result: [dynamic]^Note_Event
    for key in 0 ..< KEY_COUNT {
        for note in lta.notes[key] {
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
    return result
}

_destroy_notes_on_key :: proc(lta: ^Legato_Time_Adjuster, key: int) {
    for note in lta.notes[key] {
        _destroy_note(note)
    }
}

_destroy_note :: proc(note: Note) {
    free(note.on)
    if note_off, ok := note.off.?; ok {
        free(note_off)
    }
}