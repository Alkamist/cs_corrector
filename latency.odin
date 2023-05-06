package main

import "clap"

set_latency :: proc(instance: ^Plugin_Instance, value: int) {
    instance.latency = value

    // Inform the host of the latency change.
    host_latency := cast(^clap.Host_Latency)(instance.clap_host->get_extension(clap.EXT_LATENCY))
    host_latency.changed(instance.clap_host)
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