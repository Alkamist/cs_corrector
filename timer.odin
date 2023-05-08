package main

import "core:runtime"
import "clap"

register_timer :: proc(instance: ^Plugin_Instance, name: string, period_ms: int, timer_proc: proc(instance: ^Plugin_Instance)) {
    if instance.clap_host_timer_support == nil ||
       instance.clap_host_timer_support.register_timer == nil {
        return
    }
    id: clap.Id
    instance.clap_host_timer_support.register_timer(instance.clap_host, u32(period_ms), &id)
    instance.timer_name_to_id[name] = id
    instance.timer_id_to_proc[id] = timer_proc
}

unregister_timer :: proc(instance: ^Plugin_Instance, name: string) {
    if instance.clap_host_timer_support == nil ||
       instance.clap_host_timer_support.unregister_timer == nil {
        return
    }
    if id, ok := instance.timer_name_to_id[name]; ok {
        id := instance.timer_name_to_id[name]
        instance.clap_host_timer_support.unregister_timer(instance.clap_host, id)
        instance.timer_id_to_proc[id] = nil
    }
}

timer_extension := clap.Plugin_Timer_Support{
    on_timer = proc "c" (clap_plugin: ^clap.Plugin, timer_id: clap.Id) {
        context = runtime.default_context()
        instance := get_instance(clap_plugin)
        if timer_proc, ok := instance.timer_id_to_proc[timer_id]; ok {
            timer_proc(instance)
        }
    },
}