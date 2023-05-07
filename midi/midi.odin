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
    if status_code == 0x80 || status_code == 0x90 {
        result = Note_Message{
            kind = .Off,
            channel = int(msg[0] & 0x0f),
            key = int(msg[1]),
            velocity = int(msg[2]),
        }
        if status_code == 0x90 && result.velocity > 0 {
            result.kind = .On
        }
        ok = true
    }
    return
}

encode_note_message :: proc(msg: Note_Message) -> Encoded_Message {
    status := msg.channel
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

// import "core:testing"
// import "core:fmt"

// @test
// test_note_message_decoding :: proc(t: ^testing.T) {
//     encoded_msg := [3]u8{0x91, 0x40, 0x40}
//     msg, ok := decode_note_message(encoded_msg)
//     assert(ok)
//     assert(msg == Note_Message{kind = .On, channel = 1, key = 64, velocity = 64})

//     encoded_msg2 := [3]u8{0x81, 0x40, 0x40}
//     msg2, ok2 := decode_note_message(encoded_msg2)
//     assert(ok2)
//     assert(msg2 == Note_Message{kind = .Off, channel = 1, key = 64, velocity = 64})

//     encoded_msg3 := [3]u8{0x91, 0x40, 0x00}
//     msg3, ok3 := decode_note_message(encoded_msg3)
//     assert(ok3)
//     assert(msg3 == Note_Message{kind = .Off, channel = 1, key = 64, velocity = 0})
// }

// @test
// test_note_message_encoding :: proc(t: ^testing.T) {
//     msg := Note_Message{kind = .On, channel = 1, key = 64, velocity = 64}
//     encoded_msg := encode_note_message(msg)
//     assert(encoded_msg == [3]u8{0x91, 0x40, 0x40})

//     msg2 := Note_Message{kind = .Off, channel = 1, key = 64, velocity = 64}
//     encoded_msg2 := encode_note_message(msg2)
//     assert(encoded_msg2 == [3]u8{0x81, 0x40, 0x40})

//     msg3 := Note_Message{kind = .On, channel = 1, key = 64, velocity = 0}
//     encoded_msg3 := encode_note_message(msg3)
//     assert(encoded_msg3 == [3]u8{0x91, 0x40, 0x00})
// }