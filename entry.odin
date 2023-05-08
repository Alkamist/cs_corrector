package main

import "clap"
import "core:runtime"

create_instance :: proc(host: ^clap.Host) -> ^clap.Plugin {
    instance := new(Plugin_Instance)
    instance.clap_host = host
    instance.clap_plugin = {
        desc = &plugin_descriptor,
        plugin_data = instance,
        init = instance_init,
        destroy = instance_destroy,
        activate = instance_activate,
        deactivate = instance_deactivate,
        start_processing = instance_start_processing,
        stop_processing = instance_stop_processing,
        reset = instance_reset,
        process = instance_process,
        get_extension = instance_get_extension,
        on_main_thread = instance_on_main_thread,
    }
    return &instance.clap_plugin
}

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
        // reaper_load_functions(host)
        if plugin_id == plugin_descriptor.id {
            return create_instance(host)
        }
        return nil
    },
}

@export
clap_entry := clap.Plugin_Entry{
	clap_version = CLAP_VERSION,

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