package midi

Encoded_Message :: [3]u8

Note_Message_Kind :: enum {
    Off,
    On,
}

Note_Message :: struct {
    kind: Note_Message_Kind,
    channel: int,
    key: int,
    velocity: int,
}

decode_note_message :: proc(msg: Encoded_Message) -> (result: Note_Message, ok: bool) {
    status_code := msg[0] & 0xf0
    if status_code == 0x80 {
        result = Note_Message{
            kind = .Off,
            channel = int(msg[0] & 0x0f),
            key = int(msg[1]),
            velocity = int(msg[2]),
        }
        ok = true
    } else if status_code == 0x90 {
        result = Note_Message{
            kind = .On,
            channel = int(msg[0] & 0x0f),
            key = int(msg[1]),
            velocity = int(msg[2]),
        }
        ok = true
    }
    return
}

encode_note_message :: proc(msg: Note_Message) -> Encoded_Message {
    status := msg.channel - 1
    switch msg.kind {
    case .Off: status += 0x80
    case .On: status += 0x90
    }
    return Encoded_Message{
        u8(status),
        u8(msg.key),
        u8(msg.velocity),
    }
}