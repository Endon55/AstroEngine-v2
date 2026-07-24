package astro 

import "base:runtime"
import "core:log"
import "core:strings"


import "vendor:glfw"

glfw_error_callback::proc "c" (error:i32, description: cstring) {
    context = runtime.default_context()
    context.logger = g_logger
    log.errorf("GLFW [%d]: %s", error, description)
}

@(require_results)
create_window::proc(title: string, width, height: u32) ->(window: glfw.WindowHandle, ok: bool) {
    ensure(bool(glfw.Init()), "Failed to initialize GLFW")

    glfw.SetErrorCallback(glfw_error_callback)

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    c_title:= strings.clone_to_cstring(title, context.temp_allocator)


    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    window = glfw.CreateWindow(i32(width), i32(height), c_title, nil, nil)
    if window == nil {
        log.error("Failed to create window")
        return
    }
    return window, true
}

destroy_window::proc(window: glfw.WindowHandle) {
    glfw.DestroyWindow(window)
    glfw.Terminate()
}

callback_framebuffer_size::proc "c" (window:glfw.WindowHandle, width, height: i32) {

}

callback_window_minimize::proc "c" (window:glfw.WindowHandle, iconified: i32) {
    engine := cast(^Engine)glfw.GetWindowUserPointer(window)
    engine.stop_rendering = bool(iconified)
}
