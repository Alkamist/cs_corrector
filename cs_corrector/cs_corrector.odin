package cs_corrector

import "core:slice"

// debug_text_changed := false
// debug_text: cstring

// debug :: proc(text: cstring) {
//     delete(debug_text)
//     debug_text = text
//     debug_text_changed = true
// }

KEY_COUNT :: 128

Cs_Corrector :: struct {
    midi_events: [dynamic]^Midi_Event,
    note_on_off_pairs: [KEY_COUNT][dynamic]Note_On_Off_Pair,
    held_key: Maybe(u8),
    legato_first_delay: i32, // Freshly pressed key
    legato_level0_delay: i32, // Lowest velocity legato
    legato_level1_delay: i32,
    legato_level2_delay: i32,
    legato_level3_delay: i32, // Highest velocity legato
}

destroy :: proc(cs: ^Cs_Corrector) {
    for pairs in cs.note_on_off_pairs {
        delete(pairs)
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

append_event :: proc(cs: ^Cs_Corrector, event: Midi_Event) {
    #partial switch midi_message_kind(event.data) {

    case .Note_Off:
        event_key := midi_key(event.data)

        held_key, key_is_held := cs.held_key.?
        if key_is_held && event_key == held_key {
            cs.held_key = nil
        }
        _append_with_delay(cs, event, 0)

        // Find the first unfinished note-on-off pair of the same key and finish it
        for pair in &cs.note_on_off_pairs[event_key] {
            if pair.off == nil {
                pair.off = _last_midi_event(cs)
                break
            }
        }

    case .Note_On:
        event_key := midi_key(event.data)

        _, key_is_held := cs.held_key.?
        if key_is_held {
            _append_with_delay(cs, event, cs.legato_level0_delay)
        } else {
            _append_with_delay(cs, event, cs.legato_first_delay)
        }
        cs.held_key = event_key

        // Start a note-on-off pair
        append(&cs.note_on_off_pairs[event_key], Note_On_Off_Pair{
            on = _last_midi_event(cs),
            off = nil,
        })

    case:
        _append_with_delay(cs, event, 0)
    }
}

push_midi_events :: proc(cs: ^Cs_Corrector, frame_count: u32, push_proc: proc(event: Midi_Event)) {
    _sort_midi_events_by_time(cs)
    _fix_note_overlaps(cs)

    keep_events: [dynamic]^Midi_Event

    // Loop through events and push any that are inside the frame count
    for event in cs.midi_events {
        if event.time < frame_count {
            // debug("test")
            push_proc(event^)
            #partial switch midi_message_kind(event.data) {
            case .Note_Off, .Note_On:
                _mark_note_event_sent(cs, event)
            }
            free(event)
        } else {
            append(&keep_events, event)
        }
    }

    delete(cs.midi_events)
    cs.midi_events = keep_events

    _decrease_midi_events_time(cs, frame_count)
}

_mark_note_event_sent :: proc(cs: ^Cs_Corrector, event: ^Midi_Event) {
    key := midi_key(event.data)
    for pair in &cs.note_on_off_pairs[key] {
        if pair.on == event {
            pair.on_sent = true
        }
        if pair.off == event {
            pair.off_sent = true
        }
    }
}

_fix_note_overlaps :: proc(cs: ^Cs_Corrector) {
    _clear_unused_note_on_off_pairs(cs)
    _sort_note_on_off_pairs_by_time(cs)
    for pairs in &cs.note_on_off_pairs {
        for i in 1 ..< len(pairs) {
            off := pairs[i - 1].off
            on := pairs[i].on
            if off != nil && on != nil && off.time >= on.time {
                off.time = on.time - 1
            }
        }
    }
}

_clear_unused_note_on_off_pairs :: proc(cs: ^Cs_Corrector) {
    keep_pairs: [KEY_COUNT][dynamic]Note_On_Off_Pair

    for pairs, key in &cs.note_on_off_pairs {
        for pair in &pairs {
            if !pair.on_sent || !pair.off_sent {
                append(&keep_pairs[key], pair)
            }
        }
        delete(cs.note_on_off_pairs[key])
    }

    cs.note_on_off_pairs = keep_pairs
}

_last_midi_event :: proc(cs: ^Cs_Corrector) -> ^Midi_Event {
    return cs.midi_events[len(cs.midi_events) - 1]
}

_append_with_delay :: proc(cs: ^Cs_Corrector, event: Midi_Event, delay: i32) {
    event := new_clone(event)
    event.time += u32(i32(required_latency(cs)) + delay)
    append(&cs.midi_events, event)
}

_decrease_midi_events_time :: proc(cs: ^Cs_Corrector, time: u32) {
    for event in cs.midi_events {
        event.time -= time
    }
}

_sort_note_on_off_pairs_by_time :: proc(cs: ^Cs_Corrector) {
    for pairs in &cs.note_on_off_pairs {
        slice.sort_by(pairs[:], proc(i, j: Note_On_Off_Pair) -> bool {
            if i.on.time < j.on.time {
                return true
            } else {
                return false
            }
        })
    }
}

_sort_midi_events_by_time :: proc(cs: ^Cs_Corrector) {
    slice.sort_by(cs.midi_events[:], proc(i, j: ^Midi_Event) -> bool {
        if i.time < j.time {
            return true
        } else {
            return false
        }
    })
}

Note_On_Off_Pair :: struct {
    on: ^Midi_Event,
    on_sent: bool,
    off: ^Midi_Event,
    off_sent: bool,
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