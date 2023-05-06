package main

import "clap"

get_instance :: proc "c" (clap_plugin: ^clap.Plugin) -> ^Plugin_Instance {
    return cast(^Plugin_Instance)clap_plugin.plugin_data
}

write_string :: proc "c" (buffer: []byte, value: string) {
    n := copy(buffer, value)
    // enforce NUL termination
    buffer[min(n, len(buffer) - 1)] = 0
}