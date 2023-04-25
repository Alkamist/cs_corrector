package main

import "core:sync"
import "core:runtime"
import "core:strings"
import "clap"
import cs "cs_corrector"

register_timer :: proc "c" (plugin: ^Plugin, period_ms: u32, id: ^clap.Id) {
    host_timer_support := cast(^clap.Host_Timer_Support)plugin.clap_host.get_extension(plugin.clap_host, clap.EXT_TIMER_SUPPORT)
    host_timer_support.register_timer(plugin.clap_host, period_ms, id)
}

unregister_timer :: proc "c" (plugin: ^Plugin, id: clap.Id) {
    host_timer_support := cast(^clap.Host_Timer_Support)plugin.clap_host.get_extension(plugin.clap_host, clap.EXT_TIMER_SUPPORT)
    host_timer_support.unregister_timer(plugin.clap_host, id)
}

timer_extension := clap.Plugin_Timer_Support{
    on_timer = proc "c" (clap_plugin: ^clap.Plugin, timer_id: clap.Id) {
        context = runtime.default_context()
        plugin := get_plugin(clap_plugin)

        if debug_text_changed {
            sync.lock(&debug_text_mutex)
            debug_text_cstring := strings.clone_to_cstring(strings.to_string(debug_text))
            show_console_msg(debug_text_cstring)
            delete(debug_text_cstring)
            strings.builder_reset(&debug_text)
            debug_text_changed = false
            sync.unlock(&debug_text_mutex)
        }
    },
}