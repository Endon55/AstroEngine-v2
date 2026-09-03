package astro

import "core:log"
import "base:runtime"

import "vendor:glfw"
import vk "vendor:vulkan"
import im "libs:imgui"
import im_glfw "libs:imgui/backends/glfw"
import im_vk "libs:imgui/backends/vulkan"


import "libs:vkb"
import vma "libs:vma"


@(require_results)
engine_init :: proc(self: ^Engine) -> (ok: bool) {
    ensure(self != nil, "Invalid 'Engine' object")

    g_logger = context.logger

    self.window_extent = DEFAULT_WINDOW_EXTENT
    self.render_scale = 1.0

    self.window = create_window(
        TITLE,
        self.window_extent.width,
        self.window_extent.height,
    ) or_return
    defer if !ok {
        destroy_window(self.window)
    }
    
    glfw.SetWindowUserPointer(self.window, self)

    glfw.SetFramebufferSizeCallback(self.window, callback_framebuffer_size)
    glfw.SetWindowIconifyCallback(self.window, callback_window_minimize)
   

    log.debugf("Initializing Vulkan")
    engine_init_vulkan(self) or_return
    log.debugf("Initializing Swapchain")
    engine_init_swapchain(self) or_return
    log.debugf("Initializing Engine Commands")
    engine_init_commands(self) or_return
    log.debugf("Initializing Sync Structures")
    engine_init_sync_structures(self) or_return
    log.debugf("Initializing Descriptors")
    engine_init_descriptors(self) or_return
    log.debugf("Initializing Pipelines")
    engine_init_pipelines(self) or_return
    log.debugf("Initializing ImGui")
    engine_init_imgui(self) or_return
    log.debugf("Initializing Vulkan")
    engine_init_default_data(self) or_return
    self.is_initialized = true

    return true

}

engine_resize_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    vk_check(vk.DeviceWaitIdle(self.vk_device)) or_return

    width, height := glfw.GetFramebufferSize(self.window)
    self.window_extent = {u32(width), u32(height)}
    // log.infof("Window Extent: %v", self.window_extent)
    // log.infof("Draw Extent: %v", self.draw_extent)
    engine_create_swapchain(self, self.window_extent) or_return

    return true
}

engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool){

    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    
    features:= Vulkan_Feature_Requirements {
        device_features_11 = {
            sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
            shaderDrawParameters = true,
        },
        device_features_12 = {
            sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            bufferDeviceAddress = true,
            descriptorIndexing = true,
            vulkanMemoryModelAvailabilityVisibilityChains = false,
        },
        device_features_13 = {
            sType =.PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            dynamicRendering = true,
            synchronization2 = true,
        },
    }
    features.device_extensions = make([dynamic]cstring, context.allocator)
    append(&features.device_extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME, vk.KHR_PIPELINE_LIBRARY_EXTENSION_NAME, vk.EXT_GRAPHICS_PIPELINE_LIBRARY_EXTENSION_NAME)
    log.debugf("---Creating Instance")
    create_vk_instance(&self.vk_context, features, self) or_return
    self.vk_instance = self.vk_context.vk_instance
    vk_check(glfw.CreateWindowSurface(self.vk_instance, self.window, self.vk_context.allocation_callbacks , &self.vk_surface),) or_return

    defer if !ok {
        vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    }

    log.debugf("---Selecting Physical Device")
    select_vk_physical_device(&self.vk_context, self.vk_surface) or_return
    log.debugf("---Creating Logical Device")
    create_vk_logical_device(&self.vk_context) or_return

    self.vk_physical_device = self.vk_context.physical_device.vk_physical_device
    self.vk_device = self.vk_context.vk_device
    
    log.debugf("Setting up deletion queue and allocators")
    deletion_queue_init(&self.main_deletion_queue, self.vk_device)


    vma_vulkan_functions := vma.create_vulkan_functions()
    api_version := min(self.vkb.instance.api_version, self.vkb.physical_device.vk_properties.apiVersion)


    vma_create_info: vma.AllocatorCreateInfo = {
        flags = {.BUFFER_DEVICE_ADDRESS},
        instance = self.vk_instance,
        physicalDevice = self.vk_physical_device,
        device = self.vk_device,
        pVulkanFunctions = &vma_vulkan_functions,
        vulkanApiVersion = api_version,
    }


    vk_check(vma.CreateAllocator(vma_create_info, &self.vma_allocator)) or_return

    deletion_queue_push(&self.main_deletion_queue, self.vma_allocator)

    return true 
}

engine_create_swapchain :: proc(self: ^Engine, extent: vk.Extent2D) -> (ok: bool) {

    ta := context.temp_allocator
    create_vk_swapchain(&self.vk_context.swapchain_context, extent.width, extent.height)

    if self.vk_swapchain != {} {
        engine_destroy_swapchain(self)
    }

    self.vk_swapchain = self.vk_context.swapchain_context.vk_swapchain
    self.swapchain_extent = self.vk_context.swapchain_context.vk_extent
    self.swapchain_format = self.vk_context.swapchain_context.vk_surface_format.format
    swapchain_images, swapchain_images_err := swapchain_get_images(self.vk_context.swapchain_context)

    if swapchain_images_err != false {
        log.errorf("Failed to build swapchain images: %#v", swapchain_images_err)
        return
    }

    swapchain_image_views, swapchain_image_views_err := swapchain_get_image_views(self.vk_context.swapchain_context, swapchain_images)

    if swapchain_image_views_err != false {
        log.errorf("Failed to build swapchain image views: %#v", swapchain_image_views_err)
        return
    }
    self.swapchain_images = swapchain_images
    self.swapchain_image_views = swapchain_image_views
    
    graphics_queue, graphics_queue_err := device_get_universal_queue(self.vk_context)
    if graphics_queue_err != false {
        log.errorf("Failed to get graphics queue: %#v", graphics_queue_err)
    }

    graphics_queue_family, graphics_queue_family_err := device_get_universal_queue_index(self.vk_context)
    if graphics_queue_family_err != false {
        log.errorf("Failed to get graphics queue family: %#v", graphics_queue_family_err)
    }

    self.graphics_queue = graphics_queue
    self.graphics_queue_family = graphics_queue_family


    self.swapchain_image_semaphores = make([]vk.Semaphore, len(self.swapchain_images))
    defer if !ok {delete(self.swapchain_image_semaphores)}

    semaphore_create_info := semaphore_create_info()
    for &semaphore in self.swapchain_image_semaphores {
        vk_check(vk.CreateSemaphore( self.vk_device, &semaphore_create_info, nil, &semaphore)) or_return
    }

    return true
}

engine_destroy_swapchain :: proc(self: ^Engine) {
    destroy_swapchain(self.vk_device, self.vk_swapchain, self.vk_context.allocation_callbacks)
    swapchain_destroy_image_views(self.vk_context.swapchain_context, self.swapchain_image_views)

    for semaphore in self.swapchain_image_semaphores {
        vk.DestroySemaphore(self.vk_device, semaphore, nil)
    }
    delete(self.swapchain_image_semaphores)
    delete(self.swapchain_image_views)
    delete(self.swapchain_images)
   
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool){
    engine_create_swapchain(self, self.window_extent) or_return

    monitor_width, monitor_height := get_monitor_resoution()

    draw_image_extent := vk.Extent3D {
        width = monitor_width,
        height = monitor_height,
        depth = 1,
    }

    //DRAW IMAGE
    self.draw_image.image_format = .R16G16B16A16_SFLOAT
    self.draw_image.image_extent = draw_image_extent
    self.draw_image.allocator = self.vma_allocator
    self.draw_image.device = self.vk_device

    draw_image_usages := vk.ImageUsageFlags {
        .TRANSFER_SRC,
        .TRANSFER_DST,
        .STORAGE,
        .COLOR_ATTACHMENT,
    }
    
    rimg_info := image_create_info(self.draw_image.image_format, draw_image_usages, draw_image_extent,)
    
    rimg_allocinfo := vma.AllocationCreateInfo {
        usage = .GPU_ONLY,
        requiredFlags = {.DEVICE_LOCAL,},
    }
    vk_check(vma.CreateImage(self.vma_allocator, rimg_info, rimg_allocinfo, &self.draw_image.image, &self.draw_image.allocation, nil)) or_return
    defer if !ok {
        vma.DestroyImage(self.vma_allocator, self.draw_image.image, nil)
    }

    rview_info := imageview_create_info(self.draw_image.image_format, self.draw_image.image, {.COLOR},)

    vk_check(vk.CreateImageView(self.vk_device, &rview_info, nil, &self.draw_image.image_view)) or_return
    defer if !ok {
        vk.DestroyImageView(self.vk_device, self.draw_image.image_view, nil)
    }

    deletion_queue_push(&self.main_deletion_queue, self.draw_image)


    //DEPTH IMAGE
    self.depth_image.image_format = .D32_SFLOAT
    self.depth_image.image_extent = draw_image_extent
    self.depth_image.allocator = self.vma_allocator
    self.depth_image.device = self.vk_device

    depth_image_usages := vk.ImageUsageFlags {
        .DEPTH_STENCIL_ATTACHMENT,
    }
    
    dimg_info := image_create_info(self.depth_image.image_format, depth_image_usages, draw_image_extent,)
    
    vk_check(vma.CreateImage(self.vma_allocator, dimg_info, rimg_allocinfo, &self.depth_image.image, &self.depth_image.allocation, nil)) or_return
    defer if !ok {
        vma.DestroyImage(self.vma_allocator, self.depth_image.image, nil)
    }

    dview_info := imageview_create_info(self.depth_image.image_format, self.depth_image.image, {.DEPTH},)

    vk_check(vk.CreateImageView(self.vk_device, &dview_info, nil, &self.depth_image.image_view)) or_return
    defer if !ok {
        vk.DestroyImageView(self.vk_device, self.depth_image.image_view, nil)
    }

    deletion_queue_push(&self.main_deletion_queue, self.depth_image)

    return true
}

engine_init_commands :: proc(self: ^Engine) -> (ok: bool){


    command_pool_info := command_pool_create_info(self.graphics_queue_family, {.RESET_COMMAND_BUFFER},)

    for &frame in self.frames {
        
        deletion_queue_init(&frame.deletion_queue, self.vk_device)
        
        vk_check(vk.CreateCommandPool(self.vk_device, &command_pool_info, nil, &frame.command_pool)) or_return

        cmd_alloc_info := command_buffer_allocate_info(frame.command_pool) 
        vk_check(vk.AllocateCommandBuffers(self.vk_device, &cmd_alloc_info, &frame.main_command_buffer)) or_return
    }

    vk_check(vk.CreateCommandPool(self.vk_device, &command_pool_info, nil, &self.imm_command_pool)) or_return

    cmd_alloc_info := command_buffer_allocate_info(self.imm_command_pool)
    vk_check(vk.AllocateCommandBuffers(self.vk_device, &cmd_alloc_info, &self.imm_command_buffer)) or_return
    deletion_queue_push(&self.main_deletion_queue, self.imm_command_pool)

    return true
}

engine_init_sync_structures :: proc(self: ^Engine) -> (ok: bool){

    fence_create_info := fence_create_info({.SIGNALED})
    semaphore_create_info := semaphore_create_info()

    for &frame in self.frames {
        vk_check(vk.CreateFence(self.vk_device, &fence_create_info, nil, &frame.render_fence)) or_return

        vk_check(vk.CreateSemaphore(self.vk_device, &semaphore_create_info, nil, &frame.swapchain_semaphore)) or_return
    }

    vk_check(vk.CreateFence(self.vk_device, &fence_create_info, nil, &self.imm_fence)) or_return
    deletion_queue_push(&self.main_deletion_queue, self.imm_fence)

    return true
}

engine_immediate_submit :: proc(self: ^Engine, data: $T, 
    fn: proc(engine: ^Engine, cmd: vk.CommandBuffer, data: T),) -> (ok: bool,) {

    vk_check(vk.ResetFences(self.vk_device, 1, &self.imm_fence)) or_return
    vk_check(vk.ResetCommandBuffer(self.imm_command_buffer, {})) or_return

    cmd := self.imm_command_buffer

    cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

    vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

    fn(self, cmd, data)

    vk_check(vk.EndCommandBuffer(cmd)) or_return

    cmd_info := command_buffer_submit_info(cmd)
    submit_info := submit_info(&cmd_info, nil, nil)

    vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit_info, self.imm_fence)) or_return
    vk_check(vk.WaitForFences(self.vk_device, 1,  &self.imm_fence, true, 9999999999)) or_return

    return true
}

engine_init_descriptors:: proc(self: ^Engine) -> (ok:bool) {
    sizes := []Pool_Size_Ratio{{.STORAGE_IMAGE, 1}}

    descriptor_allocator_init_pool(&self.global_descriptor_allocator, self.vk_device, 10, sizes) or_return
    deletion_queue_push(&self.main_deletion_queue, self.global_descriptor_allocator.pool)

    {
        builder: Descriptor_Layout_Builder
        descriptor_layout_builder_init(&builder, self.vk_device)
        descriptor_layout_builder_add_binding(&builder, 0, .STORAGE_IMAGE)
        self.draw_image_descriptor_layout = descriptor_layout_builder_build(&builder, {.COMPUTE}) or_return
    }
    deletion_queue_push(&self.main_deletion_queue, self.draw_image_descriptor_layout)

    self.draw_image_descriptors = descriptor_allocator_allocate(&self.global_descriptor_allocator, self.vk_device, &self.draw_image_descriptor_layout,) or_return
    
    img_info := vk.DescriptorImageInfo {
        imageLayout = .GENERAL,
        imageView = self.draw_image.image_view,
    }

    draw_image_write := vk.WriteDescriptorSet{
        sType = .WRITE_DESCRIPTOR_SET,
        dstBinding = 0,
        dstSet = self.draw_image_descriptors,
        descriptorCount = 1,
        descriptorType = .STORAGE_IMAGE,
        pImageInfo = &img_info,
    }

    vk.UpdateDescriptorSets(self.vk_device, 1, &draw_image_write, 0, nil)

    return true
}

engine_init_mesh_pipeline :: proc(self: ^Engine) -> (ok: bool) {

    mesh_frag_shader := create_shader_module(self.vk_device, #load("./../shaders/compiled/colored_triangle.frag.spv")) or_return
    defer vk.DestroyShaderModule(self.vk_device, mesh_frag_shader, nil)

    mesh_vertex_shader := create_shader_module(self.vk_device, #load("./../shaders/compiled/colored_triangle_mesh.vert.spv")) or_return
    defer vk.DestroyShaderModule(self.vk_device, mesh_vertex_shader, nil)
    
    buffer_range := vk.PushConstantRange {
        offset = 0,
        size = size_of(GPU_Draw_Push_Constants),
        stageFlags = {.VERTEX},
    }

    pipeline_layout_info := pipeline_layout_create_info()
    pipeline_layout_info.pPushConstantRanges = &buffer_range
    pipeline_layout_info.pushConstantRangeCount = 1
    vk_check(vk.CreatePipelineLayout(self.vk_device, &pipeline_layout_info, nil, &self.mesh_pipeline_layout,)) or_return

    deletion_queue_push(&self.main_deletion_queue, self.mesh_pipeline_layout)

    
    builder := pipeline_builder_create_default()

    builder.pipeline_layout = self.mesh_pipeline_layout

    pipeline_builder_set_shaders(&builder, mesh_vertex_shader, mesh_frag_shader)
    
    pipeline_builder_set_input_topology(&builder, .TRIANGLE_LIST)

    pipeline_builder_set_polygon_mode(&builder, .FILL)

    pipeline_builder_set_cull_mode(&builder, vk.CullModeFlags_NONE, .CLOCKWISE)

    pipeline_builder_set_multisampling_none(&builder)

    pipeline_builder_enable_blending_additive(&builder)

    pipeline_builder_enable_depth_test(&builder, true, .GREATER_OR_EQUAL)

    pipeline_builder_set_color_attachment_format(&builder, self.draw_image.image_format)
    pipeline_builder_set_depth_attachment_format(&builder, self.depth_image.image_format)

    self.mesh_pipeline = pipeline_builder_build(&builder, self.vk_device) or_return
    deletion_queue_push(&self.main_deletion_queue, self.mesh_pipeline)

    return true
}

engine_init_background_pipelines :: proc(self: ^Engine) -> (ok: bool) {

    GRADIENT_COLOR_SPV :: #load("./../shaders/compiled/gradient_color.comp.spv")
    gradient_color_shader := create_shader_module(self.vk_device, GRADIENT_COLOR_SPV) or_return
    defer vk.DestroyShaderModule(self.vk_device, gradient_color_shader, nil)


    SKY_SPV :: #load("./../shaders/compiled/sky.comp.spv")
    sky_shader := create_shader_module(self.vk_device, SKY_SPV) or_return
    defer vk.DestroyShaderModule(self.vk_device, sky_shader, nil)

    stage_info := vk.PipelineShaderStageCreateInfo {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.COMPUTE},
        module = gradient_color_shader,
        pName = "main",
    }

    compute_pipeline_create_info := vk.ComputePipelineCreateInfo {
        sType = .COMPUTE_PIPELINE_CREATE_INFO,
        layout = self.gradient_pipeline_layout,
        stage = stage_info,
    }

    gradient_color := Compute_Effect {
        layout = self.gradient_pipeline_layout,
        name = "Gradient Color",
        data = {data1 = {1, 0, 0, 1}, data2 = {0, 0, 1, 1}}
    }

    vk_check(vk.CreateComputePipelines(self.vk_device, 0, 1, &compute_pipeline_create_info, nil, &gradient_color.pipeline,),) or_return

    compute_pipeline_create_info.stage.module = sky_shader

    sky := Compute_Effect {
        layout = self.gradient_pipeline_layout,
        name = "Sky",
        data = {data1 = {0.1, 0.2, 0.4, 0.97}},
    }
    
    vk_check(vk.CreateComputePipelines(self.vk_device, 0, 1, &compute_pipeline_create_info, nil, &sky.pipeline),) or_return

    self.background_effects[.Gradient] = gradient_color
    self.background_effects[.Sky] = sky


    deletion_queue_push(&self.main_deletion_queue, self.gradient_pipeline_layout)
    deletion_queue_push(&self.main_deletion_queue, gradient_color.pipeline)
    deletion_queue_push(&self.main_deletion_queue, sky.pipeline)

    return true
}

engine_init_default_data :: proc(self: ^Engine) -> (ok: bool) {

    self.test_meshes = load_gltf_meshes(self, "build/assets/basicmesh.glb") or_return
    defer if !ok {
        destroy_mesh_assets(&self.test_meshes)
    }

    return true
}

engine_init_pipelines :: proc(self: ^Engine) -> (ok: bool) { 
    
    push_constant := vk.PushConstantRange {
        offset = 0,
        size = size_of(Compute_Push_Constants),
        stageFlags = {.COMPUTE}
    } 

    compute_layout := vk.PipelineLayoutCreateInfo {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        pSetLayouts = &self.draw_image_descriptor_layout,
        setLayoutCount = 1,
        pPushConstantRanges = &push_constant,
        pushConstantRangeCount = 1,
    }

    vk_check(vk.CreatePipelineLayout(self.vk_device, &compute_layout, nil, & self.gradient_pipeline_layout), "Failed to create pipeline layout") or_return
    log.debugf("---Background Pipelines")
    engine_init_background_pipelines(self) or_return
    log.debugf("---Mesh Pipelines")
    engine_init_mesh_pipeline(self) or_return

    return true
}

engine_init_imgui :: proc(self: ^Engine) -> (ok: bool) {
    im.CHECKVERSION()

   pool_sizes := []vk.DescriptorPoolSize {
        {.SAMPLER, 1000},
        {.COMBINED_IMAGE_SAMPLER, 1000},
        {.SAMPLED_IMAGE, 1000},
        {.STORAGE_IMAGE, 1000},
        {.UNIFORM_TEXEL_BUFFER, 1000},
        {.STORAGE_TEXEL_BUFFER, 1000},
        {.UNIFORM_BUFFER, 1000},
        {.STORAGE_BUFFER, 1000},
        {.UNIFORM_BUFFER_DYNAMIC, 1000},
        {.STORAGE_BUFFER_DYNAMIC, 1000},
        {.INPUT_ATTACHMENT, 1000},
    }
    pool_info := vk.DescriptorPoolCreateInfo {
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        flags = {.FREE_DESCRIPTOR_SET},
        maxSets = 1000,
        poolSizeCount = u32(len(pool_sizes)),
        pPoolSizes = raw_data(pool_sizes),
    }

    imgui_pool: vk.DescriptorPool
    vk_check(vk.CreateDescriptorPool(self.vk_device, &pool_info, nil, &imgui_pool)) or_return

    im.CreateContext()
    defer if !ok {im.DestroyContext()}

    im_glfw.InitForVulkan(self.window, install_callbacks = true) or_return
    defer if !ok {im_glfw.Shutdown()}

    pipeline_info := im_vk.PipelineInfo {
        PipelineRenderingCreateInfo = {
            sType = .PIPELINE_RENDERING_CREATE_INFO,
            colorAttachmentCount = 1,
            pColorAttachmentFormats = &self.swapchain_format,
        },
        MSAASamples = {._1},
    }

    init_info := im_vk.InitInfo {
        ApiVersion = self.vkb.instance.api_version,
        Instance = self.vk_instance,
        PhysicalDevice = self.vk_physical_device,
        Device = self.vk_device,
        Queue = self.graphics_queue,
        DescriptorPool = imgui_pool,
        MinImageCount = 3,
        ImageCount = 3,
        UseDynamicRendering = true,
        PipelineInfoMain = pipeline_info,
    }

    im_vk.LoadFunctions(self.vkb.instance.api_version, proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
        engine := cast(^Engine)user_data
        return vk.GetInstanceProcAddr(engine.vk_instance, function_name)
    }, self,) or_return

    im_vk.Init(&init_info) or_return
    defer if !ok {im_vk.Shutdown()}

    im_vk_shutdown :: proc() {
        im_vk.Shutdown()
   }

    im_glfw_shutdown :: proc() {
        im_glfw.Shutdown()
    }


    deletion_queue_push(&self.main_deletion_queue, imgui_pool)
    deletion_queue_push(&self.main_deletion_queue, im_vk_shutdown)
    deletion_queue_push(&self.main_deletion_queue, im_glfw_shutdown)

    return true
}


engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    ensure(vk.DeviceWaitIdle(self.vk_device) == .SUCCESS)

    for &frame in self.frames {
        vk.DestroyCommandPool(self.vk_device, frame.command_pool, nil)

        vk.DestroyFence(self.vk_device, frame.render_fence, nil)
        vk.DestroySemaphore(self.vk_device, frame.swapchain_semaphore, nil)

        deletion_queue_destroy(&frame.deletion_queue)
    }
    
    for &mesh in self.test_meshes {
        destroy_buffer(mesh.mesh_buffers.index_buffer)
        destroy_buffer(mesh.mesh_buffers.vertex_buffer)
    }
    destroy_mesh_assets(&self.test_meshes)

    deletion_queue_destroy(&self.main_deletion_queue)
    engine_destroy_swapchain(self)

    vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    destroy_device(&self.vk_context)

    destroy_physical_device(&self.vk_context.physical_device)
    destroy_instance(&self.vk_context)

    destroy_window(self.window)
}


