package astro

import "core:log"
import vk "vendor:vulkan"
import spirv "libs:spirv-reflect" 

/*
    The basic gist of how descriptor sets and pipelines work is as follows.
    When you pass data to a shader it necessarily has a certain shape. A struct of 10 values,
    a single float, 1000 vertices. whatever. That shape is called a Layout. And a layout is given a number(think array index) which is called a Binding. 

    So if we had 10 pieces of data to Bind to a shader, each piece of data would be assigned a Binding(its index) and the layout of that individual piece of data.

    Sometimes those data pieces are images, and an image can be all sorts of sizes and formats, so instead when we create an image binding we're just binding a pointer to that image. So the shape of that data is the same as one pointer depending on 32/64 bit architecture.

    The bindings are already forming an array. We call that grouped array of bindings a Set. 
    A group of sets gets combined into a Pipeline Layout. This fully describes all the data that the pipeline needs.
    A Pipeline describles stages the shaders are going to go through. A compute shader has only one stage which simplifies the pipeline. But rendering pipelines have vertex, tessellation, geometry, and fragment shaders.

    IMPORTANT: Bindings are shared for each stage in the pipeline, and you must specify which stage pieces of data will be used for. So if we had set0,binding0 and stored a view matrix, 16 32bit floats or 64 bytes. We would have to specify that the Vertex shader wants that matrix. The fragment shader doesn't care at all about the view matrix but it does want some color data. It cannot try to bind that data to set0,binding0 because its already in use, if it does then it will recieve the view matrix but reinterprit those 64 bytes as some color data instead.
    So we should instead use set0,binding1 to store the color data.
*/
Shader_Pipeline_Builder :: struct {
    vk_device: vk.Device,
    shaders: Astro_Shaders,
    pipeline_layout: vk.PipelineLayout,
}

shader_pipeline_builder_init :: proc(self: ^Shader_Pipeline_Builder, device: vk.Device) -> (ok:bool) {
    self.vk_device = device
    alloc_size: vk.DeviceSize = 50;
    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = alloc_size,
        usage = {.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
    }

    allocation_info := vk.MemoryAllocateFlagsInfo {
        flags = {.DEVICE_ADDRESS_CAPTURE_REPLAY},
        pNext = &buffer_info
    }

    return true
}

shader_pipeline_builder_set_shaders :: proc(self: ^Shader_Pipeline_Builder, astro_shaders: Astro_Shaders, loc:=#caller_location){
    ok: bool


    switch shaders in astro_shaders {
    case Render_Shaders:
        self.pipeline_layout, ok = shaders_generate_layout_render(self.vk_device, shaders) 
    case Compute_Shaders:
        self.pipeline_layout, ok = shaders_generate_layout_compute(self.vk_device, shaders) 
    }

    if !ok {
        log.errorf("Could not generate the layout for Shaders, %v", loc)
        return
    }
}

