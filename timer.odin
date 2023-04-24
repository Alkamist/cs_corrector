package main

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
        plugin := get_plugin(clap_plugin)
        print(plugin, "test")
        // if cs.debug_text_changed {
        //     // popup(cs.debug_text)
        //     cs.debug_text_changed = false
        // }
    },
}