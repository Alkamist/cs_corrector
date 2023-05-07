package main

import "clap"
import "core:fmt"
import "core:strconv"
import "core:sync"
import "core:runtime"

PARAMETER_COUNT :: len(Parameter)

Parameter :: enum {
    Legato_First_Note_Delay,
    Legato_Portamento_Delay,
    Legato_Slow_Delay,
    Legato_Medium_Delay,
    Legato_Fast_Delay,
}

parameter_info := [PARAMETER_COUNT]Parameter_Info{
    {
        id = .Legato_First_Note_Delay,
        flags = {.Is_Automatable},
        name = "Legato First Note Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -60.0,
    }, {
        id = .Legato_Portamento_Delay,
        flags = {.Is_Automatable},
        name = "Legato Portamento Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -300.0,
    }, {
        id = .Legato_Slow_Delay,
        flags = {.Is_Automatable},
        name = "Legato Slow Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -300.0,
    }, {
        id = .Legato_Medium_Delay,
        flags = {.Is_Automatable},
        name = "Legato Medium Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -300.0,
    }, {
        id = .Legato_Fast_Delay,
        flags = {.Is_Automatable},
        name = "Legato Fast Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -150.0,
    },
}

Parameter_Info :: struct {
    id: Parameter,
    flags: bit_set[clap.Param_Info_Flags; clap.Id],
    name: string,
    module: string,
    min_value: f64,
    max_value: f64,
    default_value: f64,
}

parameter :: proc "c" (instance: ^Plugin_Instance, id: Parameter) -> f64 {
    return instance.audio_thread_parameter_value[id]
}

parameters_sync_main_to_audio :: proc "c" (instance: ^Plugin_Instance, out_events: ^clap.Output_Events) {
    sync.lock(&instance.parameter_mutex)
    for i in 0 ..< PARAMETER_COUNT {
        if instance.main_thread_parameter_changed[i] {
            instance.audio_thread_parameter_value[i] = instance.main_thread_parameter_value[i]
            instance.main_thread_parameter_changed[i] = false

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
                value = instance.audio_thread_parameter_value[i],
            }
            out_events->try_push(&event.header)
        }
    }
    sync.unlock(&instance.parameter_mutex)
}

parameters_sync_audio_to_main :: proc "c" (instance: ^Plugin_Instance) {
    sync.lock(&instance.parameter_mutex)
    for i in 0 ..< PARAMETER_COUNT {
        if instance.audio_thread_parameter_changed[i] {
            instance.main_thread_parameter_value[i] = instance.audio_thread_parameter_value[i]
            instance.audio_thread_parameter_changed[i] = false
        }
    }
    sync.unlock(&instance.parameter_mutex)
}

parameters_extension := clap.Plugin_Params{
    count = proc "c" (plugin: ^clap.Plugin) -> u32 {
        return len(Parameter)
    },

    get_info = proc "c" (plugin: ^clap.Plugin, param_index: u32, param_info: ^clap.Param_Info) -> bool {
        param_info.id = u32(parameter_info[param_index].id)
        param_info.flags = parameter_info[param_index].flags
        write_string(param_info.name[:], parameter_info[param_index].name)
        write_string(param_info.module[:], parameter_info[param_index].module)
        param_info.min_value = parameter_info[param_index].min_value
        param_info.max_value = parameter_info[param_index].max_value
        param_info.default_value = parameter_info[param_index].default_value
        return true
    },

    get_value = proc "c" (plugin: ^clap.Plugin, param_id: clap.Id, out_value: ^f64) -> bool {
        instance := get_instance(plugin)
        sync.lock(&instance.parameter_mutex)
        if instance.main_thread_parameter_changed[param_id] {
            out_value^ = instance.main_thread_parameter_value[param_id]
        } else {
            out_value^ = instance.audio_thread_parameter_value[param_id]
        }
        sync.unlock(&instance.parameter_mutex)
        return true
    },

    value_to_text = proc "c" (plugin: ^clap.Plugin, param_id: clap.Id, value: f64, out_buffer: [^]byte, out_buffer_capacity: u32) -> bool {
        if PARAMETER_COUNT == 0 {
            return false
        }
        context = runtime.default_context()
        value_string := fmt.aprintf("%v", value)
        write_string(out_buffer[:out_buffer_capacity], value_string)
        return true
    },

    text_to_value = proc "c" (plugin: ^clap.Plugin, param_id: clap.Id, param_value_text: cstring, out_value: ^f64) -> bool {
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

    flush = proc "c" (plugin: ^clap.Plugin, input: ^clap.Input_Events, output: ^clap.Output_Events) {
        instance := get_instance(plugin)
        event_count := input->size()
        parameters_sync_main_to_audio(instance, output)
        for i in 0 ..< event_count {
            event_header := input->get(i)
            if event_header.type == .Param_Value {
                event := cast(^clap.Event_Param_Value)event_header
                sync.lock(&instance.parameter_mutex)
                instance.audio_thread_parameter_value[event.param_id] = event.value
                instance.audio_thread_parameter_changed[event.param_id] = true
                sync.unlock(&instance.parameter_mutex)
            }
        }
    },
}