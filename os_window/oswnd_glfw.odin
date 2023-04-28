package main

// import "core:fmt"
// import "core:c"
// import gl "vendor:OpenGL"
// import "vendor:glfw"

// GL_MAJOR_VERSION :: 3
// GL_MINOR_VERSION :: 3

// glfw_is_initialized := false

// Os_Window :: struct {
// 	using state: Os_Window_State
// }

// create_os_window :: proc() {
// 	glfw.WindowHint(glfw.RESIZABLE, 1)
// 	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
// 	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
// 	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

// 	if !glfw_is_initialized {
// 		if glfw.Init() != 1 {
// 			fmt.println("Failed to initialize GLFW")
// 			return
// 		}
// 		glfw_is_initialized = true
// 	}

// }

// main :: proc() {
// 	glfw.WindowHint(glfw.RESIZABLE, 1)
// 	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
// 	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
// 	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

// 	if glfw.Init() != 1 {
// 		fmt.println("Failed to initialize GLFW")
// 		return
// 	}

// 	defer glfw.Terminate()

// 	window := glfw.CreateWindow(512, 512, "Test", nil, nil)
// 	defer glfw.DestroyWindow(window)

// 	if window == nil {
// 		fmt.println("Unable to create window")
// 		return
// 	}

// 	glfw.MakeContextCurrent(window)
// 	glfw.SwapInterval(1)
// 	glfw.SetKeyCallback(window, key_callback)
// 	glfw.SetFramebufferSizeCallback(window, size_callback)
// 	gl.load_up_to(int(GL_MAJOR_VERSION), GL_MINOR_VERSION, glfw.gl_set_proc_address)

// 	for !glfw.WindowShouldClose(window) && running {
// 		glfw.PollEvents()
// 		gl.ClearColor(0.2, 0.3, 0.3, 1.0)
// 		gl.Clear(gl.COLOR_BUFFER_BIT)
// 		glfw.SwapBuffers(window)
// 	}
// }

// key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
// 	if key == glfw.KEY_ESCAPE {
// 		running = false
// 	}
// }

// size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
// 	gl.Viewport(0, 0, width, height)
// }