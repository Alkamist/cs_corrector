package main

import ap "audio_plugin"

main :: proc() {
    css_dispatcher := ap.export_plugin(
        id = CSS_ID,
        name = CSS_NAME,
        vendor = CSS_VENDOR,
        url = CSS_URL,
        manual_url = CSS_MANUAL_URL,
        support_url = CSS_SUPPORT_URL,
        version = CSS_VERSION,
        description = CSS_DESCRIPTION,
        parameter_info = css_parameter_info[:],
        vtable = &css_vtable,
    )
}