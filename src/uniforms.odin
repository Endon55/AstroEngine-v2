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


Shader_Pipeline :: struct {
    vk_device: vk.Device,
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    bind_point: vk.PipelineBindPoint,
    uniform_bindings: [dynamic]Uniform_Binding,
    texture_bindings: [dynamic]Texture_Binding,
}
Uniform_Binding :: struct {
    binding: u32,
    set: u32,
    mem_reference: Memory_Reference,
}
Texture_Binding :: struct {
    binding: u32,
    set: u32,
    reference: Texture_Reference,
}





shader_pipeline_bind :: proc(self: ^Shader_Pipeline, cmd: vk.CommandBuffer) {

    vk.CmdBindPipeline(cmd, self.bind_point, self.pipeline)
    // vk.CmdBindDescriptorSets(
    //     cmd,
    //     .COMPUTE,
    //     ocean_sim.jonswap_layout.handle,
    //     0,
    //     1,
    //     &ocean_sim.jonswap_descriptor,
    //     0,
    //     nil,
    // )
    // vk.CmdPushConstants(
    //     cmd,
    //     ocean_sim.jonswap_layout.handle,
    //     {.COMPUTE},
    //     0,
    //     size_of(Spectrum_Parameters),
    //     &ocean_sim.spectrum_params,
    // )

}

Shader_Pipeline_Builder :: struct {
    vk_device: vk.Device,
    shaders: Astro_Shaders,
    reflect_layout: Reflected_Shaders,
    shader_pipeline: Shader_Pipeline,
    memory_manager: ^Memory_Manager,
}

shader_pipeline_builder_init :: proc(self: ^Shader_Pipeline_Builder, memory_manager:^Memory_Manager, device: vk.Device) -> (ok:bool) {
    self.vk_device = device
    self.memory_manager = memory_manager
    self.shader_pipeline.uniform_bindings = make([dynamic]Uniform_Binding)

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
    self.shaders = astro_shaders
    switch shaders in astro_shaders {
    case Render_Shaders:
        self.reflect_layout, ok = shaders_generate_raw_layout_render(self.vk_device, shaders) 
    case Compute_Shaders:
        self.reflect_layout, ok = shaders_generate_raw_layout_compute(self.vk_device, shaders) 
    }

    if !ok {
        log.errorf("Could not generate the layout for Shaders, %v", loc)
        return
    }
}

shader_pipeline_builder_bind_uniform_ptr :: proc(self: ^Shader_Pipeline_Builder, data: ^^$T, set:u32, binding: u32) {
    uniform_binding: Uniform_Binding
    uniform_binding.set = set
    uniform_binding.binding = binding
    uniform_binding.mem_reference = memory_manager_bind_uniform(self.memory_manager, size_of(T))

    assert(uniform_binding.mem_reference.pointer != nil, "Got a bad pointer for the uniform")
    append(&self.shader_pipeline.uniform_bindings, uniform_binding)

    data^ = cast(^T)uniform_binding.mem_reference.pointer
}

shader_pipeline_builder_bind_image :: proc{
    shader_pipeline_builder_bind_image_existing,
    shader_pipeline_builder_bind_image_new,
}
shader_pipeline_builder_bind_image_existing :: proc(self: ^Shader_Pipeline_Builder, texture_reference: Texture_Reference, set:u32, binding:u32) {

    texture_binding: Texture_Binding

    texture_binding.reference = texture_reference 
    texture_binding.set = set
    texture_binding.binding = binding

    append(&self.shader_pipeline.texture_bindings, texture_binding)
}

shader_pipeline_builder_bind_image_new :: proc(self: ^Shader_Pipeline_Builder, image_info:vk.ImageCreateInfo, set:u32, binding: u32) -> Texture_Reference{

    texture_binding: Texture_Binding
    ref, ok := create_texture_info(self.memory_manager, image_info) 
    if !ok {
        log.errorf("Failed to create texture with image info")
        return ref
    }
    texture_binding.reference = ref
    texture_binding.set = set
    texture_binding.binding = binding

    append(&self.shader_pipeline.texture_bindings, texture_binding)
    return texture_binding.reference
}


shader_pipeline_builder_build :: proc(self: ^Shader_Pipeline_Builder) ->(shader_pipeline:Shader_Pipeline, ok:bool) {

    shader_pipeline = self.shader_pipeline
    defer delete_reflected_shaders(&self.reflect_layout)

    shader_pipeline.pipeline_layout = generate_vk_layout(self.vk_device, &self.reflect_layout) or_return

    switch &shaders in self.shaders {
    case Compute_Shaders:
        module:= shader_get_module(self.vk_device, &shaders.compute) or_return
        pipeline_create_info := vk.ComputePipelineCreateInfo {
            sType = .COMPUTE_PIPELINE_CREATE_INFO,
            layout = shader_pipeline.pipeline_layout,
            stage = pipeline_shader_stage_create_info({.COMPUTE}, module, "main"),
        }
        shader_pipeline.bind_point = .COMPUTE
        vk_check(vk.CreateComputePipelines(self.vk_device, 0, 1, &pipeline_create_info, nil, &shader_pipeline.pipeline), "Failed to create compute pipeline") or_return
    
    case Render_Shaders:

    }


    return shader_pipeline, true
}
