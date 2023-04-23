package main

import "clap"

get_note_port_count :: proc "c" (clap_plugin: ^clap.Plugin, is_input: bool) -> u32 {
    return 1
}

get_note_port_info :: proc "c" (clap_plugin: ^clap.Plugin, index: u32, is_input: bool, info: ^clap.Note_Port_Info) -> bool {
    info.id = 0
    info.supported_dialects = {.Midi}
    info.preferred_dialect = {.Midi}
    // clap.write_name(&info.name, `MIDI Port 1`)
    return true
}

note_ports_extension := clap.Plugin_Note_Ports{
    count = get_note_port_count,
    get = get_note_port_info,
}