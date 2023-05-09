package main

import "core:runtime"

CLAP_VERSION :: Clap_Version{1, 1, 8}

clap_plugin_factory := Clap_Plugin_Factory{
    get_plugin_count = proc "c" (factory: ^Clap_Plugin_Factory) -> u32 {
        return 1
    },

    get_plugin_descriptor = proc "c" (factory: ^Clap_Plugin_Factory, index: u32) -> ^Clap_Plugin_Descriptor {
        return &clap_plugin_descriptor
    },

    create_plugin = proc "c" (factory: ^Clap_Plugin_Factory, host: ^Clap_Host, plugin_id: cstring) -> ^Clap_Plugin {
        context = runtime.default_context()
        if !clap_version_is_compatible(host.clap_version) {
            return nil
        }
        if plugin_id == clap_plugin_descriptor.id {
            instance := new(Audio_Plugin)
            instance.clap_host = host
            instance.clap_plugin = {
                desc = &clap_plugin_descriptor,
                plugin_data = instance,
                init = clap_plugin_init,
                destroy = clap_plugin_destroy,
                activate = clap_plugin_activate,
                deactivate = clap_plugin_deactivate,
                start_processing = clap_plugin_start_processing,
                stop_processing = clap_plugin_stop_processing,
                reset = clap_plugin_reset,
                process = clap_plugin_process,
                get_extension = clap_plugin_get_extension,
                on_main_thread = clap_plugin_on_main_thread,
            }
            return &instance.clap_plugin
        }
        return nil
    },
}

@export
clap_entry := Clap_Plugin_Entry{
	clap_version = CLAP_VERSION,

	init = proc "c" (plugin_path: cstring) -> bool {
        return true
    },

	deinit = proc "c" () {
    },

	get_factory = proc "c" (factory_id: cstring) -> rawptr {
        if factory_id == CLAP_PLUGIN_FACTORY_ID {
            return &clap_plugin_factory
        }
        return nil
    },
}