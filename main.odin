package main

import "core:runtime"
import "clap"
import "plugin"

create_plugin :: proc "c" (factory: ^clap.Plugin_Factory, host: ^clap.Host, plugin_id: cstring) -> ^clap.Plugin {
    context = runtime.default_context()
    if !clap.version_is_compatible(host.clap_version) {
        return nil;
    }
    if plugin_id == plugin.descriptor.id {
        return plugin.create_instance();
    }
    return nil;
}

init :: proc "c" (plugin_path: cstring) -> bool {
    return true;
}

deinit :: proc "c" () {}

get_factory :: proc "c" (factory_id: cstring) -> rawptr {
    if factory_id == clap.plugin_factory_id {
        return &factory;
    }
    return nil;
}

factory := clap.Plugin_Factory{
    get_plugin_count = plugin.get_count,
    get_plugin_descriptor = plugin.get_descriptor,
    create_plugin = create_plugin,
};

@export
clap_entry := clap.Plugin_Entry{
	clap_version = clap.Version{1, 1, 7},
	init = init,
	deinit = deinit,
	get_factory = get_factory,
};