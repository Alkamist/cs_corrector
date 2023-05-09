package main

set_latency :: proc(instance: ^Audio_Plugin, value: int) {
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

clap_extension_latency := Clap_Plugin_Latency{
    get = proc "c" (plugin: ^Clap_Plugin) -> u32 {
        instance := get_instance(plugin)
        return u32(max(0, instance.latency))
    },
}