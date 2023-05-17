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

Note :: struct {
    on: ^Note_Event,
    off: ^Note_Event,
}

Note_Queue :: struct {
    playhead: int,
    current_index: [KEY_COUNT]int,
    note_events: [dynamic]Note_Event,
    key_notes: [KEY_COUNT][dynamic]Note,
}

create :: proc(len, cap: int, allocator := context.allocator) -> (result: Note_Queue, err: mem.Allocator_Error) #optional_allocator_error {
    result = Note_Queue{
        note_events = make([dynamic]Note_Event, len, cap) or_return,
    }

    key_notes_len := len / KEY_COUNT
    key_notes_cap := cap / KEY_COUNT
    for key in 0 ..< KEY_COUNT {
        result.key_notes[key] = make([dynamic]Note, key_notes_len, key_notes_cap) or_return
    }

    return result, nil
}

destroy :: proc(nq: ^Note_Queue) {
    delete(nq.note_events)
    for key in 0 ..< KEY_COUNT {
        delete(nq.key_notes[key])
    }
    free(nq)
}

reset :: proc(nq: ^Note_Queue) {
    nq.playhead = 0
    for key in 0 ..< KEY_COUNT {
        nq.current_index[key] = 0
        clear(&nq.key_notes[key])
    }
    clear(&nq.note_events)
}

add_event :: proc(nq: ^Note_Queue, kind: Note_Event_Kind, time, channel, key: int, velocity: f64) {
    append(&nq.note_events, Note_Event{
        kind = kind,
        status = .Unsent,
        index = nq.current_index[key],
        time = nq.playhead + time,
        channel = channel,
        key = key,
        velocity = velocity,
    })
    if kind == .Off {
        nq.current_index[key] += 1
    }
}

send_events :: proc(
    nq: ^Note_Queue,
    frame_count: int,
    user_data: rawptr,
    send_proc: proc(user_data: rawptr, kind: Note_Event_Kind, time, channel, key: int, velocity: f64),
) {
    sort_note_events(nq)
    fix_note_overlaps(nq)

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

    // remove_dead_events(nq)

    // Increment the playhead if there are events in the queue, otherwise reset it.
    if len(nq.note_events) > 0 {
        nq.playhead += frame_count
    } else {
        nq.playhead = 0
        for key in 0 ..< KEY_COUNT {
            nq.current_index[key] = 0
        }
    }
}

// remove_dead_events :: proc(nq: ^Note_Queue) {
//     event_pair_is_dead :: proc(a, b: Note_Event) -> bool {
//         return a.index == b.index && a.status == .Sent && b.status == .Sent
//     }

//     event_count := len(nq.note_events)
//     keep_position := 0

//     for i in 0 ..< event_count {
//         // Check the event against events later in the buffer.
//         // Mark any dead events as dead.
//         for j in i + 1 ..< event_count {
//             if event_pair_is_dead(nq.note_events[i], nq.note_events[j]) {
//                 nq.note_events[i].status = .Dead
//                 nq.note_events[j].status = .Dead
//             }
//         }

//         // Only keep events that are not dead.
//         if nq.note_events[i].status != .Dead {
//             if keep_position != i {
//                 nq.note_events[keep_position] = nq.note_events[i]
//             }
//             keep_position += 1
//         }
//     }

//     resize(&nq.note_events, keep_position)
// }

sort_note_events :: proc(nq: ^Note_Queue) {
    slice.sort_by(nq.note_events[:], proc(i, j: Note_Event) -> bool {
        return i.time < j.time
    })
}

fix_note_overlaps :: proc(nq: ^Note_Queue) {
    populate_key_notes :: proc(nq: ^Note_Queue, key: int) {
        for event in &nq.note_events {
            if key == event.key {
                switch event.kind {
                case .Off:
                    // Complete the first note off with a matching index.
                    for note in &nq.key_notes[event.key] {
                        if note.off == nil && event.index == note.on.index {
                            note.off = &event
                            break
                        }
                    }
                case .On:
                    append(&nq.key_notes[event.key], Note{on = &event})
                }
            }
        }
    }
    for key in 0 ..< KEY_COUNT {
        populate_key_notes(nq, key)
        for i in 1 ..< len(nq.key_notes[key]) {
            prev_note_off := nq.key_notes[key][i - 1].off
            if prev_note_off != nil {
                note_on := nq.key_notes[key][i].on
                if prev_note_off.time > note_on.time {
                    prev_note_off.time = note_on.time
                }
            }
        }
        clear(&nq.key_notes[key])
    }
}