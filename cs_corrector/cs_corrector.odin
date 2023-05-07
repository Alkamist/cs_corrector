package cs_corrector

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

State :: struct {
    notes: [KEY_COUNT][dynamic]Note,
    held_key: Maybe(int),
    hold_pedal_is_held: bool,
    legato_first_note_delay: int,
    legato_portamento_delay: int,
    legato_slow_delay: int,
    legato_medium_delay: int,
    legato_fast_delay: int,
}

destroy :: proc(state: ^State) {
    for key in 0 ..< KEY_COUNT {
        _free_notes(state, key)
        delete(state.notes[key])
    }
}

reset :: proc(state: ^State) {
    state.held_key = nil
    for key in 0 ..< KEY_COUNT {
        _free_notes(state, key)
        resize(&state.notes[key], 0)
    }
}

required_latency :: proc(state: ^State) -> int {
    return -min(
        0,
        state.legato_first_note_delay,
        state.legato_portamento_delay,
        state.legato_slow_delay,
        state.legato_medium_delay,
        state.legato_fast_delay,
    ) * 2
}

process_hold_pedal :: proc(state: ^State, is_held: bool) {
    state.hold_pedal_is_held = is_held
}

process_note_on :: proc(state: ^State, time, key, velocity: int) {
    delay := 0
    _, key_is_held := state.held_key.?

    if state.hold_pedal_is_held || key_is_held {
        if velocity <= 20 {
            delay = state.legato_portamento_delay
        } else if velocity > 20 && velocity <= 64 {
            delay = state.legato_slow_delay
        } else if velocity > 64 && velocity <= 100 {
            delay = state.legato_medium_delay
        } else {
            delay = state.legato_fast_delay
        }
    } else {
        delay = state.legato_first_note_delay
    }

    state.held_key = key

    note_event := new(Note_Event)
    note_event.kind = .On
    note_event.time = time + required_latency(state) + delay
    note_event.key = key
    note_event.velocity = velocity

    append(&state.notes[key], Note{on = note_event})
}

process_note_off :: proc(state: ^State, time, key, velocity: int) {
    held_key, key_is_held := state.held_key.?

    if key_is_held && held_key == key {
        state.held_key = nil
    }

    // Add a note off to the first incomplete note
    for note in &state.notes[key] {
        _, note_is_complete := note.off.?
        if !note_is_complete {
            note_event := new(Note_Event)
            note_event.kind = .Off
            note_event.time = time + required_latency(state)
            note_event.key = key
            note_event.velocity = velocity
            note.off = note_event
            break
        }
    }
}

extract_note_events :: proc(state: ^State, frame_count: int) -> (result: [dynamic]Note_Event) {
    sorted_events := _get_sorted_note_events(state)
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

    _remove_sent_notes(state)
    _fix_note_overlaps(state)
    _decrease_event_times(state, frame_count)

    return
}

_decrease_event_times :: proc(state: ^State, frame_count: int) {
    for key in 0 ..< KEY_COUNT {
        for note in state.notes[key] {
            note.on.time -= frame_count
            if note_off, ok := note.off.?; ok {
                note_off.time -= frame_count
            }
        }
    }
}

_fix_note_overlaps :: proc(state: ^State) {
    for key in 0 ..< KEY_COUNT {
        sorted_notes := _get_sorted_notes(state, key)
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

_remove_sent_notes :: proc(state: ^State) {
    for key in 0 ..< KEY_COUNT {
        keep_notes: [dynamic]Note

        for note in &state.notes[key] {
            if _note_is_sent(note) {
                _free_note(note)
            } else {
                append(&keep_notes, note)
            }
        }

        delete(state.notes[key])
        state.notes[key] = keep_notes
    }
}

_get_sorted_notes :: proc(state: ^State, key: int) -> (result: [dynamic]Note) {
    result = make([dynamic]Note, len(state.notes[key]))
    for note, i in state.notes[key] {
        result[i] = note
    }
    slice.sort_by(result[:], proc(i, j: Note) -> bool {
        if i.on.time < j.on.time {
            return true
        } else {
            return false
        }
    })
    return
}

_get_sorted_note_events :: proc(state: ^State) -> (result: [dynamic]^Note_Event) {
    for key in 0 ..< KEY_COUNT {
        for note in state.notes[key] {
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

_free_note :: proc(note: Note) {
    free(note.on)
    if note_off, ok := note.off.?; ok {
        free(note_off)
    }
}

_free_notes :: proc(state: ^State, key: int) {
    for note in state.notes[key] {
        _free_note(note)
    }
}