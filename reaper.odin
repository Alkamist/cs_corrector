package main

import "clap"
import "core:c"

// show_console_msg :: proc "c" (plugin: ^Plugin, text: cstring) {
//     reaper_plugin_info := cast(^Reaper_Plugin_Info)plugin.clap_host.get_extension(plugin.clap_host, "cockos.reaper_extension")
//     show_console_msg := cast(ShowConsoleMsg)reaper_plugin_info.get_func("ShowConsoleMsg")
//     if show_console_msg != nil {
//         show_console_msg(text)
//     }
// }

// ShowConsoleMsg :: #type proc "c" (msg: cstring)

reaper_load_functions :: proc "c" (clap_host: ^clap.Host) {
    reaper_plugin_info := cast(^Reaper_Plugin_Info)clap_host.get_extension(clap_host, "cockos.reaper_extension")
    show_console_msg = cast(type_of(show_console_msg))reaper_plugin_info.get_func("ShowConsoleMsg")
}

show_console_msg: proc "c" (msg: cstring)

Reaper_Plugin_Info :: struct {
    caller_version: c.int,
    hwnd_main: rawptr,
    register: proc "c" (name: cstring, info_struct: rawptr) -> c.int,
    get_func: proc "c" (name: cstring) -> rawptr,
}