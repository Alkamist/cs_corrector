package midi

Message :: [3]u8

Message_Kind :: enum {
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

message_kind :: proc(msg: Message) -> Message_Kind {
    status_code := msg[0] & 0xF0
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

channel :: proc(msg: Message) -> u8 {
    return msg[0] & 0x0F
}

key :: proc(msg: Message) -> u8 {
    return msg[1]
}

velocity :: proc(msg: Message) -> u8 {
    return msg[2]
}

cc_number :: proc(msg: Message) -> u8 {
    return msg[1]
}

cc_value :: proc(msg: Message) -> u8 {
    return msg[2]
}