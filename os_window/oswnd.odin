package main

import "core:slice"
import "core:strings"
import "core:time"

DENSITY_PIXEL_DPI :: 96.0

Child_Status :: enum {
    None,
    Embedded,
    Floating,
}

Mouse_Cursor_Style :: enum {
    Arrow,
    I_Beam,
    Crosshair,
    Pointing_Hand,
    Resize_Left_Right,
    Resize_Top_Bottom,
    Resize_Top_Left_Bottom_Right,
    Resize_Top_Right_Bottom_Left,
}

Mouse_Button :: enum {
    Unknown,
    Left, Middle, Right,
    Extra_1, Extra_2, Extra_3,
    Extra_4, Extra_5,
}

Keyboard_Key :: enum {
    Unknown,
    A, B, C, D, E, F, G, H, I,
    J, K, L, M, N, O, P, Q, R,
    S, T, U, V, W, X, Y, Z,
    Key_1, Key_2, Key_3, Key_4, Key_5,
    Key_6, Key_7, Key_8, Key_9, Key_0,
    Pad_1, Pad_2, Pad_3, Pad_4, Pad_5,
    Pad_6, Pad_7, Pad_8, Pad_9, Pad_0,
    F1, F2, F3, F4, F5, F6, F7,
    F8, F9, F10, F11, F12,
    Backtick, Minus, Equal, Backspace,
    Tab, Caps_Lock, Enter, Left_Shift,
    Right_Shift, Left_Control, Right_Control,
    Left_Alt, Right_Alt, Left_Meta, Right_Meta,
    Left_Bracket, Right_Bracket, Space,
    Escape, Backslash, Semicolon, Quote,
    Comma, Period, Slash, Scroll_Lock,
    Pause, Insert, End, Page_Up, Delete,
    Home, Page_Down, Left_Arrow, Right_Arrow,
    Down_Arrow, Up_Arrow, Num_Lock, Pad_Divide,
    Pad_Multiply, Pad_Subtract, Pad_Add, Pad_Enter,
    Pad_Period, Print_Screen,
}

Os_Window_State :: struct {
    _child_status: Child_Status,
	_is_open: bool,
	_is_decorated: bool,
	_is_hovered: bool,
	_x_pixels: int,
	_y_pixels: int,
	_width_pixels: int,
	_height_pixels: int,
	_tick: time.Tick,
	_pixel_density: f64,
	_mouse_x_pixels: int,
	_mouse_y_pixels: int,
	_mouse_wheel_x: f64,
	_mouse_wheel_y: f64,
	_mouse_presses: [dynamic]Mouse_Button,
	_mouse_releases: [dynamic]Mouse_Button,
	_mouse_down_states: [Mouse_Button]bool,
	_key_presses: [dynamic]Keyboard_Key,
	_key_releases: [dynamic]Keyboard_Key,
	_key_down_states: [Keyboard_Key]bool,
	_text_input: strings.Builder,

    _is_hovered_previous: bool,
    _x_pixels_previous: int,
	_y_pixels_previous: int,
    _width_pixels_previous: int,
	_height_pixels_previous: int,
    _tick_previous: time.Tick,
    _pixel_density_previous: f64,
    _mouse_x_pixels_previous: int,
	_mouse_y_pixels_previous: int,
}

child_status :: proc(window: ^Os_Window_State) -> Child_Status { return window._child_status }
is_open :: proc(window: ^Os_Window_State) -> bool { return window._is_open }
is_decorated :: proc(window: ^Os_Window_State) -> bool { return window._is_decorated }
is_hovered :: proc(window: ^Os_Window_State) -> bool { return window._is_hovered }

just_moved :: proc(window: ^Os_Window_State) -> bool { return window._x_pixels != window._x_pixels_previous || window._y_pixels != window._y_pixels_previous }
x :: proc(window: ^Os_Window_State) -> f64 { return f64(window._x_pixels) / window._pixel_density }
delta_x :: proc(window: ^Os_Window_State) -> f64 { return f64(window._x_pixels - window._x_pixels_previous) / window._pixel_density }
x_pixels :: proc(window: ^Os_Window_State) -> int { return window._x_pixels }
delta_x_pixels :: proc(window: ^Os_Window_State) -> int { return window._x_pixels - window._x_pixels_previous }
y :: proc(window: ^Os_Window_State) -> f64 { return f64(window._y_pixels) / window._pixel_density }
delta_y :: proc(window: ^Os_Window_State) -> f64 { return f64(window._y_pixels - window._y_pixels_previous) / window._pixel_density }
y_pixels :: proc(window: ^Os_Window_State) -> int { return window._y_pixels }
delta_y_pixels :: proc(window: ^Os_Window_State) -> int { return window._y_pixels - window._y_pixels_previous }

just_resized :: proc(window: ^Os_Window_State) -> bool { return window._width_pixels != window._width_pixels_previous || window._height_pixels != window._height_pixels_previous }
width :: proc(window: ^Os_Window_State) -> f64 { return f64(window._width_pixels) / window._pixel_density }
delta_width :: proc(window: ^Os_Window_State) -> f64 { return f64(window._width_pixels - window._width_pixels_previous) / window._pixel_density }
width_pixels :: proc(window: ^Os_Window_State) -> int { return window._width_pixels }
delta_width_pixels :: proc(window: ^Os_Window_State) -> int { return window._width_pixels - window._width_pixels_previous }
height :: proc(window: ^Os_Window_State) -> f64 { return f64(window._height_pixels) / window._pixel_density }
delta_height :: proc(window: ^Os_Window_State) -> f64 { return f64(window._height_pixels - window._height_pixels_previous) / window._pixel_density }
height_pixels :: proc(window: ^Os_Window_State) -> int { return window._height_pixels }
delta_height_pixels :: proc(window: ^Os_Window_State) -> int { return window._height_pixels - window._height_pixels_previous }

mouse_just_moved :: proc(window: ^Os_Window_State) -> bool { return window._mouse_x_pixels != window._mouse_x_pixels_previous || window._mouse_y_pixels != window._mouse_y_pixels_previous }
mouse_x :: proc(window: ^Os_Window_State) -> f64 { return f64(window._mouse_x_pixels) / window._pixel_density }
delta_mouse_x :: proc(window: ^Os_Window_State) -> f64 { return f64(window._mouse_x_pixels - window._mouse_x_pixels_previous) / window._pixel_density }
mouse_x_pixels :: proc(window: ^Os_Window_State) -> int { return window._mouse_x_pixels }
delta_mouse_x_pixels :: proc(window: ^Os_Window_State) -> int { return window._mouse_x_pixels - window._mouse_x_pixels_previous }
mouse_y :: proc(window: ^Os_Window_State) -> f64 { return f64(window._mouse_y_pixels) / window._pixel_density }
delta_mouse_y :: proc(window: ^Os_Window_State) -> f64 { return f64(window._mouse_y_pixels - window._mouse_y_pixels_previous) / window._pixel_density }
mouse_y_pixels :: proc(window: ^Os_Window_State) -> int { return window._mouse_y_pixels }
delta_mouse_y_pixels :: proc(window: ^Os_Window_State) -> int { return window._mouse_y_pixels - window._mouse_y_pixels_previous }

mouse_wheel_just_moved :: proc(window: ^Os_Window_State) -> bool { return window._mouse_wheel_x != 0.0 || window._mouse_wheel_y != 0.0 }
mouse_is_down :: proc(window: ^Os_Window_State, button: Mouse_Button) -> bool { return window._mouse_down_states[button] }
mouse_just_pressed :: proc(window: ^Os_Window_State, button: Mouse_Button) -> bool { return slice.contains(window._mouse_presses[:], button) }
mouse_just_released :: proc(window: ^Os_Window_State, button: Mouse_Button) -> bool { return slice.contains(window._mouse_releases[:], button) }
any_mouse_just_pressed :: proc(window: ^Os_Window_State) -> bool { return len(window._mouse_presses) > 0 }
any_mouse_just_released :: proc(window: ^Os_Window_State) -> bool { return len(window._mouse_releases) > 0 }
key_is_down :: proc(window: ^Os_Window_State, key: Keyboard_Key) -> bool { return window._key_down_states[key] }
key_just_pressed :: proc(window: ^Os_Window_State, key: Keyboard_Key) -> bool { return slice.contains(window._key_presses[:], key) }
key_just_released :: proc(window: ^Os_Window_State, key: Keyboard_Key) -> bool { return slice.contains(window._key_releases[:], key) }
any_key_just_pressed :: proc(window: ^Os_Window_State) -> bool { return len(window._key_presses) > 0 }
any_key_just_released :: proc(window: ^Os_Window_State) -> bool { return len(window._key_releases) > 0 }

mouse_just_entered :: proc(window: ^Os_Window_State) -> bool { return window._is_hovered && !window._is_hovered_previous }
mouse_just_exited :: proc(window: ^Os_Window_State) -> bool { return window._is_hovered_previous && !window._is_hovered }

delta_time :: proc(window: ^Os_Window_State) -> f64 { return time.duration_seconds(time.tick_diff(window._tick, window._tick_previous)) }

aspect_ratio :: proc(window: ^Os_Window_State) -> f64 { return f64(window._width_pixels) / f64(window._height_pixels) }
scale :: proc(window: ^Os_Window_State) -> f64 { return 1.0 / window._pixel_density }
pixel_density_changed :: proc(window: ^Os_Window_State) -> bool { return window._pixel_density != window._pixel_density_previous }

_init_state :: proc(window: ^Os_Window_State, tick: time.Tick) {
    window._tick = tick
	window._tick_previous = tick
	window._pixel_density = 1.0
	window._pixel_density_previous = 1.0
}

_update_state :: proc(window: ^Os_Window_State, tick: time.Tick) {
    window._is_hovered_previous = window._is_hovered
    window._x_pixels_previous = window._x_pixels
    window._y_pixels_previous = window._y_pixels
    window._width_pixels_previous = window._width_pixels
    window._height_pixels_previous = window._height_pixels
    window._tick_previous = window._tick
    window._pixel_density_previous = window._pixel_density
    window._mouse_x_pixels_previous = window._mouse_x_pixels
    window._mouse_y_pixels_previous = window._mouse_y_pixels
    window._mouse_wheel_x = 0.0
    window._mouse_wheel_y = 0.0
    strings.builder_reset(&window._text_input)
    delete(window._mouse_presses)
    delete(window._mouse_releases)
    delete(window._key_presses)
    delete(window._key_releases)

    window._tick = tick
}

_destroy_state :: proc(window: ^Os_Window_State) {
    delete(window._mouse_presses)
    delete(window._mouse_releases)
    delete(window._key_presses)
    delete(window._key_releases)
    strings.builder_destroy(&window._text_input)
}