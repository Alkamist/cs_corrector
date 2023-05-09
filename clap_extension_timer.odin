package main

import "core:runtime"

register_timer :: proc(plugin: ^Audio_Plugin, name: string, period_ms: int, timer_proc: proc(plugin: ^Audio_Plugin)) {
    if plugin.clap_host_timer_support == nil ||
       plugin.clap_host_timer_support.register_timer == nil {
        return
    }
    id: Clap_Id
    plugin.clap_host_timer_support.register_timer(plugin.clap_host, u32(period_ms), &id)
    plugin.timer_name_to_id[name] = id
    plugin.timer_id_to_proc[id] = timer_proc
}

unregister_timer :: proc(plugin: ^Audio_Plugin, name: string) {
    if plugin.clap_host_timer_support == nil ||
       plugin.clap_host_timer_support.unregister_timer == nil {
        return
    }
    if id, ok := plugin.timer_name_to_id[name]; ok {
        id := plugin.timer_name_to_id[name]
        plugin.clap_host_timer_support.unregister_timer(plugin.clap_host, id)
        plugin.timer_id_to_proc[id] = nil
    }
}

clap_extension_timer := Clap_Plugin_Timer_Support{
    on_timer = proc "c" (clap_plugin: ^Clap_Plugin, timer_id: Clap_Id) {
        context = runtime.default_context()
        plugin := get_instance(clap_plugin)
        if timer_proc, ok := plugin.timer_id_to_proc[timer_id]; ok {
            timer_proc(plugin)
        }
    },
}