package main

import "core:fmt"
import "core:strconv"
import "core:sync"
import "core:runtime"

main_thread_parameter :: proc "c" (plugin: ^Audio_Plugin, id: Parameter) -> f64 {
    return plugin.main_thread_parameter_value[id]
}

set_main_thread_parameter :: proc "c" (plugin: ^Audio_Plugin, id: Parameter, value: f64) {
    plugin.main_thread_parameter_value[id] = value
    plugin.main_thread_parameter_changed[id] = true
}

audio_thread_parameter :: proc "c" (plugin: ^Audio_Plugin, id: Parameter) -> f64 {
    return plugin.audio_thread_parameter_value[id]
}

set_audio_thread_parameter :: proc "c" (plugin: ^Audio_Plugin, id: Parameter, value: f64) {
    plugin.audio_thread_parameter_value[id] = value
    plugin.audio_thread_parameter_changed[id] = true
}

parameters_sync_main_to_audio :: proc "c" (plugin: ^Audio_Plugin, out_events: ^Clap_Output_Events) {
    sync.lock(&plugin.parameter_mutex)
    for id in Parameter {
        if plugin.main_thread_parameter_changed[id] {
            plugin.audio_thread_parameter_value[id] = plugin.main_thread_parameter_value[id]
            plugin.main_thread_parameter_changed[id] = false

            event := Clap_Event_Param_Value{
                header = {
                    size = size_of(Clap_Event_Param_Value),
                    time = 0,
                    space_id = CLAP_CORE_EVENT_SPACE_ID,
                    type = .Param_Value,
                    flags = 0,
                },
                param_id = u32(parameter_info[id].id),
                cookie = nil,
                note_id = -1,
                port_index = -1,
                channel = -1,
                key = -1,
                value = plugin.audio_thread_parameter_value[id],
            }
            out_events->try_push(&event.header)
        }
    }
    sync.unlock(&plugin.parameter_mutex)
}

parameters_sync_audio_to_main :: proc "c" (plugin: ^Audio_Plugin) {
    sync.lock(&plugin.parameter_mutex)
    for id in Parameter {
        if plugin.audio_thread_parameter_changed[id] {
            plugin.main_thread_parameter_value[id] = plugin.audio_thread_parameter_value[id]
            plugin.audio_thread_parameter_changed[id] = false
        }
    }
    sync.unlock(&plugin.parameter_mutex)
}

parameter_flags_to_clap_flags :: proc "c" (flags: bit_set[Parameter_Flag]) -> bit_set[Clap_Param_Info_Flag; u32] {
    result: bit_set[Clap_Param_Info_Flag; u32]
    if .Is_Stepped in flags do result += {.Is_Stepped}
    if .Is_Periodic in flags do result += {.Is_Periodic}
    if .Is_Hidden in flags do result += {.Is_Hidden}
    if .Is_Read_Only in flags do result += {.Is_Read_Only}
    if .Is_Bypass in flags do result += {.Is_Bypass}
    if .Is_Automatable in flags do result += {.Is_Automatable}
    if .Is_Automatable_Per_Note_Id in flags do result += {.Is_Automatable_Per_Note_Id}
    if .Is_Automatable_Per_Key in flags do result += {.Is_Automatable_Per_Key}
    if .Is_Automatable_Per_Channel in flags do result += {.Is_Automatable_Per_Channel}
    if .Is_Automatable_Per_Port in flags do result += {.Is_Automatable_Per_Port}
    if .Is_Modulatable in flags do result += {.Is_Modulatable}
    if .Is_Modulatable_Per_Note_Id in flags do result += {.Is_Modulatable_Per_Note_Id}
    if .Is_Modulatable_Per_Key in flags do result += {.Is_Modulatable_Per_Key}
    if .Is_Modulatable_Per_Channel in flags do result += {.Is_Modulatable_Per_Channel}
    if .Is_Modulatable_Per_Port in flags do result += {.Is_Modulatable_Per_Port}
    if .Requires_Process in flags do result += {.Requires_Process}
    return result
}

dispatch_parameter_event :: proc(plugin: ^Audio_Plugin, event_header: ^Clap_Event_Header) {
    #partial switch event_header.type {
    case .Param_Value:
        clap_event := cast(^Clap_Event_Param_Value)event_header
        sync.lock(&plugin.parameter_mutex)
        id := Parameter(clap_event.param_id)
        plugin.audio_thread_parameter_value[id] = clap_event.value
        plugin.audio_thread_parameter_changed[id] = true
        sync.unlock(&plugin.parameter_mutex)
        on_parameter_event(plugin, Parameter_Event{
            id = Parameter(clap_event.param_id),
            kind = .Value,
            note_id = int(clap_event.note_id),
            port = int(clap_event.port_index),
            channel = int(clap_event.channel),
            key = int(clap_event.key),
            value = clap_event.value,
        })
    }
}

clap_extension_parameters := Clap_Plugin_Params{
    count = proc "c" (plugin: ^Clap_Plugin) -> u32 {
        return len(Parameter)
    },
    get_info = proc "c" (plugin: ^Clap_Plugin, param_index: u32, param_info: ^Clap_Param_Info) -> bool {
        id := Parameter(param_index)
        param_info.id = u32(parameter_info[id].id)
        param_info.flags = parameter_flags_to_clap_flags(parameter_info[id].flags)
        write_string(param_info.name[:], parameter_info[id].name)
        write_string(param_info.module[:], parameter_info[id].module)
        param_info.min_value = parameter_info[id].min_value
        param_info.max_value = parameter_info[id].max_value
        param_info.default_value = parameter_info[id].default_value
        return true
    },
    get_value = proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, out_value: ^f64) -> bool {
        plugin := get_instance(plugin)
        sync.lock(&plugin.parameter_mutex)
        id := Parameter(param_id)
        if plugin.main_thread_parameter_changed[id] {
            out_value^ = plugin.main_thread_parameter_value[id]
        } else {
            out_value^ = plugin.audio_thread_parameter_value[id]
        }
        sync.unlock(&plugin.parameter_mutex)
        return true
    },
    value_to_text = proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, value: f64, out_buffer: [^]byte, out_buffer_capacity: u32) -> bool {
        if len(Parameter) == 0 {
            return false
        }
        context = runtime.default_context()
        value_string := fmt.aprintf("%v", value)
        write_string(out_buffer[:out_buffer_capacity], value_string)
        return true
    },
    text_to_value = proc "c" (plugin: ^Clap_Plugin, param_id: Clap_Id, param_value_text: cstring, out_value: ^f64) -> bool {
        if len(Parameter) == 0 {
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
    flush = proc "c" (plugin: ^Clap_Plugin, input: ^Clap_Input_Events, output: ^Clap_Output_Events) {
        context = runtime.default_context()
        plugin := get_instance(plugin)
        event_count := input->size()
        parameters_sync_main_to_audio(plugin, output)
        for i in 0 ..< event_count {
            event_header := input->get(i)
            dispatch_parameter_event(plugin, event_header)
        }
    },
}