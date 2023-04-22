package note_ports

import "../../../clap"

get_count :: proc "c" (clap_plugin: ^clap.Plugin, is_input: bool) -> u32 {
    return 1
}

get_note_port :: proc "c" (clap_plugin: ^clap.Plugin, index: u32, is_input: bool, info: ^clap.Note_Port_Info) -> bool {
    info.id = 0
    info.supported_dialects = {.Midi}
    info.preferred_dialect = {.Midi}
    // info.name = "MIDI Port 1"
    return true
}

extension := clap.Plugin_Note_Ports{
    count = get_count,
    get = get_note_port,
}