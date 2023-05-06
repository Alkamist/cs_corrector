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
    notes: [KEY_COUNT][dynamic]^Note,
    held_key: Maybe(int),
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
        delete(state.notes[key])
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

process_note_on :: proc(state: ^State, time, key, velocity: int) {
    delay := 0
    _, key_is_held := state.held_key.?

    if key_is_held {
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

    note := new(Note)
    note.on = note_event

    append(&state.notes[key], note)
}

process_note_off :: proc(state: ^State, time, key, velocity: int) {
    held_key, key_is_held := state.held_key.?

    if key_is_held && held_key == key {
        state.held_key = nil
    }

    // Add a note off to the first incomplete note
    for i in 0 ..< len(state.notes[key]) {
        _, note_is_complete := state.notes[key][i].off.?
        if !note_is_complete {
            note_event := new(Note_Event)
            note_event.kind = .Off
            note_event.time = time + required_latency(state)
            note_event.key = key
            note_event.velocity = velocity
            state.notes[key][i].off = note_event
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
    // _fix_note_overlaps(state)
    // _decrease_event_times(state, frame_count)
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

// proc fixNoteOverlaps(state: ^State) =
//   for key in 0 ..< keyCount:
//     var sortedNotes = state.notes[key]

//     sortedNotes.sort do (x, y: Note) -> int:
//       cmp(x.on.time, y.on.time)

//     for i in 1 ..< sortedNotes.len:
//       var prevNote = sortedNotes[i - 1]
//       var note = sortedNotes[i]
//       if prevNote.off.isSome and prevNote.off.get.time > note.on.time:
//         prevNote.off.get.time = note.on.time
//         if prevNote.off.get.time < prevNote.on.time:
//           prevNote.off.get.time = prevNote.on.time

_remove_sent_notes :: proc(state: ^State) {
    for key in 0 ..< KEY_COUNT {
        keep_notes: [dynamic]^Note
        defer delete(keep_notes)

        for note in state.notes[key] {
            if _note_is_sent(note) {
                _free_note(note)
            } else {
                append(&keep_notes, note)
            }
        }

        state.notes[key] = keep_notes
    }
}

_get_sorted_note_events :: proc(state: ^State) -> (events: [dynamic]^Note_Event) {
    for key in 0 ..< KEY_COUNT {
        for note in state.notes[key] {
            append(&events, note.on)
            note_off, note_off_exists := note.off.?
            if note_off_exists {
                append(&events, note_off)
            }
        }
    }
    slice.sort_by(events[:], proc(i, j: ^Note_Event) -> bool {
        if i.time < j.time {
            return true
        } else {
            return false
        }
    })
    return
}

_note_is_sent :: proc(note: ^Note) -> bool {
    note_off, note_off_exists := note.off.?
    return note_off_exists && note_off.is_sent
}

_free_note :: proc(note: ^Note) {
    free(note.on)
    if note_off, note_off_exists := note.off.?; note_off_exists {
        free(note_off)
    }
    free(note)
}

_free_notes :: proc(state: ^State, key: int) {
    for note in state.notes[key] {
        _free_note(note)
    }
}