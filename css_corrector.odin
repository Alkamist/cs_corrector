package main

import ap "audio_plugin"

CSS_ID :: "com.alkamist.CssCorrector"
CSS_NAME :: "Css Corrector"
CSS_VENDOR :: "Alkamist Audio"
CSS_URL :: ""
CSS_MANUAL_URL :: ""
CSS_SUPPORT_URL :: ""
CSS_VERSION :: "0.1.0"
CSS_DESCRIPTION :: "A MIDI timing corrector for Cinematic Studio Strings."

Css_Corrector :: struct {
    using audio_plugin: ap.Audio_Plugin,
}

Css_Parameter :: enum {
    Legato_First_Note_Delay,
    Legato_Portamento_Delay,
    Legato_Slow_Delay,
    Legato_Medium_Delay,
    Legato_Fast_Delay,
}

css_on_init :: proc(plugin: ^Css_Corrector) {
}

css_on_destroy :: proc(plugin: ^Css_Corrector) {
}

css_on_activate :: proc(plugin: ^Css_Corrector) {
}

css_on_deactivate :: proc(plugin: ^Css_Corrector) {
}

css_on_reset :: proc(plugin: ^Css_Corrector) {
}

css_on_transport_event :: proc(plugin: ^Css_Corrector, event: ap.Transport_Event) {
}

make_param :: proc(id: Css_Parameter, name: string, default_value: f64) -> ap.Parameter_Info {
    return {int(id), name, -500.0, 500.0, default_value, {.Is_Automatable}, ""}
}

css_parameter_info := [len(Css_Parameter)]ap.Parameter_Info{
    make_param(.Legato_First_Note_Delay, "Legato First Note Delay", -60.0),
    make_param(.Legato_Portamento_Delay, "Legato Portamento Delay", -300.0),
    make_param(.Legato_Slow_Delay, "Legato Slow Delay", -300.0),
    make_param(.Legato_Medium_Delay, "Legato Medium Delay", -300.0),
    make_param(.Legato_Fast_Delay, "Legato Fast Delay", -150.0),
}

css_vtable := ap.Audio_Plugin_VTable{
    on_init = proc(plugin: ^ap.Audio_Plugin) {
        css_on_init(cast(^Css_Corrector)plugin)
    },
    on_destroy = proc(plugin: ^ap.Audio_Plugin) {
        css_on_destroy(cast(^Css_Corrector)plugin)
    },
    on_activate = proc(plugin: ^ap.Audio_Plugin) {
        css_on_activate(cast(^Css_Corrector)plugin)
    },
    on_deactivate = proc(plugin: ^ap.Audio_Plugin) {
        css_on_deactivate(cast(^Css_Corrector)plugin)
    },
    on_reset = proc(plugin: ^ap.Audio_Plugin) {
        css_on_reset(cast(^Css_Corrector)plugin)
    },
    on_transport_event = proc(plugin: ^ap.Audio_Plugin, event: ap.Transport_Event) {
        css_on_transport_event(cast(^Css_Corrector)plugin, event)
    },
}