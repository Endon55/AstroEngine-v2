package astro

import la "core:math/linalg"
import vk "vendor:vulkan"


Material_Pass :: enum u8 {
    Main_Color,
    Transparent,
    Other,
}

Material_Pipeline :: struct {
    pipeline: vk.Pipeline,
    layout: vk.PipelineLayout,
}

Material_Shader :: struct {
    device: vk.Device,
    material_layout: vk.DescriptorSetLayout,
    layout: vk.PipelineLayout,
    opaque_pipeline: Material_Pipeline,
    transparent_pipeline: Material_Pipeline,
}

Material_Shader_Config :: struct {
    vertex_shader: []byte,
    fragment_shader: []byte,
    material_layout: vk.DescriptorSetLayout,
}

Material_Instance :: struct {
    pipeline: ^Material_Pipeline,
    material_set: vk.DescriptorSet,
    pass_type: Material_Pass,
}

Metallic_Roughness_Constants :: struct {
    color_factors: la.Vector4f32,
    metal_rough_factors: la.Vector4f32,
    extra: [14]la.Vector4f32,
}

Metallic_Roughness_Resources :: struct {
    color_image: Allocated_Image,
    color_sampler: vk.Sampler,
    metal_rough_image: Allocated_Image,
    metal_rough_sampler: vk.Sampler,
    data_buffer: vk.Buffer,
    data_buffer_ffset: u32,
}

Metallic_Roughness :: struct {
    shader: Material_Shader,
    constants: Metallic_Roughness_Constants,
    resources: Metallic_Roughness_Resources,
    writer: Descriptor_Writer,
}

metallic_roughness_build_pipelines :: proc(self: ^Metallic_Roughness, engine: ^Engine) -> (ok: bool,) {
    return true
}

material_shader_clear_resources :: proc(self: Material_Shader) {
    vk.DestroyDescriptorSetLayout(self.device, self.material_layout, nil)
    vk.DestroyPipelineLayout(self.device, self.layout, nil)
    vk.DestroyPipeline(self.device, self.transparent_pipeline.pipeline, nil)
    vk.DestroyPipeline(self.device, self.opaque_pipeline.pipeline, nil)
}

metallic_roughness_clear_resources :: proc(self: Metallic_Roughness) {
    material_shader_clear_resources(self.shader)
}

material_shader_write :: proc(
    self: ^Material_Shader,
    device: vk.Device,
    pass: Material_Pass,
    descriptor_allocator: ^Descriptor_Allocator,
) -> (material: Material_Instance, ok: bool) {
    material.pass_type = pass
    material.pipeline = pass == .Transparent ? &self.transparent_pipeline : &self.opaque_pipeline
    material.material_set = descriptor_allocator_allocate(
        descriptor_allocator, device, &self.material_layout,
    ) or_return

    return material, true
}

metallic_roughness_write :: proc(
    self: ^ Metallic_Roughness,
    device: vk.Device,
    pass: Material_Pass,
    resources: ^Metallic_Roughness_Resources,
    descriptor_allocator: ^Descriptor_Allocator,
    ) -> (
    material: Material_Instance,
    ok: bool,
    ) {
        material = material_shader_write(
            &self.shader, device, pass, descriptor_allocator,
        ) or_return
        
        descriptor_writer_init(&self.writer, device)
        descriptor_writer_clear(&self.writer)
        descriptor_writer_write_buffer(
            &self.writer,
            0,
            resources.data_buffer,
            size_of(Metallic_Roughness_Constants),
            vk.DeviceSize(resources.data_buffer_ffset),
            .UNIFORM_BUFFER,
        ) or_return
        descriptor_writer_write_image(
            &self.writer,
            1,
            resources.color_image.image_view,
            resources.color_sampler,
            .SHADER_READ_ONLY_OPTIMAL,
            .COMBINED_IMAGE_SAMPLER,
        ) or_return
        descriptor_writer_write_image(
            &self.writer,
            2,
            resources.metal_rough_image.image_view,
            resources.metal_rough_sampler,
            .SHADER_READ_ONLY_OPTIMAL,
            .COMBINED_IMAGE_SAMPLER
        ) or_return

        descriptor_writer_update_set(&self.writer, material.material_set)

        return material, true
    }

metallic_roughness_build_pipeline :: proc(
    self: ^Metallic_Roughness,
    engine: ^Engine,
) -> (ok: bool,) {
    layout_builder: Descriptor_Layout_Builder
    descriptor_layout_builder_init(&layout_builder, engine.vk_device)
    descriptor_layout_builder_add_binding(&layout_builder, 0, .UNIFORM_BUFFER)
    descriptor_layout_builder_add_binding(&layout_builder, 1, .COMBINED_IMAGE_SAMPLER)
    descriptor_layout_builder_add_binding(&layout_builder, 2, .COMBINED_IMAGE_SAMPLER)
    material_layout := descriptor_layout_builder_build(&layout_builder, {.VERTEX, .FRAGMENT}) or_return

    config := Material_Shader_Config {
        vertex_shader = #load("./../shaders/compiled/mesh.vert.spv"),
        fragment_shader = #load("./../shaders/compiled/mesh.frag.spv"),
        material_layout = material_layout,
    }
    material_shader_build(&self.shader, engine, config) or_return

    return true
}

material_shader_build :: proc(
    self: ^Material_Shader,
    engine: ^Engine,
    config: Material_Shader_Config,
) -> (ok: bool) {
    vertex_shader := create_shader_module(engine.vk_device, config.vertex_shader) or_return
    defer vk.DestroyShaderModule(engine.vk_device, vertex_shader, nil)

    fragment_shader := create_shader_module(engine.vk_device, config.fragment_shader) or_return
    defer vk.DestroyShaderModule(engine.vk_device, fragment_shader, nil)

    self.device = engine.vk_device
    self.material_layout = config.material_layout
    layouts := [2]vk.DescriptorSetLayout {
        engine.gpu_scene_data_descriptor_layout,
        self.material_layout,
    }

    matrix_range := vk.PushConstantRange {
        offset = 0,
        size = size_of(GPU_Draw_Push_Constants),
        stageFlags = {.VERTEX},
    }

    pipeline_layout_info := pipeline_layout_create_info()
    pipeline_layout_info.setLayoutCount = 2
    pipeline_layout_info.pSetLayouts = raw_data(layouts[:])
    pipeline_layout_info.pPushConstantRanges = &matrix_range
    pipeline_layout_info.pushConstantRangeCount = 1

    vk_check(vk.CreatePipelineLayout(
            engine.vk_device, &pipeline_layout_info, nil, &self.layout)) or_return
    defer if !ok {
        vk.DestroyPipelineLayout(engine.vk_device, self.layout, nil)
    }

    pipeline_builder := pipeline_builder_create_default()
    pipeline_builder_set_shaders(&pipeline_builder, vertex_shader, fragment_shader)
    pipeline_builder_set_input_topology(&pipeline_builder, .TRIANGLE_LIST)
    pipeline_builder_set_polygon_mode(&pipeline_builder, .FILL)
    pipeline_builder_set_cull_mode(&pipeline_builder, vk.CullModeFlags_NONE, .CLOCKWISE)
    pipeline_builder_set_multisampling_none(&pipeline_builder)
    pipeline_builder_disable_blending(&pipeline_builder)
    pipeline_builder_enable_depth_test(&pipeline_builder, true, .GREATER_OR_EQUAL)

    pipeline_builder_set_color_attachment_format(
        &pipeline_builder, engine.draw_image.image_format)
    pipeline_builder_set_depth_attachment_format(
        &pipeline_builder, engine.depth_image.image_format)

    pipeline_builder.pipeline_layout = self.layout

    self.opaque_pipeline = {
        pipeline = pipeline_builder_build(&pipeline_builder, engine.vk_device) or_return,
        layout = self.layout,
    }
    defer if !ok {
        vk.DestroyPipeline(engine.vk_device, self.opaque_pipeline.pipeline, nil)
    }

    pipeline_builder_enable_blending_additive(&pipeline_builder)
    pipeline_builder_enable_depth_test(&pipeline_builder, false, .GREATER_OR_EQUAL)

    self.transparent_pipeline = {
        pipeline = pipeline_builder_build(&pipeline_builder, engine.vk_device) or_return,
        layout = self.layout,
    }
    defer if !ok {
        vk.DestroyPipeline(engine.vk_device, self.transparent_pipeline.pipeline, nil)
    }

    return true
}
