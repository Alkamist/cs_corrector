package main

// import "core:c"
import "core:time"
import "core:runtime"
import "core:strings"
import win32 "core:sys/windows"
import gl "vendor:OpenGL"

foreign import user32 "system:User32.lib"

LOBYTE :: #force_inline proc "contextless" (#any_int w: int) -> win32.BYTE {
    return cast(win32.BYTE)(cast(win32.DWORD_PTR)(w)) & 0xff
}

@(default_calling_convention="stdcall")
foreign user32 {
    GetDesktopWindow :: proc() -> win32.HWND ---
    SetParent :: proc(hWndChild, hWndNewParent: win32.HWND) ---
}

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3

window_count := 0
window_class_name := win32.utf8_to_utf16("Odin_Os_Window")

Os_Window :: struct {
    using state: Os_Window_State,
    on_frame: proc(window: ^Os_Window),
    handle: win32.HWND,
    hdc: win32.HDC,
    hglrc: win32.HGLRC,
}

create :: proc(parent_handle: win32.HWND = nil) -> ^Os_Window {
    window := new(Os_Window)
    _init_state(window, time.tick_now())

    hinstance := cast(win32.HINSTANCE)win32.GetModuleHandleW(nil)

    if window_count == 0 {
        window_class := win32.WNDCLASSEXW{
            cbSize = size_of(win32.WNDCLASSEXW),
            style = win32.CS_OWNDC,
            lpfnWndProc = _window_proc,
            hInstance = hinstance,
            lpszClassName = &window_class_name[0],
        }
        win32.RegisterClassExW(&window_class)
    }

    window_style := win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE
    if parent_handle != nil {
        window._child_status = .Floating
        window_style |= win32.WS_POPUP
    }

    window.handle = win32.CreateWindowExW(
        0,
        &window_class_name[0],
        nil,
        window_style,
        0, 0, 800, 600,
        GetDesktopWindow(),
        nil,
        hinstance,
        nil,
    )

    update_bounds(window)
    _init_opengl_context(window)

    window_count += 1
    return window
}

poll :: proc(window: ^Os_Window) {
    if window._child_status == .None {
        msg: win32.MSG
        for win32.PeekMessageW(&msg, window.handle, 0, 0, win32.PM_REMOVE) != win32.FALSE {
            win32.TranslateMessage(&msg)
            win32.DispatchMessageW(&msg)
        }
    }
    _process_frame(window)
}

swap_buffers :: proc(window: ^Os_Window) {
    win32.SwapBuffers(window.hdc)
}

make_context_current :: proc(window: ^Os_Window) {
    win32.wglMakeCurrent(window.hdc, window.hglrc)
}

update_bounds :: proc(window: ^Os_Window) {
    rect: win32.RECT
    win32.GetClientRect(window.handle, &rect)
    win32.ClientToScreen(window.handle, cast(^win32.POINT)&rect.left)
    win32.ClientToScreen(window.handle, cast(^win32.POINT)&rect.right)
    window._x_pixels = int(rect.left)
    window._y_pixels = int(rect.top)
    window._width_pixels = int(rect.right - rect.left)
    window._height_pixels = int(rect.bottom - rect.top)
}

set_mouse_cursor_style :: proc(window: ^Os_Window, style: Mouse_Cursor_Style) {
    win32.SetCursor(win32.LoadCursorA(nil, _to_win32_mouse_cursor_style(style)))
}

set_position :: proc(window: ^Os_Window, x, y: int) {
    win32.SetWindowPos(
        window.handle, nil,
        i32(x), i32(y),
        0, 0,
        win32.SWP_NOACTIVATE | win32.SWP_NOZORDER | win32.SWP_NOSIZE,
    )
}

set_size :: proc(window: ^Os_Window, width, height: int) {
    win32.SetWindowPos(
        window.handle, nil,
        0, 0,
        i32(width), i32(height),
        win32.SWP_NOACTIVATE | win32.SWP_NOOWNERZORDER | win32.SWP_NOMOVE | win32.SWP_NOZORDER,
    )
}

set_decorated :: proc(window: ^Os_Window, decorated: bool) {
    window._is_decorated = decorated
}

embed_inside_window :: proc(window: ^Os_Window, parent: win32.HWND) {
    if window._child_status != .Embedded {
        win32.SetWindowLongPtrW(window.handle, win32.GWL_STYLE, int(win32.WS_CHILDWINDOW | win32.WS_CLIPSIBLINGS))
        window._child_status = .Embedded
        set_decorated(window, false)
        win32.SetWindowPos(
            window.handle,
            win32.HWND_TOPMOST,
            i32(window._x_pixels), i32(window._y_pixels),
            i32(window._width_pixels), i32(window._height_pixels),
            win32.SWP_SHOWWINDOW,
        )
    }
    SetParent(window.handle, parent)
}

show :: proc(window: ^Os_Window) {
    win32.ShowWindow(window.handle, win32.SW_SHOW)
}

hide :: proc(window: ^Os_Window) {
    win32.ShowWindow(window.handle, win32.SW_HIDE)
}

close :: proc(window: ^Os_Window) {
    if window._is_open {
        window._is_open = false
        win32.DestroyWindow(window.handle)
    }
}

_process_frame :: proc(window: ^Os_Window) {
    if window._is_open {
        if window.on_frame != nil {
            window.on_frame(window)
        }
        _update_state(window, time.tick_now())
    }
}

_init_opengl_context :: proc(window: ^Os_Window) {
    pfd := win32.PIXELFORMATDESCRIPTOR{
        nSize = size_of(win32.PIXELFORMATDESCRIPTOR),
        nVersion = 1,
        dwFlags = win32.PFD_DRAW_TO_WINDOW | win32.PFD_SUPPORT_OPENGL | win32.PFD_SUPPORT_COMPOSITION | win32.PFD_DOUBLEBUFFER,
        iPixelType = win32.PFD_TYPE_RGBA,
        cColorBits = 32,
        cRedBits = 0,
        cRedShift = 0,
        cGreenBits = 0,
        cGreenShift = 0,
        cBlueBits = 0,
        cBlueShift = 0,
        cAlphaBits = 0,
        cAlphaShift = 0,
        cAccumBits = 0,
        cAccumRedBits = 0,
        cAccumGreenBits = 0,
        cAccumBlueBits = 0,
        cAccumAlphaBits = 0,
        cDepthBits = 32,
        cStencilBits = 8,
        cAuxBuffers = 0,
        iLayerType = win32.PFD_MAIN_PLANE,
        bReserved = 0,
        dwLayerMask = 0,
        dwVisibleMask = 0,
        dwDamageMask = 0,
    }

    window.hdc = win32.GetDC(window.handle)
    pixel_format := win32.ChoosePixelFormat(window.hdc, &pfd)

    win32.SetPixelFormat(window.hdc, pixel_format, &pfd)

    window.hglrc = win32.wglCreateContext(window.hdc)
    win32.wglMakeCurrent(window.hdc, window.hglrc)

    gl.load_up_to(int(GL_MAJOR_VERSION), GL_MINOR_VERSION, _gl_set_proc_address)
    // current_texture: GLint
    // glGetIntegerv(GL_TEXTURE_BINDING_2D, currentTexture.addr)

    win32.ReleaseDC(window.handle, window.hdc)
}

_gl_set_proc_address :: proc(p: rawptr, name: cstring) {
    wgl_proc := win32.wglGetProcAddress(name)
    if wgl_proc != nil {
        (^rawptr)(p)^ = wgl_proc
    } else {
        hmodule := win32.LoadLibraryW(&win32.utf8_to_utf16("opengl32.dll")[0])
        (^rawptr)(p)^ = win32.GetProcAddress(hmodule, name)
    }
}

_window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
    context = runtime.default_context()

    if msg == win32.WM_CREATE {
        lpcs := transmute(^win32.CREATESTRUCTW)lparam
        win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, transmute(win32.LONG_PTR)lpcs.lpCreateParams)
    }

    window := transmute(^Os_Window)win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA)
    if window == nil || hwnd != window.handle {
        return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
    }

    switch msg {

    case win32.WM_MOVE:
        update_bounds(window)
        _process_frame(window)

    case win32.WM_SIZE:
        update_bounds(window)
        _process_frame(window)

    case win32.WM_CLOSE:
        close(window)

    case win32.WM_DESTROY:
        _destroy_state(window)
        if window_count > 0 {
            window_count -= 1
            if window_count == 0 {
                win32.UnregisterClassW(&window_class_name[0], nil)
            }
        }

    case win32.WM_DPICHANGED:
        window._pixel_density = f64(win32.GetDpiForWindow(window.handle)) / DENSITY_PIXEL_DPI
        update_bounds(window)

    case win32.WM_MOUSEMOVE:
        if !window._is_hovered {
            tme: win32.TRACKMOUSEEVENT
            tme.cbSize = size_of(tme)
            tme.dwFlags = win32.TME_LEAVE
            tme.hwndTrack = window.handle
            win32.TrackMouseEvent(&tme)
            window._is_hovered = true
        }
        window._mouse_x_pixels = int(win32.GET_X_LPARAM(lparam))
        window._mouse_y_pixels = int(win32.GET_Y_LPARAM(lparam))
        _process_frame(window)

    case win32.WM_MOUSELEAVE:
        window._is_hovered = false

    case win32.WM_MOUSEWHEEL:
        window._mouse_wheel_y += f64(win32.GET_WHEEL_DELTA_WPARAM(wparam)) / win32.WHEEL_DELTA
        _process_frame(window)

    case win32.WM_MOUSEHWHEEL:
        window._mouse_wheel_x += f64(win32.GET_WHEEL_DELTA_WPARAM(wparam)) / win32.WHEEL_DELTA
        _process_frame(window)

    case win32.WM_LBUTTONDOWN, win32.WM_LBUTTONDBLCLK,
         win32.WM_MBUTTONDOWN, win32.WM_MBUTTONDBLCLK,
         win32.WM_RBUTTONDOWN, win32.WM_RBUTTONDBLCLK,
         win32.WM_XBUTTONDOWN, win32.WM_XBUTTONDBLCLK:
        win32.SetCapture(window.handle)
        button := _to_mouse_button(msg, wparam)
        append(&window._mouse_presses, button)
        window._mouse_down_states[button] = true

    case win32.WM_LBUTTONUP, win32.WM_MBUTTONUP, win32.WM_RBUTTONUP, win32.WM_XBUTTONUP:
        win32.ReleaseCapture()
        button := _to_mouse_button(msg, wparam)
        append(&window._mouse_releases, button)
        window._mouse_down_states[button] = false

    case win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN:
        key := _to_keyboard_key(wparam, lparam)
        append(&window._key_presses, key)
        window._key_down_states[key] = true

    case win32.WM_KEYUP, win32.WM_SYSKEYUP:
        key := _to_keyboard_key(wparam, lparam)
        append(&window._key_releases, key)
        window._key_down_states[key] = false

    case win32.WM_CHAR, win32.WM_SYSCHAR:
        if wparam > 0 && wparam < 0x10000 {
            strings.write_rune(&window._text_input, cast(rune)wparam)
        }

    case win32.WM_NCCALCSIZE:
        if !window._is_decorated {
            return 0
        }
    }

    return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

_to_win32_mouse_cursor_style :: proc(style: Mouse_Cursor_Style) -> win32.LPCSTR {
    switch style {
    case .Arrow: return win32.IDC_ARROW
    case .I_Beam: return win32.IDC_IBEAM
    case .Crosshair: return win32.IDC_CROSS
    case .Pointing_Hand: return win32.IDC_HAND
    case .Resize_Left_Right: return win32.IDC_SIZEWE
    case .Resize_Top_Bottom: return win32.IDC_SIZENS
    case .Resize_Top_Left_Bottom_Right: return win32.IDC_SIZENWSE
    case .Resize_Top_Right_Bottom_Left: return win32.IDC_SIZENESW
    }
    return nil
}

_to_mouse_button :: proc(msg: win32.UINT, wparam: win32.WPARAM) -> Mouse_Button {
    switch msg {
    case win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP, win32.WM_LBUTTONDBLCLK:
        return .Left
    case win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP, win32.WM_MBUTTONDBLCLK:
        return .Middle
    case win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP, win32.WM_RBUTTONDBLCLK:
        return .Right
    case win32.WM_XBUTTONDOWN, win32.WM_XBUTTONUP, win32.WM_XBUTTONDBLCLK:
        if win32.HIWORD(cast(win32.DWORD)wparam) == 1 {
            return .Extra_1
        } else {
            return .Extra_2
        }
    }
    return .Unknown
}

_to_keyboard_key :: proc(wparam: win32.WPARAM, lparam: win32.LPARAM) -> Keyboard_Key {
    scan_code := LOBYTE(win32.HIWORD(cast(win32.DWORD)lparam))
    is_right := (win32.HIWORD(cast(win32.DWORD)lparam) & win32.KF_EXTENDED) == win32.KF_EXTENDED
    switch scan_code {
    case 42: return .Left_Shift
    case 54: return .Right_Shift
    case 29:
        if is_right {
            return .Right_Control
        } else {
            return .Left_Control
        }
    case 56:
        if is_right {
            return .Right_Alt
        } else {
            return .Left_Alt
        }
    case:
        switch wparam {
        case 8: return .Backspace
        case 9: return .Tab
        case 13: return .Enter
        case 19: return .Pause
        case 20: return .Caps_Lock
        case 27: return .Escape
        case 32: return .Space
        case 33: return .Page_Up
        case 34: return .Page_Down
        case 35: return .End
        case 36: return .Home
        case 37: return .Left_Arrow
        case 38: return .Up_Arrow
        case 39: return .Right_Arrow
        case 40: return .Down_Arrow
        case 45: return .Insert
        case 46: return .Delete
        case 48: return .Key_0
        case 49: return .Key_1
        case 50: return .Key_2
        case 51: return .Key_3
        case 52: return .Key_4
        case 53: return .Key_5
        case 54: return .Key_6
        case 55: return .Key_7
        case 56: return .Key_8
        case 57: return .Key_9
        case 65: return .A
        case 66: return .B
        case 67: return .C
        case 68: return .D
        case 69: return .E
        case 70: return .F
        case 71: return .G
        case 72: return .H
        case 73: return .I
        case 74: return .J
        case 75: return .K
        case 76: return .L
        case 77: return .M
        case 78: return .N
        case 79: return .O
        case 80: return .P
        case 81: return .Q
        case 82: return .R
        case 83: return .S
        case 84: return .T
        case 85: return .U
        case 86: return .V
        case 87: return .W
        case 88: return .X
        case 89: return .Y
        case 90: return .Z
        case 91: return .Left_Meta
        case 92: return .Right_Meta
        case 96: return .Pad_0
        case 97: return .Pad_1
        case 98: return .Pad_2
        case 99: return .Pad_3
        case 100: return .Pad_4
        case 101: return .Pad_5
        case 102: return .Pad_6
        case 103: return .Pad_7
        case 104: return .Pad_8
        case 105: return .Pad_9
        case 106: return .Pad_Multiply
        case 107: return .Pad_Add
        case 109: return .Pad_Subtract
        case 110: return .Pad_Period
        case 111: return .Pad_Divide
        case 112: return .F1
        case 113: return .F2
        case 114: return .F3
        case 115: return .F4
        case 116: return .F5
        case 117: return .F6
        case 118: return .F7
        case 119: return .F8
        case 120: return .F9
        case 121: return .F10
        case 122: return .F11
        case 123: return .F12
        case 144: return .Num_Lock
        case 145: return .Scroll_Lock
        case 186: return .Semicolon
        case 187: return .Equal
        case 188: return .Comma
        case 189: return .Minus
        case 190: return .Period
        case 191: return .Slash
        case 192: return .Backtick
        case 219: return .Left_Bracket
        case 220: return .Backslash
        case 221: return .Right_Bracket
        case 222: return .Quote
        case: return .Unknown
        }
    }
}