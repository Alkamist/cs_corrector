package main

import "clap"

latency_extension := clap.Plugin_Latency{
    get = proc "c" (clap_plugin: ^clap.Plugin) -> u32 {
        plugin := get_plugin(clap_plugin)
        return u32(max(0, plugin.latency))
    },
}