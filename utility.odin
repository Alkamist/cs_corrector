package main

import "core:runtime"
import "core:strings"
import "clap"

get_instance :: proc "c" (clap_plugin: ^clap.Plugin) -> ^Plugin_Instance {
    return cast(^Plugin_Instance)clap_plugin.plugin_data
}

write_string :: proc "c" (buffer: []byte, value: string) {
    n := copy(buffer, value)
    // enforce NUL termination
    buffer[min(n, len(buffer) - 1)] = 0
}

log :: proc(instance: ^Plugin_Instance, severity: clap.Log_Severity, msg: string) {
    if instance.clap_host_log == nil || instance.clap_host_log.log == nil {
        return
    }
    context = runtime.default_context()
    msg_cstring := strings.clone_to_cstring(msg)
    defer delete(msg_cstring)
    instance.clap_host_log.log(instance.clap_host, severity, msg_cstring)
}