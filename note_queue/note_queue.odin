package note_queue

import "core:mem"
import "core:slice"

KEY_COUNT :: 128

Note_Event_Status :: enum {
    Unsent,
    Sent,
    Dead,
}

Note_Event_Kind :: enum {
    Off,
    On,
}

Note_Event :: struct {
    kind: Note_Event_Kind,
    status: Note_Event_Status,
    index: int,
    time: int,
    channel: int,
    key: int,
    velocity: f64,
}

Note_Queue :: struct {
    playhead: int,
    note_events: [dynamic]Note_Event,
}

create :: proc(len, cap: int, allocator := context.allocator) -> (res: Note_Queue, err: mem.Allocator_Error) #optional_allocator_error {
    return Note_Queue{note_events = make([dynamic]Note_Event, len, cap) or_return}, nil
}

destroy :: proc(nq: ^Note_Queue) {
    delete(nq.note_events)
    free(nq)
}

reset :: proc(nq: ^Note_Queue) {
    nq.playhead = 0
    resize(&nq.note_events, 0)
}

add_event :: proc(nq: ^Note_Queue, kind: Note_Event_Kind, time, channel, key: int, velocity: f64) {
    // TODO: Make this insert events in order in the first place instead of just sorting after.
    append(&nq.note_events, Note_Event{
        kind = kind,
        status = .Unsent,
        time = nq.playhead + time,
        channel = channel,
        key = key,
        velocity = velocity,
    })
    slice.sort_by(nq.note_events[:], proc(i, j: Note_Event) -> bool {
        if i.time < j.time {
            return true
        } else {
            return false
        }
    })
}

send_events :: proc(
    nq: ^Note_Queue,
    frame_count: int,
    user_data: rawptr,
    send_proc: proc(user_data: rawptr, kind: Note_Event_Kind, time, channel, key: int, velocity: f64),
) {
    // Send any unsent note events within the frame count and mark them as sent.
    for event in &nq.note_events {
        offset := event.time - nq.playhead
        if offset < frame_count {
            if event.status == .Unsent {
                event.status = .Sent
                send_proc(user_data, event.kind, offset, event.channel, event.key, event.velocity)
            }
        } else {
            break
        }
    }

    remove_dead_events(nq)

    // Increment the playhead if there are events in the queue, otherwise reset it.
    if len(nq.note_events) > 0 {
        nq.playhead += frame_count
    } else {
        nq.playhead = 0
    }
}

remove_dead_events :: proc(nq: ^Note_Queue) {
    event_count := len(nq.note_events)
    keep_position := 0

    for i in 0 ..< event_count {
        // Check the event against events later in the buffer.
        // Mark any dead events as dead.
        for j in i + 1 ..< event_count {
            if event_pair_is_dead(nq.note_events[i], nq.note_events[j]) {
                nq.note_events[i].status = .Dead
                nq.note_events[j].status = .Dead
            }
        }

        // Only keep events that are not dead.
        if nq.note_events[i].status != .Dead {
            if keep_position != i {
                nq.note_events[keep_position] = nq.note_events[i]
            }
            keep_position += 1
        }
    }

    resize(&nq.note_events, keep_position)
}

event_pair_is_dead :: proc(a, b: Note_Event) -> bool {
    return a.index == b.index && a.status == .Sent && b.status == .Sent
}