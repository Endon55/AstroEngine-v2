package astro

import "core:log"
import la "core:math/linalg"

import "base:runtime"

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
    depth_image: Allocated_Image,
    draw_extent: vk.Extent2D,
    render_scale: f32,

    gradient_pipeline_layout: vk.PipelineLayout,
    background_effects: [Compute_Effect_Kind]Compute_Effect,
    current_background_effect: Compute_Effect_Kind,
    mesh_pipeline_layout: vk.PipelineLayout,
    mesh_pipeline: vk.Pipeline,

    global_descriptor_allocator: Descriptor_Allocator,
    draw_image_descriptors: vk.DescriptorSet,
    draw_image_descriptor_layout: vk.DescriptorSetLayout,

    imm_fence: vk.Fence,
    imm_command_buffer: vk.CommandBuffer,
    imm_command_pool: vk.CommandPool,


    white_image: Allocated_Image,
    black_image: Allocated_Image,
    grey_image: Allocated_Image,
    error_checkerboard_image: Allocated_Image,
    default_sampler_linear: vk.Sampler,
    default_sampler_nearest: vk.Sampler,
    single_image_descriptor_layout: vk.DescriptorSetLayout,

    default_material_data: Material_Instance,
    metal_rough_material: Metallic_Roughness,

    gpu_scene_data_descriptor_layout: vk.DescriptorSetLayout,

    main_draw_context: Draw_Context,
    name_for_node: map[string]u32,
    scene: Scene,
    scene_data: GPU_Scene_Data,

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

engine_update_scene :: proc(self: ^Engine) {
    clear(&self.main_draw_context.opaque_surfaces)

    for &hierarchy, i in self.scene.hierarchy {
        if hierarchy.parent == -1 {
            scene_draw_node(&self.scene, i, &self.main_draw_context)
        }
    }
    aspect := f32(self.window_extent.width) / f32(self.window_extent.height)

    self.scene_data.view = la.matrix4_translate_f32({0, 0, -5})
    self.scene_data.proj = matrix4_perspective_reverse_z_f32(
        f32(la.to_radians(70.0)),
        aspect,
        0.1,
        true,
    )
    self.scene_data.viewproj = la.matrix_mul(self.scene_data.proj, self.scene_data.view)
    self.scene_data.ambient_color = {0.1, 0.1, 0.1, 0.1}
    self.scene_data.sunlight_color = {1.0, 1.0, 1.0, 1.0}
    self.scene_data.sunlight_direction = {0, 1, 0.5, 1.0}
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

engine_ui_definition :: proc(self: ^Engine) {
    // ImGUi new frame
    im_glfw.NewFrame()
    im_vk.NewFrame()
    im.NewFrame()

    v := im.GetMainViewport()
    im.SetNextWindowPos({10, 10})
    im.SetNextWindowSize({250, v.WorkSize.y - 20})
    im.Begin("Hierarchy", nil, {.NoFocusOnAppearing, .NoCollapse, .NoResize})
    @(static) selected_node: i32 = -1
    for &hierarchy, i in self.scene.hierarchy {
        if hierarchy.parent == -1 {
            render_scene_tree_ui(&self.scene, i, &selected_node)
        }
    }
    im.End()

    if im.Begin("Background", nil, {.AlwaysAutoResize}) {
        im.SliderFloat("Render scale", &self.render_scale, 0.3, 1.0)

        selected := &self.background_effects[self.current_background_effect]

        im.Text("Selected effect: %s", selected.name)

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


render_scene_tree_ui :: proc(scene: ^Scene, #any_int node: i32, selected_node: ^i32) -> i32 {
    name := scene_get_node_name(scene, node)
    label := len(name) == 0 ? "NO NODE" : name
    is_leaf := scene.hierarchy[node].first_child < 0
    flags: im.TreeNodeFlags = is_leaf ? {.Leaf, .Bullet} : {}

    if node == selected_node^ {
        flags += {.Selected}
    }

    // Make the node span the entire width
    flags += {.SpanFullWidth, .FramePadding}

    is_opened := im.TreeNodeExPtr(
        &scene.hierarchy[node], flags, "%s", cstring(raw_data(label)))

    // Check for clicks in the entire row area
    was_clicked := im.IsItemClicked()

    im.PushIDInt(node)
    {
        if was_clicked {
            log.debugf("Selected node: %d (%s)", node, label)
            selected_node^ = node
        }

        if is_opened {
            for ch := scene.hierarchy[node].first_child;
                ch != -1;
                ch = scene.hierarchy[ch].next_sibling {
                if sub_node := render_scene_tree_ui(scene, ch, selected_node); sub_node > -1 {
                    selected_node^ = sub_node
                }
            }
            im.TreePop()
        }
    }
    im.PopID()

    return selected_node^
}

