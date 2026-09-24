package astro

import "core:log"
import "base:runtime"

import "vendor:glfw"
import vk "vendor:vulkan"
import la "core:math/linalg"
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
    log.debugf("Initializing Input")
    input_init(&self.input, self.window)
    log.debugf("Initializing Scene")
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
    sizes := []Pool_Size_Ratio{
        {.STORAGE_IMAGE, 1},
        {.UNIFORM_BUFFER, 1},
        {.COMBINED_IMAGE_SAMPLER, 2},
    }

    descriptor_allocator_init_pool(&self.global_descriptor_allocator, self.vk_device, 10, sizes) or_return
    deletion_queue_push(&self.main_deletion_queue, self.global_descriptor_allocator.pool)

    {
        builder: Descriptor_Layout_Builder
        descriptor_layout_builder_init(&builder, self.vk_device)
        descriptor_layout_builder_add_binding(&builder, 0, .STORAGE_IMAGE)
        self.draw_image_descriptor_layout = descriptor_layout_builder_build(&builder, {.COMPUTE}) or_return

        deletion_queue_push(&self.main_deletion_queue, self.draw_image_descriptor_layout)
    }

    self.draw_image_descriptors = descriptor_allocator_allocate(
        &self.global_descriptor_allocator,
        self.vk_device,
        &self.draw_image_descriptor_layout,
        ) or_return
   
    writer: Descriptor_Writer
    descriptor_writer_init(&writer, self.vk_device)

    descriptor_writer_write_image(
        &writer,
        binding = 0,
        image = self.draw_image.image_view,
        sampler = 0,
        layout = .GENERAL,
        type = .STORAGE_IMAGE,)

    descriptor_writer_update_set(&writer, self.draw_image_descriptors)

    for &frame in self.frames {
        frame_sizes: Ratios
        append(&frame_sizes, Pool_Size_Ratio{.STORAGE_IMAGE, 3})
        append(&frame_sizes, Pool_Size_Ratio{.STORAGE_BUFFER, 3})
        append(&frame_sizes, Pool_Size_Ratio{.UNIFORM_BUFFER, 3})
        append(&frame_sizes, Pool_Size_Ratio{.COMBINED_IMAGE_SAMPLER, 4}) 

        descriptor_growable_init(
        &frame.frame_descriptors,
        self.vk_device,
        1000,
        frame_sizes[:],
        )

        deletion_queue_push(&self.main_deletion_queue, frame.frame_descriptors)
    }

    {
        builder: Descriptor_Layout_Builder
        descriptor_layout_builder_init(&builder, self.vk_device)
        descriptor_layout_builder_add_binding(&builder, 0, .UNIFORM_BUFFER)
        self.gpu_scene_data_descriptor_layout = descriptor_layout_builder_build(
            &builder, {.VERTEX, .FRAGMENT}
        ) or_return

        deletion_queue_push(&self.main_deletion_queue, self.gpu_scene_data_descriptor_layout)
    }

    {
        builder: Descriptor_Layout_Builder
        descriptor_layout_builder_init(&builder, self.vk_device)
        descriptor_layout_builder_add_binding(&builder, 0, .COMBINED_IMAGE_SAMPLER)
        self.single_image_descriptor_layout = descriptor_layout_builder_build(&builder, {.FRAGMENT}) or_return
        deletion_queue_push(&self.main_deletion_queue, self.single_image_descriptor_layout)
    }

    return true
}

engine_init_ocean_material :: proc(self: ^Engine) -> (ok: bool) {
    layout_builder: Descriptor_Layout_Builder
    descriptor_layout_builder_init(&layout_builder, self.vk_device)
    descriptor_layout_builder_add_binding(&layout_builder, 0, .COMBINED_IMAGE_SAMPLER)
    material_layout := descriptor_layout_builder_build(&layout_builder, {.FRAGMENT}) or_return

    config := Material_Shader_Config {
        vertex_shader = #load("./../shaders/compiled/sin_ocean.vert.spv"),
        fragment_shader = #load("./../shaders/compiled/tex_image.frag.spv"),
        material_layout = material_layout,
    }
    material_shader_build(&self.ocean_material, self, config) or_return
    deletion_queue_push(&self.main_deletion_queue, self.ocean_material)

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
    log.debugf("---Metalic Pipelines")
    metallic_roughness_build_pipeline(&self.metal_rough_material, self) or_return
    deletion_queue_push(&self.main_deletion_queue, self.metal_rough_material)
    log.debugf("---Ocean Material")
    engine_init_ocean_material(self) or_return


    return true
}


setup_imgui_style :: proc() {
    style := im.GetStyle()
    colors := &style.Colors

    // Base colors for a pleasant and modern dark theme with dark accents
    colors[im.Col.Text]                  = {0.92, 0.93, 0.94, 1.00}  // Light grey text for readability
    colors[im.Col.TextDisabled]          = {0.50, 0.52, 0.54, 1.00}  // Subtle grey for disabled text
    colors[im.Col.WindowBg]              = {0.14, 0.14, 0.16, 1.00}  // Dark background with a hint of blue
    colors[im.Col.ChildBg]               = {0.16, 0.16, 0.18, 1.00}  // Slightly lighter for child elements
    colors[im.Col.PopupBg]               = {0.18, 0.18, 0.20, 1.00}  // Popup background
    colors[im.Col.Border]                = {0.28, 0.29, 0.30, 0.60}  // Soft border color
    colors[im.Col.BorderShadow]          = {0.00, 0.00, 0.00, 0.00}  // No border shadow
    colors[im.Col.FrameBg]               = {0.20, 0.22, 0.24, 1.00}  // Frame background
    colors[im.Col.FrameBgHovered]        = {0.22, 0.24, 0.26, 1.00}  // Frame hover effect
    colors[im.Col.FrameBgActive]         = {0.24, 0.26, 0.28, 1.00}  // Active frame background
    colors[im.Col.TitleBg]               = {0.14, 0.14, 0.16, 1.00}  // Title background
    colors[im.Col.TitleBgActive]         = {0.16, 0.16, 0.18, 1.00}  // Active title background
    colors[im.Col.TitleBgCollapsed]      = {0.14, 0.14, 0.16, 1.00}  // Collapsed title background
    colors[im.Col.MenuBarBg]             = {0.20, 0.20, 0.22, 1.00}  // Menu bar background
    colors[im.Col.ScrollbarBg]           = {0.16, 0.16, 0.18, 1.00}  // Scrollbar background
    colors[im.Col.ScrollbarGrab]         = {0.24, 0.26, 0.28, 1.00}  // Dark accent for scrollbar grab
    colors[im.Col.ScrollbarGrabHovered]  = {0.28, 0.30, 0.32, 1.00}  // Scrollbar grab hover
    colors[im.Col.ScrollbarGrabActive]   = {0.32, 0.34, 0.36, 1.00}  // Scrollbar grab active
    colors[im.Col.CheckMark]             = {0.46, 0.56, 0.66, 1.00}  // Dark blue checkmark
    colors[im.Col.SliderGrab]            = {0.36, 0.46, 0.56, 1.00}  // Dark blue slider grab
    colors[im.Col.SliderGrabActive]      = {0.40, 0.50, 0.60, 1.00}  // Active slider grab
    colors[im.Col.Button]                = {0.24, 0.34, 0.44, 1.00}  // Dark blue button
    colors[im.Col.ButtonHovered]         = {0.28, 0.38, 0.48, 1.00}  // Button hover effect
    colors[im.Col.ButtonActive]          = {0.32, 0.42, 0.52, 1.00}  // Active button
    colors[im.Col.Header]                = {0.24, 0.34, 0.44, 1.00}  // Header color similar to button
    colors[im.Col.HeaderHovered]         = {0.28, 0.38, 0.48, 1.00}  // Header hover effect
    colors[im.Col.HeaderActive]          = {0.32, 0.42, 0.52, 1.00}  // Active header
    colors[im.Col.Separator]             = {0.28, 0.29, 0.30, 1.00}  // Separator color
    colors[im.Col.SeparatorHovered]      = {0.46, 0.56, 0.66, 1.00}  // Hover effect for separator
    colors[im.Col.SeparatorActive]       = {0.46, 0.56, 0.66, 1.00}  // Active separator
    colors[im.Col.ResizeGrip]            = {0.36, 0.46, 0.56, 1.00}  // Resize grip
    colors[im.Col.ResizeGripHovered]     = {0.40, 0.50, 0.60, 1.00}  // Hover effect for resize grip
    colors[im.Col.ResizeGripActive]      = {0.44, 0.54, 0.64, 1.00}  // Active resize grip
    colors[im.Col.Tab]                   = {0.20, 0.22, 0.24, 1.00}  // Inactive tab
    colors[im.Col.TabHovered]            = {0.28, 0.38, 0.48, 1.00}  // Hover effect for tab
    colors[im.Col.TabSelected]           = {0.24, 0.34, 0.44, 1.00}  // Active tab color (TabActive)
    colors[im.Col.TabDimmed]             = {0.20, 0.22, 0.24, 1.00}  // Unfocused tab (TabUnfocused)
    colors[im.Col.TabDimmedSelected]     = {0.24, 0.34, 0.44, 1.00}  // Active but unfocused tab (TabUnfocusedActive)
    colors[im.Col.DockingPreview]        = {0.24, 0.34, 0.44, 0.70}  // Docking preview
    colors[im.Col.DockingEmptyBg]        = {0.14, 0.14, 0.16, 1.00}  // Empty docking background
    colors[im.Col.PlotLines]             = {0.46, 0.56, 0.66, 1.00}  // Plot lines
    colors[im.Col.PlotLinesHovered]      = {0.46, 0.56, 0.66, 1.00}  // Hover effect for plot lines
    colors[im.Col.PlotHistogram]         = {0.36, 0.46, 0.56, 1.00}  // Histogram color
    colors[im.Col.PlotHistogramHovered]  = {0.40, 0.50, 0.60, 1.00}  // Hover effect for histogram
    colors[im.Col.TableHeaderBg]         = {0.20, 0.22, 0.24, 1.00}  // Table header background
    colors[im.Col.TableBorderStrong]     = {0.28, 0.29, 0.30, 1.00}  // Strong border for tables
    colors[im.Col.TableBorderLight]      = {0.24, 0.25, 0.26, 1.00}  // Light border for tables
    colors[im.Col.TableRowBg]            = {0.20, 0.22, 0.24, 1.00}  // Table row background
    colors[im.Col.TableRowBgAlt]         = {0.22, 0.24, 0.26, 1.00}  // Alternate row background
    colors[im.Col.TextSelectedBg]        = {0.24, 0.34, 0.44, 0.35}  // Selected text background
    colors[im.Col.DragDropTarget]        = {0.46, 0.56, 0.66, 0.90}  // Drag and drop target
    colors[im.Col.NavCursor]             = {0.46, 0.56, 0.66, 1.00}  // Navigation highlight (NavHighlight)
    colors[im.Col.NavWindowingHighlight] = {1.00, 1.00, 1.00, 0.70}  // Windowing highlight
    colors[im.Col.NavWindowingDimBg]     = {0.80, 0.80, 0.80, 0.20}  // Dim background for windowing
    colors[im.Col.ModalWindowDimBg]      = {0.80, 0.80, 0.80, 0.35}  // Dim background for modal windows

    // Style adjustments
    style.WindowRounding    = 8.0  // Softer rounded corners for windows
    style.FrameRounding     = 4.0  // Rounded corners for frames
    style.ScrollbarRounding = 6.0  // Rounded corners for scrollbars
    style.GrabRounding      = 4.0  // Rounded corners for grab elements
    style.ChildRounding     = 4.0  // Rounded corners for child windows

    style.WindowTitleAlign  = {0.50, 0.50}  // Centered window title
    style.WindowPadding     = {10.0, 10.0}  // Comfortable padding
    style.FramePadding      = {6.0, 4.0}    // Frame padding
    style.ItemSpacing       = {8.0, 8.0}    // Item spacing
    style.ItemInnerSpacing  = {8.0, 6.0}    // Inner item spacing
    style.IndentSpacing     = 22.0          // Indentation spacing

    style.ScrollbarSize     = 16.0  // Scrollbar size
    style.GrabMinSize       = 10.0  // Minimum grab size

    style.AntiAliasedLines  = true  // Enable anti-aliased lines
    style.AntiAliasedFill   = true  // Enable anti-aliased fill
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

    setup_imgui_style()

    return true
}


engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    ensure(vk.DeviceWaitIdle(self.vk_device) == .SUCCESS)

    for &mesh in self.scene.meshes {
        destroy_buffer(mesh.mesh_buffers.index_buffer)
        destroy_buffer(mesh.mesh_buffers.vertex_buffer)
    }
    destroy_mesh_assets(&self.scene.meshes)
    scene_destroy(&self.scene)
    delete(self.main_draw_context.opaque_surfaces)
    delete(self.name_for_node)

    for &frame in self.frames {
        vk.DestroyCommandPool(self.vk_device, frame.command_pool, nil)

        vk.DestroyFence(self.vk_device, frame.render_fence, nil)
        vk.DestroySemaphore(self.vk_device, frame.swapchain_semaphore, nil)

        deletion_queue_destroy(&frame.deletion_queue)
    }
    
    deletion_queue_destroy(&self.main_deletion_queue)
    engine_destroy_swapchain(self)

    vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    destroy_device(&self.vk_context)

    destroy_physical_device(&self.vk_context.physical_device)
    destroy_instance(&self.vk_context)

    destroy_window(self.window)
}


