package main

set_latency :: proc(plugin: ^Audio_Plugin, value: int) {
    plugin.latency = value
    if plugin.clap_host_latency == nil ||
       plugin.clap_host_latency.changed == nil ||
       plugin.clap_host.request_restart == nil {
        return
    }

    // Inform the host of the latency change.
    plugin.clap_host_latency.changed(plugin.clap_host)
    if plugin.is_active {
        plugin.clap_host->request_restart()
    }
}

clap_extension_latency := Clap_Plugin_Latency{
    get = proc "c" (plugin: ^Clap_Plugin) -> u32 {
        plugin := get_instance(plugin)
        return u32(max(0, plugin.latency))
    },
}