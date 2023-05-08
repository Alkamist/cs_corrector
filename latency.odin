package main

import "clap"

set_latency :: proc(instance: ^Plugin_Instance, value: int) {
    instance.latency = value
    if instance.clap_host_latency == nil ||
       instance.clap_host_latency.changed == nil ||
       instance.clap_host.request_restart == nil {
        return
    }

    // Inform the host of the latency change.
    instance.clap_host_latency.changed(instance.clap_host)
    if instance.is_active {
        instance.clap_host->request_restart()
    }
}

latency_extension := clap.Plugin_Latency{
    get = proc "c" (plugin: ^clap.Plugin) -> u32 {
        instance := get_instance(plugin)
        return u32(max(0, instance.latency))
    },
}