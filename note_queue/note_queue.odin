package note_queue

import "core:mem"

KEY_COUNT :: 128
CHANNEL_COUNT :: 16

Note_Event_Kind :: enum {
    Off,
    On,
}

Note_Event :: struct {
    kind: Note_Event_Kind,
    time: int,
    channel: int,
    key: int,
    velocity: f64,
}

Note_Queue :: struct {
    playhead: int,
    note_events: [dynamic]Note_Event,
    last_event_sent: [CHANNEL_COUNT][KEY_COUNT]Maybe(Note_Event),
    pending_note_off_count: [CHANNEL_COUNT][KEY_COUNT]int,
}

create :: proc(len, cap: int, allocator := context.allocator) -> (result: Note_Queue, err: mem.Allocator_Error) #optional_allocator_error {
    return Note_Queue{note_events = make([dynamic]Note_Event, len, cap, allocator) or_return}, nil
}

destroy :: proc(nq: ^Note_Queue) {
    delete(nq.note_events)
}

reset :: proc(nq: ^Note_Queue) {
    nq.playhead = 0
    clear(&nq.note_events)
    for channel in 0 ..< CHANNEL_COUNT {
        for key in 0 ..< KEY_COUNT {
            nq.last_event_sent[channel][key] = nil
            nq.pending_note_off_count[channel][key] = 0
        }
    }
}

add_event :: proc(nq: ^Note_Queue, kind: Note_Event_Kind, time, channel, key: int, velocity: f64) {
    event := Note_Event{
        kind = kind,
        time = nq.playhead + time,
        channel = channel,
        key = key,
        velocity = velocity,
    }

    count := len(nq.note_events)

    // Insert events sorted by time.
    if count == 0 {
        append(&nq.note_events, event)
    } else {
        for i in 0 ..< count {
            if event.time < nq.note_events[i].time {
                inject_at(&nq.note_events, i, event)
                break
            }
            if i == count - 1 {
                append(&nq.note_events, event)
            }
        }
    }
}

send_events :: proc(
    nq: ^Note_Queue,
    frame_count: int,
    user_data: rawptr,
    send_proc: proc(user_data: rawptr, kind: Note_Event_Kind, time, channel, key: int, velocity: f64),
) {
    keep_position := 0

    for i in 0 ..< len(nq.note_events) {
        event := nq.note_events[i]
        offset := event.time - nq.playhead

        // Send the event if it is inside the frame count.
        if offset < frame_count {
            channel := event.channel
            key := event.key

            if last_event, ok := nq.last_event_sent[channel][key].?; ok {
                // If two note-ons in a row are detected,
                // send a note off first to avoid overlaps.
                if last_event.kind == .On && event.kind == .On {
                    send_proc(user_data, .Off, offset, channel, key, 0.0)
                    nq.last_event_sent[channel][key] = event
                    nq.pending_note_off_count[channel][key] += 1
                }
            }

            // Always send note-ons, but ignore lingering note-offs that
            // were sent early because of a note-on overlap.
            if event.kind == .On || nq.pending_note_off_count[channel][key] == 0 {
                send_proc(user_data, event.kind, offset, channel, key, event.velocity)
                nq.last_event_sent[channel][key] = event
            } else {
                nq.pending_note_off_count[channel][key] -= 1
                if nq.pending_note_off_count[channel][key] < 0 {
                    nq.pending_note_off_count[channel][key] = 0
                }
            }

        // Keep the event otherwise.
        } else {
            if keep_position != i {
                nq.note_events[keep_position] = event
            }
            keep_position += 1
        }
    }

    resize(&nq.note_events, keep_position)

    // Increment the playhead if there are no events, otherwise reset it.
    if len(nq.note_events) > 0 {
        nq.playhead += frame_count
    } else {
        nq.playhead = 0
    }
}