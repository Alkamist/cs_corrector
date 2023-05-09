package main

import "core:mem"
import "core:sync"
import "core:runtime"
import "core:strings"

clap_extension_state := Clap_Plugin_State{
    save = proc "c" (plugin: ^Clap_Plugin, stream: ^Clap_Ostream) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)

        parameters_sync_audio_to_main(plugin)

        builder := strings.builder_make_none()
        defer strings.builder_destroy(&builder)

        if save_preset(plugin, &builder) == false {
            return false
        }
        if len(builder.buf) == 0 {
            return false
        }

        write_ptr := &builder.buf[0]
        bytes_to_write := i64(len(builder.buf))
        for {
            bytes_written := stream.write(stream, write_ptr, u64(bytes_to_write))

            // Success
            if bytes_written == bytes_to_write {
                break
            }

            // An error happened
            if bytes_written <= 0 || bytes_written > bytes_to_write {
                return false
            }

            bytes_to_write -= bytes_written
            write_ptr = mem.ptr_offset(write_ptr, bytes_written)
        }

        return true
    },
    load = proc "c" (plugin: ^Clap_Plugin, stream: ^Clap_Istream) -> bool {
        context = runtime.default_context()
        plugin := get_instance(plugin)

        preset_data: [dynamic]byte
        defer delete(preset_data)

        for {
            data_byte: byte
            bytes_red := stream.read(stream, &data_byte, 1)

            // Hit the end of the stream
            if bytes_red == 0 {
                break
            }

            // Possibly more to read so keep going
            if bytes_red == 1 {
                append(&preset_data, data_byte)
                continue
            }

            // An error happened
            if bytes_red < 0 {
                return false
            }
        }

        sync.lock(&plugin.parameter_mutex)
        load_preset(plugin, preset_data[:])
        sync.unlock(&plugin.parameter_mutex)

        return true
    },
}