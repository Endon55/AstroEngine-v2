package astro

import "core:log"
import la "core:math/linalg"

import "base:runtime"

import "vendor:glfw"
import vk "vendor:vulkan"

import "libs:vkb"
import vma "libs:vma"

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
    depth_image: Allocated_Image,
    draw_extent: vk.Extent2D,
    render_scale: f32,

    gradient_pipeline_layout: vk.PipelineLayout,
    background_effects: [Compute_Effect_Kind]Compute_Effect,
    current_background_effect: Compute_Effect_Kind,
    mesh_pipeline_layout: vk.PipelineLayout,
    mesh_pipeline: vk.Pipeline,
    test_meshes: Mesh_Asset_List,

    global_descriptor_allocator: Descriptor_Allocator,
    draw_image_descriptors: vk.DescriptorSet,
    draw_image_descriptor_layout: vk.DescriptorSetLayout,

    imm_fence: vk.Fence,
    imm_command_buffer: vk.CommandBuffer,
    imm_command_pool: vk.CommandPool,

    scene_data: GPU_Scene_Data,
    gpu_scene_data_descriptor_layout: vk.DescriptorSetLayout,

    white_image: Allocated_Image,
    black_image: Allocated_Image,
    grey_image: Allocated_Image,
    error_checkerboard_image: Allocated_Image,
    default_sampler_linear: vk.Sampler,
    default_sampler_nearest: vk.Sampler,
    single_image_descriptor_layout: vk.DescriptorSetLayout,
}

Frame_Data :: struct {
    command_pool: vk.CommandPool,
    main_command_buffer : vk.CommandBuffer,
    swapchain_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
    deletion_queue: Deletion_Queue,
    frame_descriptors: Descriptor_Allocator_Growable,
}

GPU_Scene_Data :: struct {
    view: la.Matrix4x4f32,
    proj: la.Matrix4x4f32,
    viewproj: la.Matrix4x4f32,
    ambient_color: la.Vector4f32,
    sunlight_direction: la.Vector4f32,
    sunlight_color: la.Vector4f32,
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
//The modulous here isn't that expensive since FRAME_OVERLAP is a power of 2
engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
    return &self.frames[self.frame_number % FRAME_OVERLAP]
}
@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
    monitor_info := get_primary_monitor_info()
    t: Timer
    timer_init(&t, monitor_info.refresh_rate)

    log.info("Entering main loop...")
    for !glfw.WindowShouldClose(self.window) {
        glfw.PollEvents()

        if self.stop_rendering {
            glfw.WaitEvents()
            timer_init(&t, monitor_info.refresh_rate)
            continue
        }

        timer_tick(&t)
        engine_ui_definition(self)
        engine_draw(self) or_return

        when ODIN_DEBUG {
            if timer_check_fps_updated(t) {
                window_update_title_with_fps(self.window, TITLE, timer_get_fps(t))
            }
        }
    }

    log.info("Exiting...")
    return true
}

