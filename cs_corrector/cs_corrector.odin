package cs_corrector

import "core:slice"
import "core:fmt"

print: proc(text: string)

KEY_COUNT :: 128

Cs_Corrector :: struct {
    midi_events: [dynamic]^Midi_Event,
    notes: [KEY_COUNT][dynamic]^Note,
    last_note: [KEY_COUNT]^Note,
    held_key: Maybe(u8),
    legato_first_delay: i32, // Freshly pressed key
    legato_level0_delay: i32, // Lowest velocity legato
    legato_level1_delay: i32,
    legato_level2_delay: i32,
    legato_level3_delay: i32, // Highest velocity legato
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

required_latency :: proc(cs: ^Cs_Corrector) -> u32 {
    return u32(max(0, -min(
        cs.legato_first_delay,
        cs.legato_level0_delay,
        cs.legato_level1_delay,
        cs.legato_level2_delay,
        cs.legato_level3_delay,
    )))
}

process_event :: proc(cs: ^Cs_Corrector, event: Midi_Event) {
    event := new_clone(event)
    delay := i32(0)

    #partial switch midi_message_kind(event.data) {
    case .Note_Off:
        event_key := midi_key(event.data)

        held_key, key_is_held := cs.held_key.?
        if key_is_held && event_key == held_key {
            cs.held_key = nil
        }

        // Finish the last note on this key
        if cs.last_note[event_key] != nil {
            cs.last_note[event_key].off = event
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
        cs.last_note[event_key] = note

        print(fmt.aprintf("%v", cs.midi_events))
    }

    event.time += u32(i32(required_latency(cs)) + delay)
    append(&cs.midi_events, event)
}

push_events :: proc(cs: ^Cs_Corrector, frame_count: u32, push_proc: proc(event: Midi_Event)) {
    _fix_note_overlaps(cs)
    _sort_events_by_time(cs)

    keep_events: [dynamic]^Midi_Event

    // Loop through events and push any that are inside the frame count
    for event in cs.midi_events {
        if event.time < frame_count {
            // print(fmt.aprintf("%v", cs.notes))
            push_proc(event^)
            free(event)
        } else {
            append(&keep_events, event)
        }
    }

    delete(cs.midi_events)
    cs.midi_events = keep_events

    _clear_unused_notes(cs)
    _descrease_event_times(cs, frame_count)
}

_descrease_event_times :: proc(cs: ^Cs_Corrector, time: u32) {
    for event in cs.midi_events {
        event.time -= time
    }
}

_fix_note_overlaps :: proc(cs: ^Cs_Corrector) {
    for notes in cs.notes {
        for i in 1 ..< len(notes) {
            off0 := notes[i - 1].off
            on1 := notes[i].on
            if off0 != nil && on1 != nil && off0.time >= on1.time {
                on0 := notes[i - 1].on
                correct_time := on1.time - 1
                if correct_time <= on0.time {
                    correct_time = on0.time + 1
                }
                off0.time = correct_time
            }
        }
    }
}

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
            if note.off == nil || _event_still_exists(cs, note.off) {
                append(&keep_notes, note)
            }
        }
        delete(cs.notes[key])
        cs.notes[key] = keep_notes
    }
}

_event_still_exists :: proc(cs: ^Cs_Corrector, event: ^Midi_Event) -> bool {
    for event_in_buffer in cs.midi_events {
        if event == event_in_buffer {
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
    time: u32,
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

midi_channel :: proc(data: Midi_Message) -> u8 { return data[0] & 0x0F }
midi_key :: proc(data: Midi_Message) -> u8 { return data[1] }
midi_velocity :: proc(data: Midi_Message) -> u8 { return data[2] }
midi_cc_number :: proc(data: Midi_Message) -> u8 { return data[1] }
midi_cc_value :: proc(msg: Midi_Message) -> u8 { return msg[2] }