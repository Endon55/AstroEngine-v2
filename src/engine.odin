package astro

import "core:log"
import "base:runtime"
import "core:math"
import la "core:math/linalg"

import "vendor:glfw"
import vk "vendor:vulkan"

import "libs:vkb"
import vma "libs:vma"
import im "libs:imgui"
import im_glfw "libs:imgui/backends/glfw"
import im_vk "libs:imgui/backends/vulkan"


TITLE :: "Astro Engine v2"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678}

FRAME_OVERLAP :: 2


Engine::struct {
    window: glfw.WindowHandle,
    window_extent: vk.Extent2D,
    is_initialized: bool,
    stop_rendering: bool,

    //device
    vk_instance: vk.Instance,
    vk_physical_device: vk.PhysicalDevice,
    vk_surface: vk.SurfaceKHR,
    vk_device: vk.Device,
    

    vkb: struct{
        instance: vkb.Instance,
        physical_device: vkb.Physical_Device,
        device: vkb.Device,
        swapchain: vkb.Swapchain,
    },
    vk_context: Vulkan_Creation_Context,

    vk_swapchain: vk.SwapchainKHR,
    swapchain_format: vk.Format,
    swapchain_extent: vk.Extent2D,
    swapchain_images: []vk.Image,
    swapchain_image_views: []vk.ImageView,
    swapchain_image_semaphores: []vk.Semaphore,

    frames: [FRAME_OVERLAP] Frame_Data,
    frame_number: int,
    graphics_queue: vk.Queue,
    graphics_queue_family: u32,


    vma_allocator: vma.Allocator,
    main_deletion_queue: Deletion_Queue,

    draw_image: Allocated_Image,
    draw_extent: vk.Extent2D,

    gradient_pipeline_layout: vk.PipelineLayout,
    background_effects: [Compute_Effect_Kind]Compute_Effect,
    current_background_effect: Compute_Effect_Kind,
    triangle_pipeline_layout: vk.PipelineLayout,
    triangle_pipeline: vk.Pipeline,
    mesh_pipeline_layout: vk.PipelineLayout,
    mesh_pipeline: vk.Pipeline,
    rectangle: GPU_Mesh_Buffers,

    global_descriptor_allocator: Descriptor_Allocator,
    draw_image_descriptors: vk.DescriptorSet,
    draw_image_descriptor_layout: vk.DescriptorSetLayout,

    imm_fence: vk.Fence,
    imm_command_buffer: vk.CommandBuffer,
    imm_command_pool: vk.CommandPool,
}

Frame_Data :: struct {
    command_pool: vk.CommandPool,
    main_command_buffer : vk.CommandBuffer,
    swapchain_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
    deletion_queue: Deletion_Queue,
}

Compute_Push_Constants :: struct {
    data1: [4]f32,
    data2: [4]f32,
    data3: [4]f32,
    data4: [4]f32,
}

Compute_Effect_Kind :: enum {
    Gradient,
    Sky,
}

Compute_Effect :: struct {
    name:     cstring,
    pipeline: vk.Pipeline,
    layout:   vk.PipelineLayout,
    data:     Compute_Push_Constants,
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

engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool){

    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    
    features:= Vulkan_Feature_Requirements {
        device_features_11 = {
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
    create_vk_instance(&self.vk_context, features, self) or_return

    self.vk_instance = self.vk_context.vk_instance
    vk_check(glfw.CreateWindowSurface(self.vk_instance, self.window, self.vk_context.allocation_callbacks , &self.vk_surface),) or_return

    defer if !ok {
        vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    }

    select_vk_physical_device(&self.vk_context, self.vk_surface) or_return
    create_vk_logical_device(&self.vk_context) or_return

    self.vk_physical_device = self.vk_context.physical_device.vk_physical_device
    self.vk_device = self.vk_context.vk_device


    // log.debugf("Creating Vulkan Instance")
    // instance_builder: vkb.Instance_Builder
    // vkb.instance_builder_init(&instance_builder, ta)
    //
    // vkb.instance_builder_set_app_name(&instance_builder, "Astro2")
    // vkb.instance_builder_require_api_version(&instance_builder, vk.API_VERSION_1_3)
    //
    // when ODIN_DEBUG {
    //     log.debugf("Adding debug callback to  Vulkan")
    //     vkb.instance_builder_request_validation_layers(&instance_builder)
    //
    //     default_debug_callback :: proc "system" (message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    //         p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: rawptr) -> b32 {
    //
    //         context = runtime.default_context()
    //         context.logger = g_logger
    //
    //         if .WARNING in message_severity {
    //             log.warnf("[%v]: %s", message_types, p_callback_data.pMessage)
    //         } else if .ERROR in message_severity {
    //             log.errorf("[%v]: %s", message_types, p_callback_data.pMessage)
    //             //runtime.debug_trap()
    //         } else {
    //             log.infof("[%v]: %s", message_types, p_callback_data.pMessage)
    //         }
    //
    //         return false
    //     }
        // vkb.instance_builder_set_debug_callback(&instance_builder, default_debug_callback)
        // vkb.instance_builder_set_debug_callback_user_data_pointer(&instance_builder, self)

    //     VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"
    //
    //     info: vkb.System_Info
    //     info_err := vkb.system_info_init(&info, allocator = ta)
    //     if info_err != nil {
    //         log.errorf("Failed to get system info: %#v", info_err)
    //     }
    //
    //     if vkb.system_info_is_layer_available(info, VK_LAYER_LUNARG_MONITOR) {
    //         when ODIN_OS == .Windows || ODIN_OS == .Linux {
    //             vkb.instance_builder_enable_layer(&instance_builder, VK_LAYER_LUNARG_MONITOR)
    //         }
    //     }
    //}
    // vkb_instance_err := vkb.instance_builder_build(&instance_builder, &self.vkb.instance)
    // if vkb_instance_err != nil {
    //     log.errorf("Failed to build instance: %#v", vkb_instance_err)
    //     return
    // }
    // defer if !ok {
    //     vkb.destroy_instance(&self.vkb.instance)
     // }
    //
    // self.vk_instance = self.vkb.instance.vk_instance
    //

    // log.debugf("Creating window surface")
    // vk_check(glfw.CreateWindowSurface(self.vk_instance, self.window, nil, &self.vk_surface),) or_return
    // defer if !ok {
    //     vkb.destroy_surface(&self.vkb.instance, self.vk_surface)
    // }
    //
    // features_11 := vk.PhysicalDeviceVulkan11Features {
    //     shaderDrawParameters = true,
    // }
    // features_12 := vk.PhysicalDeviceVulkan12Features {
    //     sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
    //     bufferDeviceAddress = true,
    //     descriptorIndexing = true,
    //     vulkanMemoryModelAvailabilityVisibilityChains = false,
    // }
    // features_13 := vk.PhysicalDeviceVulkan13Features {
    //     dynamicRendering = true,
    //     synchronization2 = true,
    // }
    // log.debugf("Selecting physical device")
    // selector: vkb.Physical_Device_Selector
    // vkb.physical_device_selector_init(&selector, self.vkb.instance, ta)
    //
    // vkb.physical_device_selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
    // // vkb.physical_device_selector_add_required_extension_features(&selector, features_12)
    // vkb.physical_device_selector_set_required_features_13(&selector, features_13)
    // vkb.physical_device_selector_set_required_features_12(&selector, features_12)
    // vkb.physical_device_selector_set_required_features_11(&selector, features_11)
    // vkb.physical_device_selector_set_surface(&selector, self.vk_surface)
    //
    //
    // vkb_physical_device_err := vkb.physical_device_selector_select(&selector, &self.vkb.physical_device)
    // if vkb_physical_device_err != nil {
    //     log.errorf("Failed to select physical device: %#v", vkb_physical_device_err)
    //     return
    // }
    // defer if !ok {
    //     vkb.destroy_physical_device(&self.vkb.physical_device)
    // }
    //
    // self.vk_physical_device = self.vkb.physical_device.vk_physical_device
    // device_properties := vk.PhysicalDeviceProperties2{
    //     sType = .PHYSICAL_DEVICE_PROPERTIES_2
    // }
    // // self.vkb.physical_device.vulkan_1_2_features.vulkanMemoryModelAvailabilityVisibilityChains = false
    // vk.GetPhysicalDeviceProperties2(self.vk_physical_device, &device_properties)
    // str := string(cstring(&device_properties.properties.deviceName[0]))
    // log.debugf("Physical Device Name: %v", str)
    //
    // log.debugf("Building vk.device builder")
    // device_builder: vkb.Device_Builder
    // vkb.device_builder_init(&device_builder, ta)
    // log.debugf("Building vk.device")
    // // vkb.device_builder_add_pnext(&device_builder, &features_12)
    // log.debugf("Extensions: %#v", &self.vkb.physical_device.extended_features_chain)
    //
    // vkb_device_err := vkb.device_builder_build(&device_builder, &self.vkb.physical_device, &self.vkb.device)
    // if vkb_device_err != nil {
    //     log.errorf("Failed to get logical device: %#v", vkb_device_err)
    //     return
    // }
    // defer if !ok {
    //     vkb.destroy_device(&self.vkb.device)    
    // }
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

    //
    // runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    //
    // self.swapchain_format = .B8G8R8A8_UNORM
    //
    // builder: vkb.Swapchain_Builder
    // vkb.swapchain_builder_init(&builder, self. vkb.device, ta)
    //
    // vkb.swapchain_builder_set_desired_format(&builder, {format = self.swapchain_format, colorSpace = .SRGB_NONLINEAR})
    // //FIFO turns on vsync 
    // vkb.swapchain_builder_set_desired_present_mode(&builder, .FIFO)
    // vkb.swapchain_builder_set_desired_present_mode(&builder, .IMMEDIATE)
    // vkb.swapchain_builder_set_desired_present_mode(&builder, .MAILBOX)
    // vkb.swapchain_builder_set_desired_extent(&builder, extent.width, extent.height)
    // vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})
    //
    // swapchain_err := vkb.swapchain_builder_build(&builder, &self.vkb.swapchain)
    //
    // if swapchain_err != nil {
    //     log.errorf("Failed to build swapchain: %#v", swapchain_err)
    //     return
    // }
    

    create_vk_swapchain(&self.vk_context.swapchain_context, extent.width, extent.height)

    self.vk_swapchain = self.vk_context.swapchain_context.vk_swapchain
    self.swapchain_extent = self.vk_context.swapchain_context.vk_extent

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

    graphics_queue_family, graphics_queue_family_err := device_get_universal_queue__index(self.vk_context)
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
    vkb.destroy_swapchain(&self.vkb.swapchain)
    vkb.swapchain_destroy_image_views(self.vkb.swapchain, self.swapchain_image_views)

    for semaphore in self.swapchain_image_semaphores {
        vk.DestroySemaphore(self.vk_device, semaphore, nil)
    }
    delete(self.swapchain_image_semaphores)
    delete(self.swapchain_image_views)
    delete(self.swapchain_images)
   
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool){
    engine_create_swapchain(self, self.window_extent) or_return
    draw_image_extent := vk.Extent3D {
        width = self.window_extent.width,
        height = self.window_extent.height,
        depth = 1,
    }
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

    pipeline_builder_disable_blending(&builder)

    pipeline_builder_disable_depth_test(&builder)

    pipeline_builder_set_color_attachment_format(&builder, self.draw_image.image_format)
    pipeline_builder_set_depth_attachment_format(&builder, .UNDEFINED)

    self.mesh_pipeline = pipeline_builder_build(&builder, self.vk_device) or_return
    deletion_queue_push(&self.main_deletion_queue, self.mesh_pipeline)

    return true
}
engine_init_triangle_pipeline :: proc(self: ^Engine) -> (ok: bool) {

    triangle_frag_shader := create_shader_module(self.vk_device, #load("./../shaders/compiled/colored_triangle.frag.spv")) or_return
    defer vk.DestroyShaderModule(self.vk_device, triangle_frag_shader, nil)

    triangle_vert_shader := create_shader_module(self.vk_device, #load("./../shaders/compiled/colored_triangle.vert.spv")) or_return
    defer vk.DestroyShaderModule(self.vk_device, triangle_vert_shader, nil)

    pipeline_layout_info := pipeline_layout_create_info()
    vk_check(vk.CreatePipelineLayout(self.vk_device, &pipeline_layout_info, nil, &self.triangle_pipeline_layout,)) or_return

    deletion_queue_push(&self.main_deletion_queue, self.triangle_pipeline_layout)

    
    builder := pipeline_builder_create_default()

    builder.pipeline_layout = self.triangle_pipeline_layout

    pipeline_builder_set_shaders(&builder, triangle_vert_shader, triangle_frag_shader)

    
    pipeline_builder_set_input_topology(&builder, .TRIANGLE_LIST)

    pipeline_builder_set_polygon_mode(&builder, .FILL)

    pipeline_builder_set_cull_mode(&builder, vk.CullModeFlags_NONE, .CLOCKWISE)

    pipeline_builder_set_multisampling_none(&builder)

    pipeline_builder_disable_blending(&builder)

    pipeline_builder_disable_depth_test(&builder)

    pipeline_builder_set_color_attachment_format(&builder, self.draw_image.image_format)
    pipeline_builder_set_depth_attachment_format(&builder, .UNDEFINED)

    self.triangle_pipeline = pipeline_builder_build(&builder, self.vk_device) or_return
    deletion_queue_push(&self.main_deletion_queue, self.triangle_pipeline)

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
    rect_vertices := [4]Vertex {
        { position = {0.5,-0.5, 0},  color = { 0,0, 0.0, 1.0 }},
        { position = {0.5,0.5, 0},   color = { 0.5, 0.5, 0.5 ,1.0 }},
        { position = {-0.5,-0.5, 0}, color = { 1,0, 0.0, 1.0 }},
        { position = {-0.5,0.5, 0},  color = { 0.0, 1.0, 0.0, 1.0 }},
    }

    rect_indices := [6]u32 {
        0, 1, 2,
        2, 1, 3,
    }
    // odinfmt: enable

    self.rectangle = upload_mesh(self, rect_indices[:], rect_vertices[:]) or_return

    // Delete the rectangle data on engine shutdown
    deletion_queue_push(&self.main_deletion_queue, self.rectangle.index_buffer)
    deletion_queue_push(&self.main_deletion_queue, self.rectangle.vertex_buffer)

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
    log.debugf("---Triangle Pipelines")
    engine_init_triangle_pipeline(self) or_return
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

//The modulous here isn't that expensive since FRAME_OVERLAP is a power of 2
engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
    return &self.frames[self.frame_number % FRAME_OVERLAP]
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
    
    deletion_queue_destroy(&self.main_deletion_queue)
    engine_destroy_swapchain(self)

    vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    vkb.destroy_device(&self.vkb.device)

    vkb.destroy_physical_device(&self.vkb.physical_device)
    vkb.destroy_instance(&self.vkb.instance)

    destroy_window(self.window)
}

engine_draw_geometry :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    color_attachment := attachment_info(self.draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
    render_info := rendering_info(self.draw_extent, &color_attachment, nil)
    vk.CmdBeginRendering(cmd, &render_info)


    viewport := vk.Viewport {
        x = 0,
        y = 0,
        width = f32(self.draw_extent.width),
        height = f32(self.draw_extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }

    vk.CmdSetViewport(cmd, 0, 1, &viewport)

    scissor := vk.Rect2D {
        offset = {x = 0, y = 0},
        extent = {width = self.draw_extent.width, height = self.draw_extent.height},
    }
    vk.CmdSetScissor(cmd, 0, 1, & scissor)

    vk.CmdBindPipeline(cmd, .GRAPHICS, self.triangle_pipeline)
    vk.CmdDraw(cmd, 3, 1, 0, 0)

    vk.CmdBindPipeline(cmd, .GRAPHICS, self.mesh_pipeline)

    push_constants := GPU_Draw_Push_Constants {
        world_matrix = la.MATRIX4F32_IDENTITY,
        vertex_buffer = self.rectangle.vertex_buffer_address,
    }

    vk.CmdPushConstants(cmd, self.mesh_pipeline_layout, {.VERTEX}, 0, size_of(GPU_Draw_Push_Constants), &push_constants,)

    vk.CmdBindIndexBuffer(cmd, self.rectangle.index_buffer.buffer, 0, .UINT32)
    vk.CmdDrawIndexed(cmd, 6, 1, 0, 0, 0)

    vk.CmdEndRendering(cmd)

    return true
}

@(require_results)
engine_draw_background :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    effect := &self.background_effects[self.current_background_effect]
   vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)
   vk.CmdBindDescriptorSets(cmd, .COMPUTE, self.gradient_pipeline_layout, 0, 1, &self.draw_image_descriptors, 0, nil,)

    vk.CmdPushConstants(cmd, self.gradient_pipeline_layout, {.COMPUTE}, 0, size_of(Compute_Push_Constants), &effect.data,)
    vk.CmdDispatch(cmd, 
        u32(math.ceil_f32(f32(self.draw_extent.width) / 16.0)), 
        u32(math.ceil_f32(f32(self.draw_extent.height) / 16.0)),
        1,)

 return true
}

engine_draw_imgui :: proc(self: ^Engine, cmd: vk.CommandBuffer, target_view: vk.ImageView,) -> (ok: bool,) {

    color_attachment := attachment_info(target_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
    render_info := rendering_info(self.swapchain_extent, &color_attachment, nil)

    vk.CmdBeginRendering(cmd, &render_info)
    im_vk.RenderDrawData(im.GetDrawData(), cmd)

    vk.CmdEndRendering(cmd)

    return
}

@(require_results)
engine_draw ::proc(self: ^Engine) -> (ok: bool){

    frame := engine_get_current_frame(self)
    //waits for the gpu to finish working
    vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return
    vk_check(vk.ResetFences(self.vk_device, 1, &frame.render_fence)) or_return

    deletion_queue_flush(&frame.deletion_queue)

    swapchain_image_index: u32 = ---
    vk_check(vk.AcquireNextImageKHR(self.vk_device, self.vk_swapchain, 1e9, frame.swapchain_semaphore, 0, &swapchain_image_index,),) or_return

    cmd := frame.main_command_buffer

    vk_check(vk.ResetCommandBuffer(cmd, {})) or_return
    
    cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})


    self.draw_extent.width = self.draw_image.image_extent.width
    self.draw_extent.height = self.draw_image.image_extent.height


    vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return
    
    transition_image(cmd, self.draw_image.image, .UNDEFINED, .GENERAL)

    engine_draw_background(self, cmd) or_return


    transition_image(cmd, self.draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)

    engine_draw_geometry(self, cmd) or_return
    
    transition_image(cmd, self.draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)

    transition_image(cmd, self.swapchain_images[swapchain_image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

    copy_image_to_image(cmd, self.draw_image.image, self.swapchain_images[swapchain_image_index], self.draw_extent, self.swapchain_extent)

    transition_image(cmd, self.swapchain_images[swapchain_image_index], .TRANSFER_DST_OPTIMAL, .COLOR_ATTACHMENT_OPTIMAL,)
    
    engine_draw_imgui(self, cmd, self.swapchain_image_views[swapchain_image_index])

    transition_image(cmd, self.swapchain_images[swapchain_image_index], .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR,)

    vk_check(vk.EndCommandBuffer(cmd)) or_return

    ready_for_present_semaphore := self.swapchain_image_semaphores[swapchain_image_index]

    cmd_info := command_buffer_submit_info(cmd)
    signal_info := semaphore_submit_info({.ALL_GRAPHICS}, ready_for_present_semaphore)
    wait_info := semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchain_semaphore)
    
    submit := submit_info(&cmd_info, &signal_info, &wait_info)

    vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) or_return


    present_info := vk.PresentInfoKHR {
        sType = .PRESENT_INFO_KHR,
        pSwapchains = &self.vk_swapchain,
        swapchainCount = 1,
        pWaitSemaphores = &ready_for_present_semaphore,
        waitSemaphoreCount = 1,
        pImageIndices = &swapchain_image_index,
    }
    vk_check(vk.QueuePresentKHR(self.graphics_queue, &present_info)) or_return

    self.frame_number += 1

    return true
}

engine_ui_definition :: proc(self: ^Engine) {

    im_glfw.NewFrame()
    im_vk.NewFrame()
    im.NewFrame()

    if im.Begin("Background", nil, {.AlwaysAutoResize}) {
        selected := &self.background_effects[self.current_background_effect]

        im.Text("Selected effect : %s", selected.name)

        @(static) current_background_effect: i32
        current_background_effect = i32(self.current_background_effect)

        // If the combo is opened and an item is selected, update the current effect
        if im.BeginCombo("Effect", selected.name) {
            for effect, i in self.background_effects {
                is_selected := i32(i) == current_background_effect
                if im.Selectable(effect.name, is_selected) {
                    current_background_effect = i32(i)
                    self.current_background_effect = Compute_Effect_Kind(
                        current_background_effect,
                    )
                }

                // Set initial focus when the currently selected item becomes visible
                if is_selected {
                    im.SetItemDefaultFocus()
                }
            }
            im.EndCombo()
        }

        im.InputFloat4("data1", &selected.data.data1)
        im.InputFloat4("data2", &selected.data.data2)
        im.InputFloat4("data3", &selected.data.data3)
        im.InputFloat4("data4", &selected.data.data4)

    }
    im.End() 
    im.Render()

}


@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
    // monitor_info := get_primary_monitor_info()
    // t: Timer
    // timer_init(&t, monitor_info.refresh_rate)
    //
    log.info("Entering main loop...")
    for !glfw.WindowShouldClose(self.window) {
        glfw.PollEvents()
        //
        // if self.stop_rendering {
        //     glfw.WaitEvents()
        //     timer_init(&t, monitor_info.refresh_rate)
        //     continue
        // }
        //
        // timer_tick(&t)
        // engine_ui_definition(self)
        // engine_draw(self) or_return
        //
        // when ODIN_DEBUG {
        //     if timer_check_fps_updated(t) {
        //         window_update_title_with_fps(self.window, TITLE, timer_get_fps(t))
        //     }
        // }
    }

    log.info("Exiting...")
    return true
}

