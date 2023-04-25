package cs_corrector

import "core:slice"
import "core:fmt"

print: proc(text: string)

Cs_Corrector :: struct {
    midi_events: [dynamic]^Midi_Event,
    notes: [128][dynamic]^Note,
    current_note: [128]^Note,
    held_key: Maybe(u8),
    legato_first_delay: int, // Freshly pressed key
    legato_level0_delay: int, // Lowest velocity legato
    legato_level1_delay: int,
    legato_level2_delay: int,
    legato_level3_delay: int, // Highest velocity legato
}

destroy :: proc(cs: ^Cs_Corrector) {
    for notes in cs.notes {
        for note in notes {
            free(note)
        }
        delete(notes)
    }
    for event in cs.midi_events {
        free(event)
    }
    delete(cs.midi_events)
}

required_latency :: proc(cs: ^Cs_Corrector) -> int {
    return -min(
        0,
        cs.legato_first_delay,
        cs.legato_level0_delay,
        cs.legato_level1_delay,
        cs.legato_level2_delay,
        cs.legato_level3_delay,
    )
}

process_event :: proc(cs: ^Cs_Corrector, event: Midi_Event) {
    event := new_clone(event)
    delay := 0

    #partial switch midi_message_kind(event.data) {
    case .Note_Off:
        event_key := midi_key(event.data)

        held_key, key_is_held := cs.held_key.?
        if key_is_held && event_key == held_key {
            cs.held_key = nil
        }

        // Finish the last note on this key
        if cs.current_note[event_key] != nil {
            cs.current_note[event_key].off = event
            cs.current_note[event_key] = nil
        }

        print(fmt.aprintf("%v", cs.midi_events))

    case .Note_On:
        event_key := midi_key(event.data)

        _, key_is_held := cs.held_key.?
        if key_is_held {
            delay = cs.legato_level0_delay
        } else {
            delay = cs.legato_first_delay
        }
        cs.held_key = event_key

        // Start a new note
        note := new(Note)
        note.on = event
        append(&cs.notes[event_key], note)
        cs.current_note[event_key] = note

        print(fmt.aprintf("%v", cs.midi_events))
    }

    event.time += required_latency(cs) + delay
    if event.time < 0 {
        event.time = 0
    }

    append(&cs.midi_events, event)
}

push_events :: proc(cs: ^Cs_Corrector, frame_count: int, push_proc: proc(event: Midi_Event)) {
    // _fix_note_overlaps(cs)
    _sort_events_by_time(cs)

    keep_events: [dynamic]^Midi_Event

    // Loop through events and push any that are inside the frame count
    for event in cs.midi_events {
        if event.time < frame_count {
            push_proc(event^)
            free(event)
        } else {
            append(&keep_events, event)
        }
    }

    delete(cs.midi_events)
    cs.midi_events = keep_events

    _clear_unused_notes(cs)
    _decrease_event_times(cs, frame_count)
}

_decrease_event_times :: proc(cs: ^Cs_Corrector, time: int) {
    for event in cs.midi_events {
        event.time -= time
    }
}

// _fix_note_overlaps :: proc(cs: ^Cs_Corrector) {
//     for notes in cs.notes {
//         for i in 1 ..< len(notes) {
//             prev_note := notes[i - 1]
//             if _note_is_unused(cs, prev_note) {
//                 continue
//             }
//             note := notes[i]
//             if prev_note.off == nil || note.on == nil {
//                 continue
//             }
//             if prev_note.off.time > note.on.time {
//                 prev_note.off.time = note.on.time
//             }
//             if prev_note.on == nil {
//                 continue
//             }
//             if prev_note.off.time < prev_note.on.time {
//                 prev_note.off.time = prev_note.on.time
//             }
//         }
//     }
// }

_sort_events_by_time :: proc(cs: ^Cs_Corrector) {
    slice.sort_by(cs.midi_events[:], proc(i, j: ^Midi_Event) -> bool {
        if i.time < j.time {
            return true
        } else {
            return false
        }
    })
}

_clear_unused_notes :: proc(cs: ^Cs_Corrector) {
    for notes, key in cs.notes {
        keep_notes: [dynamic]^Note
        for note in notes {
            if !_note_is_unused(cs, note) {
                append(&keep_notes, note)
            }
        }
        delete(cs.notes[key])
        cs.notes[key] = keep_notes
    }
}

_note_is_unused :: proc(cs: ^Cs_Corrector, note: ^Note) -> bool {
    if note == nil {
        return true
    }
    if note.on == nil {
        return true
    }
    if note.off == nil && cs.current_note[midi_key(note.on.data)] != note {
        return true
    }
    if note.off != nil && !_event_is_in_buffer(cs, note.off) {
        return true
    }
    return false
}

_event_is_in_buffer :: proc(cs: ^Cs_Corrector, event: ^Midi_Event) -> bool {
    if event == nil {
        return false
    }
    for buffer_event in cs.midi_events {
        if event == buffer_event {
            return true
        }
    }
    return false
}

Note :: struct {
    on: ^Midi_Event,
    off: ^Midi_Event,
}

Midi_Event :: struct {
    time: int,
    data: Midi_Message,
}

Midi_Message :: [3]u8

Midi_Message_Kind :: enum {
    Unknown,
    Note_Off,
    Note_On,
    Aftertouch,
    Cc,
    Patch_Change,
    Channel_Pressure,
    Pitch_Bend,
    Non_Musical,
};

midi_message_kind :: proc(data: Midi_Message) -> Midi_Message_Kind {
    status_code := data[0] & 0xF0
    switch status_code {
    case 0x80: return .Note_Off
    case 0x90: return .Note_On
    case 0xA0: return .Aftertouch
    case 0xB0: return .Cc
    case 0xC0: return .Patch_Change
    case 0xD0: return .Channel_Pressure
    case 0xE0: return .Pitch_Bend
    case 0xF0: return .Non_Musical
    case: return .Unknown
    }
}

midi_channel :: proc(data: Midi_Message) -> u8 { return min(15, data[0] & 0x0F) }
midi_key :: proc(data: Midi_Message) -> u8 { return min(127, data[1]) }
midi_velocity :: proc(data: Midi_Message) -> u8 { return min(127, data[2]) }
midi_cc_number :: proc(data: Midi_Message) -> u8 { return min(127, data[1]) }
midi_cc_value :: proc(data: Midi_Message) -> u8 { return min(127, data[2]) }