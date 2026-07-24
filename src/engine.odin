package astro

import "core:log"

import "vendor:glfw"
import vk "vendor:vulkan"


TITLE :: "Astro Engine v2"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678}

Engine::struct {
    window: glfw.WindowHandle,
    window_extent: vk.Extent2D,
    is_initialized: bool,
    stop_rendering: bool,
}

@(private)
g_logger: log.Logger

@(require_results)
engine_init :: proc(self: ^Engine) -> (ok: bool) {
    ensure(self != nil, "Invalid 'Engine' object")
    g_logger = context.logger

    self.window_extent = DEFAULT_WINDOW_EXTENT

    self.window = create_window(
        TITLE,
        self.window_extent.width,
        self.window_extent.height,
    ) or_return
    defer if !ok{
        destroy_window(self.window)
    }

    glfw.SetWindowUserPointer(self.window, self)

    glfw.SetFramebufferSizeCallback(self.window, callback_framebuffer_size)
    glfw.SetWindowIconifyCallback(self.window, callback_window_minimize)

    self.is_initialized = true

    return true

}

engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }
    destroy_window(self.window)
}

@(require_results)
engine_draw ::proc(self: ^Engine) -> (ok: bool){
    return true
}

@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
    log.info("Entering main loop...")
    loop: for !glfw.WindowShouldClose(self.window) {
        glfw.PollEvents()

        if self.stop_rendering {
            glfw.WaitEvents()
            continue
        }

        engine_draw(self) or_return

    }

    log.info("Exiting...")
    return true
}
