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

Shader_Resource :: union {
    Uniform_Binding,
    Texture_Binding,
    Buffer_Binding,
}

Shader_Pipeline :: struct {
    vk_device: vk.Device,
    pipeline_layout: Pipeline_Layout2,
    pipeline: vk.Pipeline,
    bind_point: vk.PipelineBindPoint,
    resources: [dynamic]Shader_Resource,
    binding_parameters: Binding_Parameters,
}

Binding_Parameters :: struct {
    buffer_infos: []vk.DescriptorBufferBindingInfoEXT,
    set_buffer_indices: []u32,
    set_buffer_offsets: []vk.DeviceSize,
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

Buffer_Binding :: struct {
    binding: u32,
    set: u32,
    reference: Allocated_Buffer
}

/*
    1. Bind Pipeline.
*/

shader_pipeline_bind :: proc(self: ^Shader_Pipeline, cmd: vk.CommandBuffer) {

    //1. Bind Pipeline
    vk.CmdBindPipeline(cmd, self.bind_point, self.pipeline) 
    //2. Bind All buffers used by this pipeline must always include the default descriptor buffer
    vk.CmdBindDescriptorBuffersEXT(cmd, u32(len(self.binding_parameters.buffer_infos)), raw_data(self.binding_parameters.buffer_infos))

    //3. Set for each set I need to specify where the descriptor lives (buffer index from Step 2, offset into that buffer)
    vk.CmdSetDescriptorBufferOffsetsEXT(cmd, self.bind_point, self.pipeline_layout.vk_layout, 0, self.pipeline_layout.sets, raw_data(self.binding_parameters.set_buffer_indices), raw_data(self.binding_parameters.set_buffer_offsets))
    //4. Dispatch
    //vk.CmdDispatch(cmd, 64, 64, 1)

    //
    // for uniform in self.uniform_bindings {
    //
    //    //bind each uniform with its descriptor offset 
    // }
    //
    //
    // vk.CmdBindDescriptorBuffersEXT(
    //     cmd,
    //     .COMPUTE,
    //     self.pipeline_layout,
    //     0,
    //     1,
    //     self.pipeline_,
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

shader_pipeline_destroy :: proc(self:^Shader_Pipeline,) {

    delete(self.resources)

    delete(self.binding_parameters.set_buffer_indices)
    delete(self.binding_parameters.set_buffer_offsets)
    delete(self.binding_parameters.buffer_infos)


    vk.DestroyPipeline(self.vk_device, self.pipeline, nil)
    vk.DestroyPipelineLayout(self.vk_device, self.pipeline_layout.vk_layout, nil)
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
    self.shader_pipeline.resources = make([dynamic]Shader_Resource)
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
/*
    Uniforms are for relatively small amounts of data taht you want to change regularly.
*/
shader_pipeline_builder_bind_uniform_ptr :: proc(self: ^Shader_Pipeline_Builder, data: ^^$T, set:u32, binding: u32) {
    uniform_binding: Uniform_Binding
    uniform_binding.set = set
    uniform_binding.binding = binding
    uniform_binding.mem_reference = memory_manager_bind_uniform(self.memory_manager, size_of(T))

    assert(uniform_binding.mem_reference.pointer != nil, "Got a bad pointer for the uniform")
    append(&self.shader_pipeline.resources, uniform_binding)

    data^ = cast(^T)uniform_binding.mem_reference.pointer
}
/*
    Images are required to be it's own type of data.
*/
shader_pipeline_builder_bind_image :: proc(self: ^Shader_Pipeline_Builder, texture_reference: Texture_Reference, set:u32, binding:u32) {

    texture_binding: Texture_Binding

    texture_binding.reference = texture_reference 
    texture_binding.set = set
    texture_binding.binding = binding

    append(&self.shader_pipeline.resources, texture_binding)
}

shader_pipeline_bind_static_buffer :: proc(self: ^Shader_Pipeline_Builder, buffer: Allocated_Buffer, set: u32, binding: u32, loc:= #caller_location) {
    append(&self.shader_pipeline.resources, Buffer_Binding{
        set = set,
        binding = binding,
        reference = buffer,
    } )

}

shader_pipeline_builder_build :: proc(self: ^Shader_Pipeline_Builder, engine:^Engine) ->(shader_pipeline:Shader_Pipeline, ok:bool) {

    shader_pipeline = self.shader_pipeline
    shader_pipeline.vk_device = self.vk_device
    defer delete_reflected_shaders(&self.reflect_layout)

    shader_pipeline.pipeline_layout = generate_vk_layout(self.vk_device, engine.memory_manager.universal_layout, &self.reflect_layout) or_return

    switch &shaders in self.shaders {
    case Compute_Shaders:
        module:= shader_get_module(self.vk_device, engine, &shaders.compute) or_return
        pipeline_create_info := vk.ComputePipelineCreateInfo {
            sType = .COMPUTE_PIPELINE_CREATE_INFO,
            flags = {.DESCRIPTOR_BUFFER_EXT},
            layout = shader_pipeline.pipeline_layout.vk_layout,
            stage = pipeline_shader_stage_create_info({.COMPUTE}, module, "main"),
        }
        shader_pipeline.bind_point = .COMPUTE
        vk_check(vk.CreateComputePipelines(self.vk_device, 0, 1, &pipeline_create_info, nil, &shader_pipeline.pipeline), "Failed to create compute pipeline") or_return
    
    case Render_Shaders:

    }

    sets:= shader_pipeline.pipeline_layout.sets
    shader_pipeline.binding_parameters.set_buffer_indices = make([]u32, sets)
    shader_pipeline.binding_parameters.set_buffer_offsets = make([]vk.DeviceSize, sets)
    shader_pipeline.binding_parameters.buffer_infos = make([]vk.DescriptorBufferBindingInfoEXT, 2)
    shader_pipeline.binding_parameters.buffer_infos[0] = self.memory_manager.texture_heap.bind_info
    shader_pipeline.binding_parameters.buffer_infos[1] = self.memory_manager.descriptor_arena.bind_info

    for i in 0..< sets {
        if i == 0 {
            shader_pipeline.binding_parameters.set_buffer_indices[i] = 0
            shader_pipeline.binding_parameters.set_buffer_offsets[i] = 0
        }
        else { 
            shader_pipeline.binding_parameters.set_buffer_indices[i] = 1
            shader_pipeline.binding_parameters.set_buffer_offsets[i] = memory_manager_register_set_descriptor_ring(self.memory_manager, shader_pipeline.pipeline_layout.set_layouts[i]) 
        }
    }
    for resource in shader_pipeline.resources{

        set, binding: u32
        base_ptr := self.memory_manager.descriptor_arena.buffer.mapped_ptr
        get_info := vk.DescriptorGetInfoEXT{
            sType = .DESCRIPTOR_GET_INFO_EXT,
        }
        //Looping over each "frame" of the set buffer to fill with default data.
        for i in 0..< self.memory_manager.uniform.buffering_depth {
            switch res in resource{
            case Texture_Binding:
                set, binding = res.set, res.binding
                img := vk.DescriptorImageInfo{
                    imageView = res.reference.image.image_view,
                    imageLayout = .GENERAL,
                }
                get_info.type = .STORAGE_IMAGE
                get_info.data = {pStorageImage = &img}

                case Buffer_Binding:

                    buffer := vk.DescriptorAddressInfoEXT {
                        sType = .DESCRIPTOR_ADDRESS_INFO_EXT,
                        address = res.reference.device_address,
                        range = res.reference.size,
                    }
                    get_info.type = .UNIFORM_BUFFER
                    get_info.data = {pUniformBuffer = &buffer}

                    case Uniform_Binding:

            }
            dst := ptr_offset(base_ptr, shader_pipeline.binding_parameters.set_buffer_offsets[set] + shader_pipeline.pipeline_layout.set_layouts[set].binding_offsets[binding]) 
            vk.GetDescriptorEXT(self.vk_device, &get_info, int(get_descriptor_size(self.memory_manager, get_info.type)) , dst)
        }
    }

    deletion_queue_push(&engine.main_deletion_queue, shader_pipeline)
    return shader_pipeline, true
}


