package astro

import "core:log"
import vk "vendor:vulkan"
import "base:runtime"
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
    set_arena_references: []Arena_Reference,
}

Binding_Parameters :: struct {
    buffer_infos: []vk.DescriptorBufferBindingInfoEXT,
    set_buffer_indices: []u32,
    set_buffer_frame_offsets: []vk.DeviceSize,
}
Binding :: struct {
    binding: u32,
    set: u32,
    type: vk.DescriptorType,
}
Uniform_Binding :: struct {
    using bind: Binding,
    mem_reference: Memory_Reference,
}
Texture_Binding :: struct {
    using bind:Binding,
    reference: Texture_Reference,
}

Buffer_Binding :: struct {
    using bind:Binding,
    reference: Allocated_Buffer
}

/*
    1. Bind Pipeline.
*/

shader_pipeline_bind :: proc(self: ^Shader_Pipeline, cmd: vk.CommandBuffer, engine:^Engine) {
    frame := engine.memory_manager.draw_frame 
    
    for i in 1..<len(self.pipeline_layout.set_layouts) {
        self.binding_parameters.set_buffer_frame_offsets[i] = self.set_arena_references[i].arena_offset + self.set_arena_references[i].descriptor_size * vk.DeviceSize(frame)
    }

    //1. Bind Pipeline
    vk.CmdBindPipeline(cmd, self.bind_point, self.pipeline) 
    //2. Bind All buffers used by this pipeline must always include the default descriptor buffer
    vk.CmdBindDescriptorBuffersEXT(cmd, u32(len(self.binding_parameters.buffer_infos)), raw_data(self.binding_parameters.buffer_infos))

    //3. Set for each set I need to specify where the descriptor lives (buffer index from Step 2, offset into that buffer)
    vk.CmdSetDescriptorBufferOffsetsEXT(cmd, self.bind_point, self.pipeline_layout.vk_layout, 0, self.pipeline_layout.sets, raw_data(self.binding_parameters.set_buffer_indices), raw_data(self.binding_parameters.set_buffer_frame_offsets))
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
    delete(self.binding_parameters.set_buffer_frame_offsets)
    delete(self.binding_parameters.buffer_infos)
    delete(self.set_arena_references)

    // Set 0 is the shared texture heap layout, which the memory manager owns.
    for &set_layout, i in self.pipeline_layout.set_layouts {
        if i == 0 {
            continue
        }
        delete(set_layout.binding_layouts)
        vk.DestroyDescriptorSetLayout(self.vk_device, set_layout.vk_layout, nil)
    }
    delete(self.pipeline_layout.set_layouts)

    vk.DestroyPipeline(self.vk_device, self.pipeline, nil)
    vk.DestroyPipelineLayout(self.vk_device, self.pipeline_layout.vk_layout, nil)
}

Graphics_Pipeline_Options :: struct {
    
    shader_stages:           [dynamic; MAX_SHADER_STAGES]vk.PipelineShaderStageCreateInfo,
    input_assembly:          vk.PipelineInputAssemblyStateCreateInfo,
    rasterizer:              vk.PipelineRasterizationStateCreateInfo,
    color_blend_attachment:  vk.PipelineColorBlendAttachmentState,
    multisampling:           vk.PipelineMultisampleStateCreateInfo,
    depth_stencil:           vk.PipelineDepthStencilStateCreateInfo,
    render_info:             vk.PipelineRenderingCreateInfo,
    color_attachment_format: vk.Format,
    tessellation_state:      vk.PipelineTessellationStateCreateInfo,
    base_pipeline:           vk.Pipeline,
    base_pipeline_index:     i32,
    flags:                   vk.PipelineCreateFlags,
    allocator:               runtime.Allocator,

}

/*
    State shared by both builders. Resource binding (uniforms, images, buffers) lives here and works on either builder
    through subtype polymorphism, so the compute and graphics builders only add what is specific to them.
    Builders are not copyable once graphics state is set, since some of that state points back into the builder.
*/
Pipeline_Builder_Base :: struct {
    vk_device: vk.Device,
    reflect_layout: Reflected_Shaders,
    shader_pipeline: Shader_Pipeline,
    memory_manager: ^Memory_Manager,
    failed: bool,
}

Compute_Pipeline_Builder :: struct {
    using base: Pipeline_Builder_Base,
    shaders: Compute_Shaders,
}

Graphics_Pipeline_Builder :: struct {
    using base: Pipeline_Builder_Base,
    shaders: Render_Shaders,
    graphics: Graphics_Pipeline_Options,
}

@(private="file")
pipeline_builder_base_init :: proc(self: ^Pipeline_Builder_Base, memory_manager: ^Memory_Manager, device: vk.Device) {
    self.vk_device = device
    self.memory_manager = memory_manager
    self.shader_pipeline.resources = make([dynamic]Shader_Resource)
}

compute_pipeline_builder_init :: proc(self: ^Compute_Pipeline_Builder, memory_manager: ^Memory_Manager, device: vk.Device) -> (ok: bool) {
    pipeline_builder_base_init(self, memory_manager, device)
    return true
}

compute_pipeline_builder_set_shader :: proc(self: ^Compute_Pipeline_Builder, compute: Shader, loc := #caller_location) {
    ok: bool
    self.shaders = {compute = compute}
    self.reflect_layout, ok = shaders_generate_raw_layout_compute(self.vk_device, self.shaders)
    if !ok {
        log.errorf("Could not generate the layout for the Compute Shader, %v", loc)
        self.failed = true
    }
}

graphics_pipeline_builder_init :: proc(self: ^Graphics_Pipeline_Builder, memory_manager: ^Memory_Manager, device: vk.Device) -> (ok: bool) {
    pipeline_builder_base_init(self, memory_manager, device)

    self.graphics.input_assembly = {
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    }
    self.graphics.rasterizer = {
        sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    }
    self.graphics.multisampling = {
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    }
    self.graphics.depth_stencil = {
        sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    }
    self.graphics.tessellation_state = {
        sType = .PIPELINE_TESSELLATION_STATE_CREATE_INFO,
    }
    self.graphics.render_info = {
        sType = .PIPELINE_RENDERING_CREATE_INFO,
    }
    return true
}

graphics_pipeline_builder_set_shaders :: proc(self: ^Graphics_Pipeline_Builder, shaders: Render_Shaders, loc := #caller_location) {
    ok: bool
    self.shaders = shaders
    self.reflect_layout, ok = shaders_generate_raw_layout_render(self.vk_device, shaders)
    if !ok {
        log.errorf("Could not generate the layout for the Render Shaders, %v", loc)
        self.failed = true
    }
}

/*
    Uniforms are for relatively small amounts of data taht you want to change regularly.
*/
pipeline_builder_bind_uniform_ptr :: proc(self: ^Pipeline_Builder_Base, data: ^^$T, set:u32, binding: u32) {
    uniform_binding: Uniform_Binding
    uniform_binding.set = set
    uniform_binding.binding = binding
    uniform_binding.mem_reference = memory_manager_bind_uniform(self.memory_manager, size_of(T))

    assert(uniform_binding.mem_reference.cpu_pointer != nil, "Got a bad pointer for the uniform")
    append(&self.shader_pipeline.resources, uniform_binding)

    data^ = cast(^T)uniform_binding.mem_reference.cpu_pointer
}
/*
    Images are required to be it's own type of data.
*/
pipeline_builder_bind_image :: proc(self: ^Pipeline_Builder_Base, texture_reference: Texture_Reference, set:u32, binding:u32) {

    texture_binding: Texture_Binding

    texture_binding.reference = texture_reference 
    texture_binding.set = set
    texture_binding.binding = binding

    append(&self.shader_pipeline.resources, texture_binding)
}

pipeline_builder_bind_static_buffer :: proc(self: ^Pipeline_Builder_Base, buffer: Allocated_Buffer, set: u32, binding: u32, loc:= #caller_location) {
    append(&self.shader_pipeline.resources, Buffer_Binding{
        set = set,
        binding = binding,
        reference = buffer,
    })
}
/*
    Must be a pointer to an array or a struct that doesn't contain pointers. The data will be uploaded AS-IS.
    The buffer is owned by the engine's deletion queue, it lives until the owning module (game) is torn down.
 */
pipeline_builder_bind_new_static_buffer :: proc(self: ^Pipeline_Builder_Base, engine:^Engine, data:^$T, usage:vk.BufferUsageFlags = {.STORAGE_BUFFER}, set:u32, binding: u32,loc:= #caller_location) -> (buffer: Allocated_Buffer){
    log.debugf("Binding new Static Buffer")
    ok: bool 
    buffer, ok = upload_data(engine, data, usage)
    if !ok {
        self.failed = true
        log.errorf("Failed create new Static Buffer")
        return buffer
    } 
    deletion_queue_push(&engine.main_deletion_queue, buffer)
    pipeline_builder_bind_static_buffer(self, buffer, set, binding, loc)

    return buffer 

}

/*
    Shared build steps
*/

// Generates the vulkan pipeline layout (and the per-set descriptor layouts) from reflection into `pipeline`.
@(private="file")
pipeline_create_layout :: proc(self: ^Pipeline_Builder_Base, pipeline: ^Shader_Pipeline) -> (ok: bool) {
    pipeline.vk_device = self.vk_device
    pipeline.pipeline_layout = generate_vk_layout(self.vk_device, GLOBALS.memory_manager.universal_heap.set_layout^, &self.reflect_layout) or_return
    return true
}

// Reserves descriptor memory for every set of the pipeline (set 0 is the shared texture heap).
@(private="file")
pipeline_alloc_set_memory :: proc(pipeline: ^Shader_Pipeline,) {
    memory_manager:= GLOBALS.memory_manager
    sets := pipeline.pipeline_layout.sets
    pipeline.binding_parameters.set_buffer_indices = make([]u32, sets)
    pipeline.set_arena_references = make([]Arena_Reference, sets)
    pipeline.binding_parameters.set_buffer_frame_offsets = make([]vk.DeviceSize, sets)
    pipeline.binding_parameters.buffer_infos = make([]vk.DescriptorBufferBindingInfoEXT, 2)
    pipeline.binding_parameters.buffer_infos[0] = memory_manager.universal_heap.bind_info
    pipeline.binding_parameters.buffer_infos[1] = memory_manager.descriptor_arena.bind_info

    for i in 0..< sets {
        if i == 0 {
            pipeline.binding_parameters.set_buffer_indices[i] = 0
            pipeline.set_arena_references[0] = {}
            pipeline.binding_parameters.set_buffer_frame_offsets[i] = 0
        }
        else { 
            pipeline.binding_parameters.set_buffer_indices[i] = 1
            pipeline.set_arena_references[i] = memory_manager_register_descriptor(pipeline.pipeline_layout.set_layouts[i].total_set_size, memory_manager.frames_buffered) 
        }
    }
}

// Writes the descriptor of every resource into each frame's copy of its set.
@(private="file")
pipeline_write_resources :: proc(pipeline: ^Shader_Pipeline) -> (ok: bool) {
    memory_manager := GLOBALS.memory_manager
    sets := pipeline.pipeline_layout.sets
    base_ptr := memory_manager.descriptor_arena.buffer.cpu_write_ptr

    for resource in pipeline.resources {
        set, binding: u32
        get_info := vk.DescriptorGetInfoEXT{
            sType = .DESCRIPTOR_GET_INFO_EXT,
        }
        //Looping over each "frame" of the set buffer to fill with default data.
        for i in 0..< memory_manager.frames_buffered {
            ring_frame_offset: vk.DeviceSize = vk.DeviceSize(i) * memory_manager.uniform.frame_buffer_size
            data: rawptr
            switch res in resource{

            case Texture_Binding:
                set, binding = res.set, res.binding
                data = &vk.DescriptorImageInfo{
                    imageView = res.reference.image.image_view,
                }

            case Buffer_Binding:
                set, binding = res.set, res.binding
                data = &vk.DescriptorAddressInfoEXT {
                    sType = .DESCRIPTOR_ADDRESS_INFO_EXT,
                    address = res.reference.gpu_address,
                    range = res.reference.size,
                }

            case Uniform_Binding:
                set, binding = res.set, res.binding
                data = &vk.DescriptorAddressInfoEXT {
                    sType = .DESCRIPTOR_ADDRESS_INFO_EXT,
                    address = memory_manager.uniform.ring_buffer.gpu_address+ vk.DeviceAddress(ring_frame_offset + res.mem_reference.gpu_offset),
                    range = res.mem_reference.size,
                }
            }
            if set == 0 || set >= sets || int(binding) >= len(pipeline.pipeline_layout.set_layouts[set].binding_layouts) {
                log.errorf("Resource bound to set %v binding %v, which isn't a bindable slot in this pipeline (set 0 is the shared texture heap)", set, binding)
                return false
            }
            get_info.type = pipeline.pipeline_layout.set_layouts[set].binding_layouts[binding].type 
            switch get_info.type {
            case .COMBINED_IMAGE_SAMPLER:
                get_info.data.pCombinedImageSampler = cast(^vk.DescriptorImageInfo)data
                get_info.data.pCombinedImageSampler.imageLayout = .GENERAL
            case .SAMPLED_IMAGE:
                get_info.data.pSampledImage = cast(^vk.DescriptorImageInfo)data
                get_info.data.pCombinedImageSampler.imageLayout = .SHADER_READ_ONLY_OPTIMAL
            case .STORAGE_IMAGE: 
                get_info.data.pStorageImage = cast(^vk.DescriptorImageInfo)data
                get_info.data.pCombinedImageSampler.imageLayout = .GENERAL
            case .INPUT_ATTACHMENT:
                get_info.data.pInputAttachmentImage = cast(^vk.DescriptorImageInfo)data
                get_info.data.pCombinedImageSampler.imageLayout = .GENERAL

            case .UNIFORM_BUFFER, .UNIFORM_BUFFER_DYNAMIC, .INLINE_UNIFORM_BLOCK:
                get_info.data.pUniformBuffer = cast(^vk.DescriptorAddressInfoEXT)data
            case .STORAGE_BUFFER, .STORAGE_BUFFER_DYNAMIC:
                get_info.data.pStorageBuffer = cast(^vk.DescriptorAddressInfoEXT)data
            case .UNIFORM_TEXEL_BUFFER:
                get_info.data.pUniformTexelBuffer = cast(^vk.DescriptorAddressInfoEXT)data
            case .STORAGE_TEXEL_BUFFER:
                get_info.data.pStorageTexelBuffer = cast(^vk.DescriptorAddressInfoEXT)data
            case .SAMPLER, .ACCELERATION_STRUCTURE_NV, .ACCELERATION_STRUCTURE_KHR, .SAMPLE_WEIGHT_IMAGE_QCOM, .BLOCK_MATCH_IMAGE_QCOM, .TENSOR_ARM, .MUTABLE_EXT, .PARTITIONED_ACCELERATION_STRUCTURE_NV:
                log.errorf("I Don't support these descriptor types, they are an offront to God and I denounce them unequivically: %v", get_info.type)
                return false
            }
            offset := get_descriptor_offset(&pipeline.set_arena_references[set], i)
            dst := ptr_offset(base_ptr,
                offset + pipeline.pipeline_layout.set_layouts[set].binding_layouts[binding].offset)

            vk.GetDescriptorEXT(pipeline.vk_device, &get_info, int(get_descriptor_size(get_info.type)) , dst)
        }
    }
    return true
}

// Allocates descriptor memory, writes the bound resources, and hands the pipeline to the engine for cleanup.
@(private="file")
pipeline_finalize :: proc(self: ^Pipeline_Builder_Base, engine: ^Engine, pipeline: ^Shader_Pipeline) -> (ok: bool) {
    pipeline_alloc_set_memory(pipeline)
    pipeline_write_resources(pipeline) or_return
    deletion_queue_push(&engine.main_deletion_queue, pipeline^)
    return true
}

compute_pipeline_builder_build :: proc(self: ^Compute_Pipeline_Builder, engine: ^Engine) -> (pipeline: Shader_Pipeline, ok: bool) {
    defer delete_reflected_shaders(&self.reflect_layout)
    if self.failed {
        log.errorf("Compute Pipeline had an error before calling _build")
        delete(self.shader_pipeline.resources)
        return pipeline, false
    }
    pipeline = self.shader_pipeline
    defer if !ok {
        shader_pipeline_destroy(&pipeline)
    }

    pipeline_create_layout(self, &pipeline) or_return

    module := shader_get_module(self.vk_device, engine, &self.shaders.compute) or_return
    pipeline_create_info := vk.ComputePipelineCreateInfo {
        sType = .COMPUTE_PIPELINE_CREATE_INFO,
        flags = {.DESCRIPTOR_BUFFER_EXT},
        layout = pipeline.pipeline_layout.vk_layout,
        stage = pipeline_shader_stage_create_info({.COMPUTE}, module, "main"),
    }
    pipeline.bind_point = .COMPUTE
    vk_check(vk.CreateComputePipelines(self.vk_device, 0, 1, &pipeline_create_info, nil, &pipeline.pipeline), "Failed to create compute pipeline") or_return

    pipeline_finalize(self, engine, &pipeline) or_return
    return pipeline, true
}

graphics_pipeline_builder_build :: proc(self: ^Graphics_Pipeline_Builder, engine: ^Engine) -> (pipeline: Shader_Pipeline, ok: bool) {
    defer delete_reflected_shaders(&self.reflect_layout)
    if self.failed {
        log.errorf("Graphics Pipeline had an error before calling _build")
        delete(self.shader_pipeline.resources)
        return pipeline, false
    }
    pipeline = self.shader_pipeline
    defer if !ok {
        shader_pipeline_destroy(&pipeline)
    }

    pipeline_create_layout(self, &pipeline) or_return
    pipeline.bind_point = .GRAPHICS

    viewport_state := vk.PipelineViewportStateCreateInfo {
        sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount = 1,
    }

    color_blending := vk.PipelineColorBlendStateCreateInfo {
        sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable = false,
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = &self.graphics.color_blend_attachment,
    }

    vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    }

    dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR, .POLYGON_MODE_EXT}
    dynamic_info := vk.PipelineDynamicStateCreateInfo {
        sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        pDynamicStates = raw_data(dynamic_states[:]),
        dynamicStateCount = u32(len(dynamic_states)),
    }

    module_infos := make([dynamic]vk.PipelineShaderStageCreateInfo) 
    defer delete(module_infos)

    for stage in self.reflect_layout.stage_params {
        module : vk.ShaderModule
        #partial switch stage.stage {
        case .VERTEX:
            module, ok = shader_get_module(self.vk_device, engine, &self.shaders.vertex)
        case .TESSELLATION_CONTROL:
            module, ok = shader_get_module(self.vk_device, engine, &self.shaders.tessellation_control)
        case .TESSELLATION_EVALUATION:
            module, ok = shader_get_module(self.vk_device, engine, &self.shaders.tessellation_evaluation)
        case .GEOMETRY:
            module, ok = shader_get_module(self.vk_device, engine, &self.shaders.geometry)
        case .FRAGMENT:
            module, ok = shader_get_module(self.vk_device, engine, &self.shaders.fragment)
        }

        if !ok{
            log.errorf("Failed to create shader module") 
            return pipeline, false
        }

        append(&module_infos, pipeline_shader_stage_create_info({stage.stage}, module, "main"))
    }
    flags := self.graphics.flags | {.DESCRIPTOR_BUFFER_EXT}
    pipeline_create_info := vk.GraphicsPipelineCreateInfo {
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        // Connect the renderInfo to the pNext extension mechanism
        pNext               = &self.graphics.render_info,
        flags               = flags,
        stageCount          = u32(len(module_infos)),
        pStages             = raw_data(module_infos[:]),
        pVertexInputState   = &vertex_input_info,
        pInputAssemblyState = &self.graphics.input_assembly,
        pTessellationState  = &self.graphics.tessellation_state,
        pViewportState      = &viewport_state,
        pRasterizationState = &self.graphics.rasterizer,
        pMultisampleState   = &self.graphics.multisampling,
        pDepthStencilState  = &self.graphics.depth_stencil,
        pColorBlendState    = &color_blending,
        pDynamicState       = &dynamic_info,
        layout              = pipeline.pipeline_layout.vk_layout,
    }

    vk_check(vk.CreateGraphicsPipelines(self.vk_device, 0, 1, &pipeline_create_info, nil, &pipeline.pipeline), "Failed to create graphics pipeline") or_return

    pipeline_finalize(self, engine, &pipeline) or_return
    return pipeline, true
}

// Graphics Options
graphics_pipeline_builder_set_input_topology :: proc(self: ^Graphics_Pipeline_Builder, topology: vk.PrimitiveTopology, primitive_restart_enable: bool = false,) {

    self.graphics.input_assembly.topology = topology
    self.graphics.input_assembly.primitiveRestartEnable = b32(primitive_restart_enable)

}

graphics_pipeline_builder_set_polygon_mode :: proc(self: ^Graphics_Pipeline_Builder, polygon_mode: vk.PolygonMode, line_width: f32 = 1.0,) {
    self.graphics.rasterizer.polygonMode = polygon_mode
    self.graphics.rasterizer.lineWidth = line_width
}

graphics_pipeline_builder_set_cull_mode :: proc(self: ^Graphics_Pipeline_Builder, cull_mode: vk.CullModeFlags, front_face: vk.FrontFace,) {
    self.graphics.rasterizer.cullMode = cull_mode
    self.graphics.rasterizer.frontFace = front_face
}

graphics_pipeline_builder_set_multisampling :: proc(self: ^Graphics_Pipeline_Builder, rasterization_samples: vk.SampleCountFlags, min_sample_shading: f32 = 1.0, sample_mask: ^vk.SampleMask = nil, alpha_to_coverage_enable: bool = false, alpha_to_one_enable: bool = false,) {
    self.graphics.multisampling.rasterizationSamples = rasterization_samples
    self.graphics.multisampling.sampleShadingEnable = min_sample_shading < 1.0
    self.graphics.multisampling.minSampleShading = min_sample_shading
    self.graphics.multisampling.pSampleMask = sample_mask
    self.graphics.multisampling.alphaToCoverageEnable = b32(alpha_to_coverage_enable)
    self.graphics.multisampling.alphaToOneEnable = b32(alpha_to_one_enable)
}

graphics_pipeline_builder_set_multisampling_none :: proc(self: ^Graphics_Pipeline_Builder) {
    graphics_pipeline_builder_set_multisampling(self, {._1})
}

graphics_pipeline_builder_set_blend_state :: proc(
    self: ^Graphics_Pipeline_Builder,
    blend_enable: bool,
    src_color_blend: vk.BlendFactor,
    dst_color_blend: vk.BlendFactor,
    color_blend_op: vk.BlendOp,
    src_alpha_blend: vk.BlendFactor,
    dst_alpha_blend: vk.BlendFactor,
    alpha_blend_op: vk.BlendOp,
    color_write_mask: vk.ColorComponentFlags,
) {
    self.graphics.color_blend_attachment = {
        blendEnable         = b32(blend_enable),
        srcColorBlendFactor = src_color_blend,
        dstColorBlendFactor = dst_color_blend,
        colorBlendOp        = color_blend_op,
        srcAlphaBlendFactor = src_alpha_blend,
        dstAlphaBlendFactor = dst_alpha_blend,
        alphaBlendOp        = alpha_blend_op,
        colorWriteMask      = color_write_mask,
    }
}

graphics_pipeline_builder_enable_blending_additive :: proc(self: ^Graphics_Pipeline_Builder) {
    self.graphics.color_blend_attachment.colorWriteMask = {.R,.G,.B,.A}
    self.graphics.color_blend_attachment.blendEnable = true
    self.graphics.color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
    self.graphics.color_blend_attachment.dstColorBlendFactor = .ONE
    self.graphics.color_blend_attachment.colorBlendOp = .ADD
    self.graphics.color_blend_attachment.srcAlphaBlendFactor = .ONE
    self.graphics.color_blend_attachment.dstAlphaBlendFactor = .ZERO
    self.graphics.color_blend_attachment.alphaBlendOp = .ADD
}

graphics_pipeline_builder_enable_blending_alphablend :: proc(self: ^Graphics_Pipeline_Builder) {
    self.graphics.color_blend_attachment.colorWriteMask = {.R,.G,.B,.A}
    self.graphics.color_blend_attachment.blendEnable = true
    self.graphics.color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
    self.graphics.color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
    self.graphics.color_blend_attachment.colorBlendOp = .ADD
    self.graphics.color_blend_attachment.srcAlphaBlendFactor = .ONE
    self.graphics.color_blend_attachment.dstAlphaBlendFactor = .ZERO
    self.graphics.color_blend_attachment.alphaBlendOp = .ADD
}

graphics_pipeline_builder_disable_blending :: proc(self: ^Graphics_Pipeline_Builder) {
    self.graphics.color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
    self.graphics.color_blend_attachment.blendEnable = false
}

graphics_pipeline_builder_set_color_attachment_format :: proc(self: ^Graphics_Pipeline_Builder, format: vk.Format,) {
    self.graphics.color_attachment_format = format
    self.graphics.render_info.colorAttachmentCount = 1
    self.graphics.render_info.pColorAttachmentFormats = &self.graphics.color_attachment_format
}

graphics_pipeline_builder_set_depth_attachment_format :: proc(self: ^Graphics_Pipeline_Builder, format: vk.Format,) {
    self.graphics.render_info.depthAttachmentFormat = format
}

graphics_pipeline_builder_enable_depth_test :: proc(self:^Graphics_Pipeline_Builder, depth_write_enable: bool, op: vk.CompareOp) {
    self.graphics.depth_stencil.depthTestEnable = true
    self.graphics.depth_stencil.depthWriteEnable = b32(depth_write_enable)
    self.graphics.depth_stencil.depthCompareOp = op
    self.graphics.depth_stencil.depthBoundsTestEnable = false
    self.graphics.depth_stencil.stencilTestEnable = false
    self.graphics.depth_stencil.front = {}
    self.graphics.depth_stencil.back = {}
    self.graphics.depth_stencil.minDepthBounds = 0.0
    self.graphics.depth_stencil.maxDepthBounds = 1.0
}

graphics_pipeline_builder_disable_depth_test :: proc(self: ^Graphics_Pipeline_Builder) {
    self.graphics.depth_stencil.depthTestEnable = false
    self.graphics.depth_stencil.depthWriteEnable = false
    self.graphics.depth_stencil.depthCompareOp = .NEVER
    self.graphics.depth_stencil.depthBoundsTestEnable = false
    self.graphics.depth_stencil.stencilTestEnable = false
    self.graphics.depth_stencil.front = {}
    self.graphics.depth_stencil.back = {}
    self.graphics.depth_stencil.minDepthBounds = 0.0
    self.graphics.depth_stencil.maxDepthBounds = 1.0
}


