package astro

import "core:log"
import "core:math"
import la "core:math/linalg"

import vk "vendor:vulkan"
import im "libs:imgui"
import im_glfw "libs:imgui/backends/glfw"
import im_vk "libs:imgui/backends/vulkan"


engine_draw_geometry :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    frame := engine_get_current_frame(self)

    // Game draw records barriers/compute, which are illegal inside dynamic rendering.
    game_manager_game_draw(&self.game_manager, &self.scene, self, cmd)

    color_attachment := attachment_info(self.draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
    depth_attachment := depth_attachment_info(self.depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

    render_info := rendering_info(self.draw_extent, &color_attachment, &depth_attachment)
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

    gpu_scene_data_buffer := create_buffer(self, size_of(GPU_Scene_Data), {.UNIFORM_BUFFER}, .CPU_TO_GPU) or_return

    deletion_queue_push(&frame.deletion_queue, gpu_scene_data_buffer)

    scene_uniform_data := cast(^GPU_Scene_Data)gpu_scene_data_buffer.info.pMappedData
    scene_uniform_data^ = self.scene_data

    global_descriptor := descriptor_growable_allocate(&frame.frame_descriptors, &self.gpu_scene_data_descriptor_layout,) or_return

    writer: Descriptor_Writer
    descriptor_writer_init(&writer, self.vk_device)
    descriptor_writer_write_buffer(&writer,
        binding = 0,
        buffer = gpu_scene_data_buffer.buffer,
        size = size_of(GPU_Scene_Data),
        offset = 0,
        type = .UNIFORM_BUFFER)
    descriptor_writer_update_set(&writer, global_descriptor)
    for &draw in self.main_draw_context.opaque_surfaces {
        material := &self.scene.materials[draw.material]

        vk.CmdBindPipeline(cmd, .GRAPHICS, material.pipeline.pipeline)
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            material.pipeline.layout,
            0,
            1,
            &global_descriptor,
            0,
            nil, 
        )
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            material.pipeline.layout,
            1,
            1,
            &material.material_set,
            0,
            nil,
        )
        
        vk.CmdBindIndexBuffer(cmd, draw.index_buffer, 0, .UINT32)

        push_constants := GPU_Draw_Push_Constants {
            vertex_buffer = draw.vertex_buffer_address,
            world_matrix = draw.transform,
        }

        vk.CmdPushConstants(
            cmd, 
            material.pipeline.layout, 
            {.VERTEX}, 
            0, 
            size_of(GPU_Draw_Push_Constants), 
            &push_constants,
        )

        vk.CmdDrawIndexed(cmd, draw.index_count, 1, draw.first_index, 0, 0)
    }

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
    engine_update_scene(self)
    frame := engine_get_current_frame(self)
    //waits for the gpu to finish working
    vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return
    vk_check(vk.ResetFences(self.vk_device, 1, &frame.render_fence)) or_return

    deletion_queue_flush(&frame.deletion_queue)
    descriptor_growable_clear_pools(&frame.frame_descriptors)

    swapchain_image_index: u32 = ---
    result := vk.AcquireNextImageKHR(self.vk_device, self.vk_swapchain, 1e9, frame.swapchain_semaphore, 0, &swapchain_image_index,)

    if result != .ERROR_OUT_OF_DATE_KHR && result != .SUBOPTIMAL_KHR {
        vk_check(result) or_return
    }

    cmd := frame.main_command_buffer

    vk_check(vk.ResetCommandBuffer(cmd, {})) or_return
    
    cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

    self.draw_extent = {
        width = u32(f32(min(self.swapchain_extent.width, self.draw_image.image_extent.width)) * self.render_scale),
        height = u32(f32(min(self.swapchain_extent.height, self.draw_image.image_extent.height)) * self.render_scale),
    }

    vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return
    /*
        This whole section can be difficult to understand but the basic 'gist is that our image buffers contain garbage from the prvious frames. So transitioning them is more like re-initializing them to the state we need. During the lifetime of the frame the GPU is doing crazy bullshit to optimize the hell out out of the data which by the next frame leaves the buffers in an undefined state.
    */
    
    
    transition_image(cmd, self.draw_image.image, .UNDEFINED, .GENERAL)

    engine_draw_background(self, cmd) or_return
    //
    // ocean_sim := &self.scene.ocean.sim_data
    // transition_image(cmd, ocean_sim.jonswap_texture.image, .UNDEFINED, .GENERAL)
    // vk.CmdBindPipeline(cmd, .COMPUTE, ocean_sim.jonswap_pipeline)
    // vk.CmdBindDescriptorSets(
    //     cmd,
    //     .COMPUTE,
    //     ocean_sim.jonswap_layout,
    //     0,
    //     1,
    //     &ocean_sim.jonswap_descriptor,
    //     0,
    //     nil,
    // )
    // vk.CmdPushConstants(
    //     cmd,
    //     ocean_sim.jonswap_layout,
    //     {.COMPUTE},
    //     0,
    //     size_of(Spectrum_Parameters),
    //     &ocean_sim.spectrum_params,
    // )
    // vk.CmdDispatch(
    //     cmd,
    //     u32(math.ceil_f32(f32(DOMAIN_GRAPH_EXTENT.width) / 16.0)),
    //     u32(math.ceil_f32(f32(DOMAIN_GRAPH_EXTENT.height) / 16.0)),
    //     1,
    // )
    // transition_image(cmd, ocean_sim.jonswap_texture.image, .GENERAL, .SHADER_READ_ONLY_OPTIMAL)
    //
    transition_image(cmd, self.draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
    transition_image(cmd, self.depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)

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
    result = vk.QueuePresentKHR(self.graphics_queue, &present_info)
    if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
        engine_resize_swapchain(self) or_return
    } else {
        vk_check(result) or_return
    }
 
    self.frame_number += 1

    return true
}

ui_status_row :: proc(label: cstring, status: Build_Status) {
    size := im.GetFrameHeight()
    pos := im.GetCursorScreenPos()
    dl := im.GetWindowDrawList()
    center := im.Vec2{pos.x + size * 0.5, pos.y + size * 0.5}
    r := size * 0.3
    thickness := max(2, size * 0.1)

    switch status {
    case .Idle:
        im.DrawList_AddCircleFilled(dl, center, r * 0.4, im.ColorConvertFloat4ToU32({0.5, 0.5, 0.5, 1}))
    case .Compiling:
        t := f32(im.GetTime())
        start := t * 8
        im.DrawList_PathArcTo(dl, center, r, start, start + 4.5, 24)
        im.DrawList_PathStroke(dl, im.ColorConvertFloat4ToU32({1, 0.8, 0.2, 1}), thickness)
    case .Success:
        col := im.ColorConvertFloat4ToU32({0.2, 0.9, 0.3, 1})
        a := im.Vec2{center.x - r, center.y}
        b := im.Vec2{center.x - r * 0.3, center.y + r * 0.7}
        c := im.Vec2{center.x + r, center.y - r * 0.7}
        im.DrawList_AddLine(dl, a, b, col, thickness)
        im.DrawList_AddLine(dl, b, c, col, thickness)
    case .Failed:
        col := im.ColorConvertFloat4ToU32({0.95, 0.2, 0.2, 1})
        im.DrawList_AddLine(dl, {center.x - r, center.y - r}, {center.x + r, center.y + r}, col, thickness)
        im.DrawList_AddLine(dl, {center.x - r, center.y + r}, {center.x + r, center.y - r}, col, thickness)
    }

    im.Dummy({size, size})
    im.SameLine()
    im.Text("%s", label)
}

engine_ui_definition :: proc(self: ^Engine) {
    // ImGUi new frame
    im_glfw.NewFrame()
    im_vk.NewFrame()
    im.NewFrame()

    game_manager_game_draw_ui(&self.game_manager, &self.scene, self)
    v := im.GetMainViewport()
    im.SetNextWindowPos({0, 0})
    im.SetNextWindowSize({250, v.WorkSize.y * .8})
    im.Begin("Hierarchy", nil, {.NoFocusOnAppearing, .NoCollapse, .NoResize})
    @(static) selected_node: i32 = -1
    // im.Text("Camera - %f, %f, %f", self.scene.camera.position.x, self.scene.camera.position.y, self.scene.camera.position.z)
    for &hierarchy, i in self.scene.hierarchy {
        if hierarchy.parent == -1 {
            ui_scene_tree(&self.scene, i, &selected_node)
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

        im.SliderFloat4("data1", &selected.data.data1, 0.0, 10.0)
        im.SliderFloat4("data2", &selected.data.data2, 0.0, 10.0)
        im.SliderFloat4("data3", &selected.data.data3, 0.0, 10.0)
        im.SliderFloat4("data4", &selected.data.data4, 0.0, 10.0)

    }
    im.End()


    //Compiler status 
    size: im.Vec2 = {
        v.WorkSize.x,
        v.WorkSize.y * .2
    }
    pos : im.Vec2 = {
        0,
        v.WorkSize.y - size.y,
        
    }
    im.SetNextWindowPos(pos)
    im.SetNextWindowSize(size)
    if im.Begin("Status", nil, {.NoFocusOnAppearing, .NoCollapse, .NoResize}) {
        ui_status_row("Game library", self.game_manager.library.build_status)
        ui_status_row("Shaders", self.shader_manager.build_status)
    }
    im.End()

    im.Render()
}

ui_scene_tree :: proc(scene: ^Scene, #any_int node: i32, selected_node: ^i32) -> i32 {
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
                if sub_node := ui_scene_tree(scene, ch, selected_node); sub_node > -1 {
                    selected_node^ = sub_node
                }
            }
            im.TreePop()
        }
    }
    im.PopID()

    return selected_node^
}


