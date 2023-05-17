package main

import nq "note_queue"

CHANNEL_COUNT :: nq.CHANNEL_COUNT
DELAY_COUNT :: 4

Cs_Corrector_Logic :: struct {
    plugin: ^Audio_Plugin,
    note_queue: nq.Note_Queue,
    is_playing: bool,
    was_playing: bool,
    held_key: [CHANNEL_COUNT]Maybe(int),
    hold_pedal_is_virtually_held: [CHANNEL_COUNT]bool,
    hold_pedal_is_physically_held: [CHANNEL_COUNT]bool,
    legato_first_note_delay: int,
    legato_delay_times: [DELAY_COUNT]int,
    legato_delay_velocities: [DELAY_COUNT]f64,
}

cs_corrector_destroy :: proc(cs: ^Cs_Corrector_Logic) {
    nq.destroy(&cs.note_queue)
}

cs_corrector_reset :: proc(cs: ^Cs_Corrector_Logic) {
    nq.reset(&cs.note_queue)
    cs.held_key = nil
    cs.hold_pedal_is_virtually_held = false
    cs.hold_pedal_is_physically_held = false
}

send_note_events :: proc(cs: ^Cs_Corrector_Logic, frame_count: int) {
    nq.send_events(&cs.note_queue, frame_count, cs.plugin,
        proc(plugin: rawptr, kind: nq.Note_Event_Kind, time, channel, key: int, velocity: f64)
    {
        plugin := cast(^Audio_Plugin)plugin
        send_midi_event(plugin, encode_note_as_midi_event(kind, time, channel, key, velocity))
    })
}

process_transport_event :: proc(cs: ^Cs_Corrector_Logic, event: Transport_Event) {
    if .Is_Playing in event.flags {
        cs.was_playing = cs.is_playing
        cs.is_playing = true
    } else {
        cs.was_playing = cs.is_playing
        cs.is_playing = false
        // Reset the note queue on playback stop.
        if cs.was_playing && !cs.is_playing {
            cs_corrector_reset(cs)
        }
    }
}

process_midi_event :: proc(cs: ^Cs_Corrector_Logic, event: Midi_Event) {
    // Don't process when project is not playing back so there isn't
    // an annoying delay when drawing notes on the piano roll
    if !cs.is_playing {
        send_midi_event(cs.plugin, event)
        return
    }

    msg := event.data
    status_code := msg[0] & 0xF0
    channel := int(msg[0] & 0x0F)

    is_note_off := status_code == 0x80
    if is_note_off {
        process_note_off(cs, event.time, channel, int(msg[1]), f64(msg[2]))
        return
    }

    is_note_on := status_code == 0x90
    if is_note_on {
        process_note_on(cs, event.time, channel, int(msg[1]), f64(msg[2]))
        return
    }

    is_cc := status_code == 0xB0
    is_hold_pedal := is_cc && msg[1] == 64
    if is_hold_pedal {
        is_held := msg[2] > 63
        process_hold_pedal(cs, channel, is_held)
        // Don't return because we need to send the hold pedal information
    }

    // Pass any events that aren't note on or off straight to the host
    event := event
    event.time += cs.plugin.latency
    send_midi_event(cs.plugin, event)
}

required_latency :: proc(cs: ^Cs_Corrector_Logic) -> int {
    latency := cs.legato_first_note_delay
    for delay in cs.legato_delay_times {
        if delay < latency {
            latency = delay
        }
    }
    return -min(0, latency)
}

process_note_on :: proc(cs: ^Cs_Corrector_Logic, time, channel, key: int, velocity: f64) {
    delay := required_latency(cs)

    _, key_is_held := cs.held_key[channel].?

    if key_is_held || cs.hold_pedal_is_virtually_held[channel] {
        v_bottom := 0.0
        for v_top, i in cs.legato_delay_velocities {
            if velocity > v_bottom && velocity <= v_top {
                delay += cs.legato_delay_times[i]
                break
            }
            v_bottom = v_top
        }
    } else {
        delay += cs.legato_first_note_delay
    }

    cs.held_key[channel] = key

    nq.add_event(
        &cs.note_queue,
        .On,
        time + delay,
        channel, key, velocity,
    )

    // The virtual hold pedal waits to activate until after the first note on
    if cs.hold_pedal_is_physically_held[channel] {
        cs.hold_pedal_is_virtually_held[channel] = true
    }
}

process_note_off :: proc(cs: ^Cs_Corrector_Logic, time, channel, key: int, velocity: f64) {
    held_key, _key_is_held := cs.held_key[channel].?

    if _key_is_held && held_key == key {
        cs.held_key[channel] = nil
    }

    delay := required_latency(cs)

    nq.add_event(
        &cs.note_queue,
        .Off,
        time + delay,
        channel, key, velocity,
    )
}

process_hold_pedal :: proc(cs: ^Cs_Corrector_Logic, channel: int, is_held: bool) {
    cs.hold_pedal_is_physically_held[channel] = is_held
    if is_held {
        // Only hold down the virtual hold pedal if there is already a key held
        _, key_is_held := cs.held_key[channel].?
        if key_is_held {
            cs.hold_pedal_is_virtually_held[channel] = true
        }
    } else {
        // The virtual hold pedal is always released with the real one
        cs.hold_pedal_is_virtually_held[channel] = false
    }
}

encode_note_as_midi_event :: proc(kind: nq.Note_Event_Kind, time, channel, key: int, velocity: f64) -> Midi_Event {
    status := channel
    switch kind {
    case .Off: status += 0x80
    case .On: status += 0x90
    }
    return Midi_Event{
        time = time,
        port = 0,
        data = {u8(status), u8(key), u8(velocity)},
    }
}