package main

import "clap"
import "core:fmt"
import "core:strconv"
import "core:sync"
import "core:runtime"

Parameter_Id :: enum {
    Delay,
}

parameter_info := [PARAMETER_COUNT]Parameter_Info{
    {
        id = .Delay,
        flags = {.Is_Automatable},
        name = "Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = 0.0,
    },
}

Parameter_Info :: struct {
    id: Parameter_Id,
    flags: bit_set[clap.Param_Info_Flags; clap.Id],
    name: string,
    module: string,
    min_value: f64,
    max_value: f64,
    default_value: f64,
}

Parameter :: struct {
    value: f64,
    changed: bool,
}

PARAMETER_COUNT :: len(Parameter_Id)

parameters_sync_main_to_audio :: proc "c" (plugin: ^Plugin, out_events: ^clap.Output_Events) {
    sync.lock(&plugin.parameter_mutex)

    for i in 0 ..< PARAMETER_COUNT {
        if plugin.parameters_main_thread[i].changed {
            plugin.parameters_audio_thread[i].value = plugin.parameters_main_thread[i].value
            plugin.parameters_main_thread[i].changed = false

            event := clap.Event_Param_Value{
                header = {
                    size = size_of(clap.Event_Param_Value),
                    time = 0,
                    space_id = clap.CORE_EVENT_SPACE_ID,
                    type = .Param_Value,
                    flags = 0,
                },
                param_id = u32(parameter_info[i].id),
                cookie = nil,
                note_id = -1,
                port_index = -1,
                channel = -1,
                key = -1,
                value = plugin.parameters_audio_thread[i].value,
            }
            out_events.try_push(out_events, &event.header)
        }
    }

    sync.unlock(&plugin.parameter_mutex)
}

parameters_sync_audio_to_main :: proc "c" (plugin: ^Plugin) {
    sync.lock(&plugin.parameter_mutex)

    for i in 0 ..< PARAMETER_COUNT {
        if plugin.parameters_audio_thread[i].changed {
            plugin.parameters_main_thread[i].value = plugin.parameters_audio_thread[i].value
            plugin.parameters_audio_thread[i].changed = false
        }
    }

    sync.unlock(&plugin.parameter_mutex)
}

parameters_extension := clap.Plugin_Params{
    count = proc "c" (clap_plugin: ^clap.Plugin) -> u32 {
        return len(Parameter_Id)
    },

    get_info = proc "c" (clap_plugin: ^clap.Plugin, param_index: u32, param_info: ^clap.Param_Info) -> bool {
        param_info.id = u32(parameter_info[param_index].id)
        param_info.flags = parameter_info[param_index].flags
        clap.write_string(param_info.name[:], parameter_info[param_index].name)
        clap.write_string(param_info.module[:], parameter_info[param_index].module)
        param_info.min_value = parameter_info[param_index].min_value
        param_info.max_value = parameter_info[param_index].max_value
        param_info.default_value = parameter_info[param_index].default_value
        return true
    },

    get_value = proc "c" (clap_plugin: ^clap.Plugin, param_id: clap.Id, out_value: ^f64) -> bool {
        plugin := get_plugin(clap_plugin)

        sync.lock(&plugin.parameter_mutex)

        if plugin.parameters_main_thread[param_id].changed {
            out_value^ = plugin.parameters_main_thread[param_id].value
        } else {
            out_value^ = plugin.parameters_audio_thread[param_id].value
        }

        sync.unlock(&plugin.parameter_mutex)

        return true
    },

    value_to_text = proc "c" (clap_plugin: ^clap.Plugin, param_id: clap.Id, value: f64, out_buffer: [^]byte, out_buffer_capacity: u32) -> bool {
        if PARAMETER_COUNT == 0 {
            return false
        }

        context = runtime.default_context()

        value_string := fmt.aprintf("%v", value)
        clap.write_string(out_buffer[:out_buffer_capacity], value_string)

        return true
    },

    text_to_value = proc "c" (clap_plugin: ^clap.Plugin, param_id: clap.Id, param_value_text: cstring, out_value: ^f64) -> bool {
        if PARAMETER_COUNT == 0 {
            return false
        }

        context = runtime.default_context()

        value, ok := strconv.parse_f64(cast(string)param_value_text)
        if ok {
            out_value^ = value
            return true
        } else {
            return false
        }
    },

    flush = proc "c" (clap_plugin: ^clap.Plugin, input: ^clap.Input_Events, output: ^clap.Output_Events) {
        plugin := get_plugin(clap_plugin)
        event_count := input.size(input)

        parameters_sync_main_to_audio(plugin, output)

        for i in 0 ..< event_count {
            event_header := input.get(input, i)
            if event_header.type == .Param_Value {
                event := cast(^clap.Event_Param_Value)event_header

                sync.lock(&plugin.parameter_mutex)

                plugin.parameters_audio_thread[event.param_id].value = event.value
                plugin.parameters_audio_thread[event.param_id].changed = true

                sync.unlock(&plugin.parameter_mutex)
            }
        }
    },
}