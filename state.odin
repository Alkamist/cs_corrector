package main

import "core:mem"
import "core:sync"
import "core:runtime"
import "clap"

PRESET_VERSION :: 1

Plugin_Preset_V1 :: struct {
    version: int,
    parameters: [Parameter]f64,
}

get_preset :: proc(instance: ^Plugin_Instance) -> Plugin_Preset_V1 {
    preset := Plugin_Preset_V1{version = PRESET_VERSION}
    parameters_sync_audio_to_main(instance)
    sync.lock(&instance.parameter_mutex)
    for id in Parameter {
        preset.parameters[id] = instance.main_thread_parameter_value[id]
    }
    sync.unlock(&instance.parameter_mutex)
    return preset
}

load_preset :: proc(instance: ^Plugin_Instance, state: Plugin_Preset_V1) {
    sync.lock(&instance.parameter_mutex)
    for id in Parameter {
        instance.main_thread_parameter_value[id] = state.parameters[id]
        instance.main_thread_parameter_changed[id] = true
    }
    sync.unlock(&instance.parameter_mutex)
}

state_extension := clap.Plugin_State{
    save = proc "c" (plugin: ^clap.Plugin, stream: ^clap.O_Stream) -> bool {
        context = runtime.default_context()
        instance := get_instance(plugin)
        preset := get_preset(instance)

        write_ptr := &preset
        bytes_to_write := i64(size_of(preset))
        for {
            bytes_written := stream->write(write_ptr, u64(bytes_to_write))
            if bytes_written == bytes_to_write {
                // Success
                break
            }
            if bytes_written <= 0 || bytes_written > bytes_to_write {
                // Something went wrong
                return false
            }
            bytes_to_write -= bytes_written
            write_ptr = mem.ptr_offset(write_ptr, bytes_written)
        }

        return true
    },

    load = proc "c" (plugin: ^clap.Plugin, stream: ^clap.I_Stream) -> bool {
        context = runtime.default_context()

        data: [size_of(Plugin_Preset_V1)]byte

        read_ptr := &data
        bytes_to_read := i64(len(data))
        for {
            bytes_read := stream->read(read_ptr, u64(bytes_to_read))
            if bytes_read == bytes_to_read {
                // Success
                break
            }
            if bytes_read <= 0 || bytes_read > bytes_to_read {
                // Something went wrong
                return false
            }
            bytes_to_read -= bytes_read
            read_ptr = mem.ptr_offset(read_ptr, bytes_read)
        }

        preset := (^Plugin_Preset_V1)(&data)^
        instance := get_instance(plugin)
        load_preset(instance, preset)

        return true
    },
}