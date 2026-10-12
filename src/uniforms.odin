package astro

import vk "vendor:vulkan"


/*

    3 Things

    Build the layout
    Build the descriptor
    Build the pipeline
    Possibly add an optional "bulk" construct that passes in many singular data pieces.


*/



Shader_Layout :: struct {
    vk_device: vk.Device,
}

pipeline :: struct {





}

shader_layout_init :: proc(self: ^Shader_Layout, device: vk.Device) -> (ok:bool) {
    self.vk_device = device



    return true

}







