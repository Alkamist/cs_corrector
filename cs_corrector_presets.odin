package main

Cs_Corrector_Preset_V1 :: struct {
    size: i64le,
    preset_version: i64le,
    parameter_offset: i64le,
    parameter_count: i64le,
    parameters: [Parameter]f64le,
}