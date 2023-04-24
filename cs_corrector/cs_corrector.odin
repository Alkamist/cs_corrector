package cs_corrector

import "core:slice"

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
        for _, i in cs.note_on_off_pairs[event_key] {
            unfinished := cs.note_on_off_pairs[event_key][i].off == nil
            if unfinished {
                cs.note_on_off_pairs[event_key][i].off = _last_midi_event(cs)
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

push_midi_events :: proc(cs: ^Cs_Corrector, frame_count: u32, push_proc: proc(event: ^Midi_Event)) {
    _fix_note_overlaps(cs)
    _sort_midi_events_by_time_backwards(cs)

    event_count := len(cs.midi_events)
    smallest_index_sent := event_count

    // Go through events backwards (forwards in time)
    // and push any that are inside the frame count
    for i := event_count - 1; i >= 0; i -= 1 {
        event := cs.midi_events[i]
        if event.time < frame_count {
            push_proc(event)
            free(event)
            smallest_index_sent = i
        } else {
            break
        }
    }

    // Resize the buffer to chop off the events that were sent
    if smallest_index_sent < event_count {
        resize(&cs.midi_events, smallest_index_sent)
    }

    _decrease_midi_events_time(cs, frame_count)
}

_fix_note_overlaps :: proc(cs: ^Cs_Corrector) {
    for pairs in cs.note_on_off_pairs {
        for i in 1 ..< len(pairs) {
            if pairs[i - 1].off.time >= pairs[i].on.time {
                pairs[i - 1].off.time = pairs[i].on.time - 1
            }
        }
    }
}

_clear_unused_note_on_off_pairs :: proc(cs: ^Cs_Corrector) {
    keep_pairs: [KEY_COUNT][dynamic]Note_On_Off_Pair
    for pairs, key in cs.note_on_off_pairs {
        for pair in pairs {
            if pair.on != nil || pair.off != nil {
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
    for _, i in cs.midi_events {
        cs.midi_events[i].time -= time
    }
}

_sort_midi_events_by_time_backwards :: proc(cs: ^Cs_Corrector) {
    slice.sort_by(cs.midi_events[:], proc(i, j: ^Midi_Event) -> bool {
        if i.time >= j.time {
            return true
        } else {
            return false
        }
    })
}

Note_On_Off_Pair :: struct {
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