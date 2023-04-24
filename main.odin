package main

import "core:runtime"
import "clap"

plugin_factory := clap.Plugin_Factory{
    get_plugin_count = proc "c" (factory: ^clap.Plugin_Factory) -> u32 {
        return 1
    },

    get_plugin_descriptor = proc "c" (factory: ^clap.Plugin_Factory, index: u32) -> ^clap.Plugin_Descriptor {
        return &plugin_descriptor
    },

    create_plugin = proc "c" (factory: ^clap.Plugin_Factory, host: ^clap.Host, plugin_id: cstring) -> ^clap.Plugin {
        context = runtime.default_context()

        if !clap.version_is_compatible(host.clap_version) {
            return nil
        }

        reaper_load_functions(host)

        if plugin_id == plugin_descriptor.id {
            return plugin_create_instance(host)
        }

        return nil
    },
}

@export
clap_entry := clap.Plugin_Entry{
	clap_version = clap.Version{1, 1, 7},

	init = proc "c" (plugin_path: cstring) -> bool {
        return true
    },

	deinit = proc "c" () {
    },

	get_factory = proc "c" (factory_id: cstring) -> rawptr {
        if factory_id == clap.PLUGIN_FACTORY_ID {
            return &plugin_factory
        }

        return nil
    },
}