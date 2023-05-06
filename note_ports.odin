package main

import "clap"

note_ports_extension := clap.Plugin_Note_Ports{
    count = proc "c" (clap_plugin: ^clap.Plugin, is_input: bool) -> u32 {
        return 1
    },

    get = proc "c" (clap_plugin: ^clap.Plugin, index: u32, is_input: bool, info: ^clap.Note_Port_Info) -> bool {
        info.id = 0
        info.supported_dialects = {.Midi}
        info.preferred_dialect = {.Midi}
        write_string(info.name[:], "MIDI Port 1")
        return true
    },
}