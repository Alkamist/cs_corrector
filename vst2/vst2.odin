package vst2

AEffect :: struct {
    magic: i32,
    dispatcher: proc "c" (effect: ^AEffect, opcode: i32, index: i32, value: int, ptr: rawptr, opt: f32) -> int,
    process: proc "c" (effect: ^AEffect, inputs, outputs: [^][^]f32, sampleFrames: i32), // deprecated
    setParameter: proc "c" (effect: ^AEffect, index: i32, parameter: f32),
    getParameter: proc "c" (effect: ^AEffect, index: i32) -> f32,
    numPrograms: i32,
    numParams: i32,
    numInputs: i32,
    numOutputs: i32,
    flags: i32,
    resvd1: int,
    resvd2: int,
    initialDelay: i32,
    realQualities: i32, // deprecated
    offQualities: i32, // deprecated
    ioRatio: f32, // deprecated
    object: rawptr,
    user: rawptr,
    uniqueID: i32,
    version: i32,
    processReplacing: proc "c" (effect: ^AEffect, inputs, outputs: [^][^]f32, sampleFrames: i32),
    processDoubleReplacing: proc "c" (effect: ^AEffect, inputs, outputs: [^][^]f64, sampleFrames: i32),
    future: [56]byte,
}

// audioMasterCallback :: #type proc "c" (effect: ^AEffect, opcode: i32, index: i32, value: int, ptr: rawptr, opt: f32) -> int