package cs_corrector

import "core:slice"

Cs_Corrector :: struct {
    midi_events: [dynamic]Midi_Event,
    held_key: Maybe(u8),
    legato_first_delay: i32, // Freshly pressed key
    legato_level0_delay: i32, // Lowest velocity legato
    legato_level1_delay: i32,
    legato_level2_delay: i32,
    legato_level3_delay: i32, // Highest velocity legato
}

destroy :: proc(cs: ^Cs_Corrector) {
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
        held_key, key_is_held := cs.held_key.?
        if key_is_held && midi_key(event.data) == held_key {
            cs.held_key = nil
        }
        _append_with_delay(cs, event, 0)

    case .Note_On:
        _, key_is_held := cs.held_key.?
        if key_is_held {
            _append_with_delay(cs, event, cs.legato_level0_delay)
        } else {
            _append_with_delay(cs, event, cs.legato_first_delay)
        }
        cs.held_key = midi_key(event.data)

    case:
        _append_with_delay(cs, event, 0)
    }
}

push_midi_events :: proc(cs: ^Cs_Corrector, frame_count: u32, push_proc: proc(event: Midi_Event)) {
    _sort_midi_events_by_time_backwards(cs)

    event_count := len(cs.midi_events)
    smallest_index_sent := event_count

    for i := event_count - 1; i >= 0; i -= 1 {
        event := cs.midi_events[i]
        if event.time < frame_count {
            push_proc(event)
            smallest_index_sent = i
        } else {
            break
        }
    }

    if smallest_index_sent < event_count {
        resize(&cs.midi_events, smallest_index_sent)
    }

    _decrease_midi_events_time(cs, frame_count)
}

_append_with_delay :: proc(cs: ^Cs_Corrector, event: Midi_Event, delay: i32) {
    delayed_event := event
    delayed_event.time += u32(i32(required_latency(cs)) + delay)
    append(&cs.midi_events, delayed_event)
}

_decrease_midi_events_time :: proc(cs: ^Cs_Corrector, time: u32) {
    for _, i in cs.midi_events {
        cs.midi_events[i].time -= time
    }
}

_sort_midi_events_by_time_backwards :: proc(cs: ^Cs_Corrector) {
    slice.sort_by(cs.midi_events[:], proc(i, j: Midi_Event) -> bool {
        if i.time >= j.time {
            return true
        } else {
            return false
        }
    })
}

Midi_Message :: [3]u8

Midi_Event :: struct {
    time: u32,
    data: Midi_Message,
}

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