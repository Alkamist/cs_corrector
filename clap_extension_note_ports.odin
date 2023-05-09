package main

send_midi_event :: proc(plugin: ^Audio_Plugin, event: Midi_Event) {
    append(&plugin.output_midi_events, Clap_Event_Midi{
        header = {
            size = size_of(Clap_Event_Midi),
            // after the bug in reaper gets fixed: time = u32(event.time)
            time = u32(event.time - plugin.latency),
            space_id = CLAP_CORE_EVENT_SPACE_ID,
            type = .Midi,
            flags = 0,
        },
        port_index = u16(event.port),
        data = event.data,
    })
}

dispatch_midi_event :: proc(plugin: ^Audio_Plugin, event_header: ^Clap_Event_Header) {
    clap_event := cast(^Clap_Event_Midi)event_header
    on_midi_event(plugin, Midi_Event{
        time = int(event_header.time),
        port = int(clap_event.port_index),
        data = clap_event.data,
    })
}

clap_extension_note_ports := Clap_Plugin_Note_Ports{
    count = proc "c" (plugin: ^Clap_Plugin, is_input: bool) -> u32 {
        return 1
    },
    get = proc "c" (plugin: ^Clap_Plugin, index: u32, is_input: bool, info: ^Clap_Note_Port_Info) -> bool {
        info.id = 0
        info.supported_dialects = {.Midi}
        info.preferred_dialect = {.Midi}
        write_string(info.name[:], "MIDI Port 1")
        return true
    },
}