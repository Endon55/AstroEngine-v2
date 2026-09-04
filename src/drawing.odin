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

    color_attachment := attachment_info(self.draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
    depth_attachment := depth_attachment_info(self.depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

    render_info := rendering_info(self.draw_extent, &color_attachment, &depth_attachment)
    vk.CmdBeginRendering(cmd, &render_info)


    vk.CmdBindPipeline(cmd, .GRAPHICS, self.mesh_pipeline)

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

    image_set := descriptor_growable_allocate(&frame.frame_descriptors, &self.single_image_descriptor_layout) or_return

    {
        writer: Descriptor_Writer
        descriptor_writer_init(&writer, self.vk_device)
        descriptor_writer_write_image(&writer, binding = 0, image = self.error_checkerboard_image.image_view, sampler = self.default_sampler_nearest, layout = .SHADER_READ_ONLY_OPTIMAL, type = .COMBINED_IMAGE_SAMPLER)

        descriptor_writer_update_set(&writer, image_set)
    }
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, self.mesh_pipeline_layout, 0, 1, &image_set, 0, nil)
    view := la.matrix4_translate_f32({0,0,-5})
    projection := matrix4_perspective_reverse_z_f32(f32(la.to_radians(70.0)), f32(self.draw_extent.width) / f32(self.draw_extent.height), 0.1, true)

    push_constants := GPU_Draw_Push_Constants {
        world_matrix = projection * view,
        vertex_buffer = self.test_meshes[2].mesh_buffers.vertex_buffer_address,
    }



    vk.CmdPushConstants(cmd, self.mesh_pipeline_layout, {.VERTEX}, 0, size_of(GPU_Draw_Push_Constants), &push_constants,)
    
    vk.CmdBindIndexBuffer(cmd, self.test_meshes[2].mesh_buffers.index_buffer.buffer, 0, .UINT32)

    vk.CmdDrawIndexed(cmd, self.test_meshes[2].surfaces[0].count, 1, self.test_meshes[2].surfaces[0].start_index, 0, 0)
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
    
    transition_image(cmd, self.draw_image.image, .UNDEFINED, .GENERAL)

    engine_draw_background(self, cmd) or_return


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

engine_ui_definition :: proc(self: ^Engine) {

    im_glfw.NewFrame()
    im_vk.NewFrame()
    im.NewFrame()

    if im.Begin("Background", nil, {.AlwaysAutoResize}) {
        im.SliderFloat("Render Scale", &self.render_scale, 0.3, 1.0)
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


