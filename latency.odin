package main

import "clap"

get_latency :: proc "c" (clap_plugin: ^clap.Plugin) -> u32 {
    plugin := cast(^Plugin)clap_plugin.plugin_data
    return plugin.latency
}

latency_extension := clap.Plugin_Latency{
    get = get_latency,
}