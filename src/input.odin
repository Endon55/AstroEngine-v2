package astro

import la "core:math/linalg"
import "vendor:glfw"




Input :: struct {

    window_handle: glfw.WindowHandle,

    mouse_moved: bool,
    mouse_pos: la.Vector2f32,
    mouse_prev_pos: la.Vector2f32,
    mouse_delta: la.Vector2f32,
}

input_init :: proc(self: ^Input, window_handle: glfw.WindowHandle) {
    self.window_handle = window_handle
    input_update(self)
}

input_update :: proc(self: ^Input) {
    self.mouse_prev_pos = self.mouse_pos
    x, y := glfw.GetCursorPos(self.window_handle)
    self.mouse_pos.x = f32(x)
    self.mouse_pos.y = f32(y)
    self.mouse_moved = self.mouse_pos != self.mouse_prev_pos

    if self.mouse_moved {
        self.mouse_delta.x = self.mouse_pos.x - self.mouse_prev_pos.x
        self.mouse_delta.y = self.mouse_pos.y - self.mouse_prev_pos.y
    } else {
        self.mouse_delta.x = 0.0
        self.mouse_delta.y = 0.0
    }
    
}

