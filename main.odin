package main

import "core:runtime"
import "clap"

factory_get_plugin_count :: proc "c" (factory: ^clap.Plugin_Factory) -> u32 {
    return 1
}

factory_get_plugin_descriptor :: proc "c" (factory: ^clap.Plugin_Factory, index: u32) -> ^clap.Plugin_Descriptor {
    return &plugin_descriptor
}

factory_create_plugin :: proc "c" (factory: ^clap.Plugin_Factory, host: ^clap.Host, plugin_id: cstring) -> ^clap.Plugin {
    context = runtime.default_context()
    if !clap.version_is_compatible(host.clap_version) {
        return nil;
    }
    if plugin_id == plugin_descriptor.id {
        return plugin_create_instance();
    }
    return nil;
}

main_init :: proc "c" (plugin_path: cstring) -> bool {
    return true;
}

main_deinit :: proc "c" () {}

main_get_factory :: proc "c" (factory_id: cstring) -> rawptr {
    if factory_id == clap.plugin_factory_id {
        return &factory;
    }
    return nil;
}

factory := clap.Plugin_Factory{
    get_plugin_count = factory_get_plugin_count,
    get_plugin_descriptor = factory_get_plugin_descriptor,
    create_plugin = factory_create_plugin,
};

@export
clap_entry := clap.Plugin_Entry{
	clap_version = clap.Version{1, 1, 7},
	init = main_init,
	deinit = main_deinit,
	get_factory = main_get_factory,
};