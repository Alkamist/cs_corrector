package main

import "core:c"

show_console_msg: proc "c" (msg: cstring)

Reaper_Plugin_Info :: struct {
    caller_version: c.int,
    hwnd_main: rawptr,
    register: proc "c" (name: cstring, info_struct: rawptr) -> c.int,
    get_func: proc "c" (name: cstring) -> rawptr,
}

reaper_load_functions :: proc "c" (reaper_plugin_info: ^Reaper_Plugin_Info) {
    if reaper_plugin_info == nil {
        return
    }
    show_console_msg = cast(type_of(show_console_msg))reaper_plugin_info.get_func("ShowConsoleMsg")
}