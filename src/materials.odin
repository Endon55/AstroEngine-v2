package astro

import la "core:math/linalg"
import vk "vendor:vulkan"
import "core:log"
import "core:fmt"

Material_Pass :: enum u8 {
    Main_Color,
    Transparent,
    Other,
}

Material_Pipeline :: struct {
    pipeline: vk.Pipeline,
    layout: vk.PipelineLayout,
}

// Descriptor set numbers every material pipeline agrees on, matching [[vk::binding(n, set)]] in the shaders.
SCENE_SET :: 0
MATERIAL_SET :: 1

Material_Shader :: struct {
    name: string,
    device: vk.Device,
    layout: Pipeline_Layout,
    opaque_pipeline: Material_Pipeline,
    transparent_pipeline: Material_Pipeline,
}

Material_Shader_Config :: struct {
    vertex_shader: []byte,
    fragment_shader: []byte,
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

// Starts a material pipeline: the scene set is shared from the engine and the draw push constants are added.
// Follow with one material_shader_add_binding per material descriptor, then material_shader_build.
material_shader_init :: proc(self: ^Material_Shader, engine: ^Engine, name: string) {
    self^ = {
        name = name,
        device = engine.vk_device,
    }
    pipeline_layout_init(&self.layout, engine.vk_device, name)
    pipeline_layout_use_set(&self.layout, SCENE_SET, &engine.scene_layout)
    pipeline_layout_add_push_constant(&self.layout, GPU_Draw_Push_Constants, {.VERTEX})
}

// Declares a descriptor of the material set (set 1). `binding` must match the shader.
material_shader_add_binding :: proc(
    self: ^Material_Shader,
    binding: u32,
    type: vk.DescriptorType,
    stages: vk.ShaderStageFlags = {.VERTEX, .FRAGMENT},
    count: u32 = 1,
    loc := #caller_location,
) {
    pipeline_layout_add_binding(&self.layout, MATERIAL_SET, binding, type, stages, count, loc)
}

material_shader_init_writer :: proc(self: ^Material_Shader, writer: ^Descriptor_Writer) {
    descriptor_writer_init(writer, self.device, pipeline_layout_set(&self.layout, MATERIAL_SET))
}

material_shader_clear_resources :: proc(self: Material_Shader) {
    pipeline_layout_destroy(self.layout)
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
        descriptor_allocator, pipeline_layout_set(&self.layout, MATERIAL_SET),
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

        material_shader_init_writer(&self.shader, &self.writer)
        descriptor_writer_write_buffer(
            &self.writer,
            0,
            resources.data_buffer,
            size_of(Metallic_Roughness_Constants),
            vk.DeviceSize(resources.data_buffer_ffset),
        ) or_return
        descriptor_writer_write_image(
            &self.writer,
            1,
            resources.color_image.image_view,
            resources.color_sampler,
        ) or_return
        descriptor_writer_write_image(
            &self.writer,
            2,
            resources.metal_rough_image.image_view,
            resources.metal_rough_sampler,
        ) or_return

        descriptor_writer_update_set(&self.writer, material.material_set)

        return material, true
    }

metallic_roughness_build_pipeline :: proc(
    self: ^Metallic_Roughness,
    engine: ^Engine,
) -> (ok: bool,) {
    material_shader_init(&self.shader, engine, "Metallic Roughness")
    material_shader_add_binding(&self.shader, 0, .UNIFORM_BUFFER)
    material_shader_add_binding(&self.shader, 1, .COMBINED_IMAGE_SAMPLER)
    material_shader_add_binding(&self.shader, 2, .COMBINED_IMAGE_SAMPLER)

    vertex, has_vertex := shader_manager_get_shader(&engine.shader_manager, "engine/mesh.vert")
    fragment, has_fragment := shader_manager_get_shader(&engine.shader_manager, "engine/mesh.frag")
    if !has_vertex || !has_fragment {
        return false
    }

    config := Material_Shader_Config {
        vertex_shader = vertex.spirv_bytes, 
        fragment_shader = fragment.spirv_bytes, 
    }
    material_shader_build(&self.shader, engine, config) or_return

    return true
}

material_shader_build :: proc(
    self: ^Material_Shader,
    engine: ^Engine,
    config: Material_Shader_Config,
) -> (ok: bool) {

    material_shader_validate(self, config.vertex_shader, config.fragment_shader) or_return

    vertex_shader := create_shader_module(engine.vk_device, config.vertex_shader) or_return
    defer vk.DestroyShaderModule(engine.vk_device, vertex_shader, nil)

    fragment_shader := create_shader_module(engine.vk_device, config.fragment_shader) or_return
    defer vk.DestroyShaderModule(engine.vk_device, fragment_shader, nil)

    self.device = engine.vk_device
    pipeline_layout_build(&self.layout) or_return
    defer if !ok {
        pipeline_layout_release(&self.layout)
    }

    pipelines := material_shader_create_pipelines(self, engine, vertex_shader, fragment_shader) or_return
    self.opaque_pipeline = pipelines.opaque
    self.transparent_pipeline = pipelines.transparent
    return true
}

// Checks both shaders against the layout declared on this material, logging every mismatch.
material_shader_validate :: proc(self: ^Material_Shader, vertex_code, fragment_code: []byte) -> bool {
    vertex_ok := pipeline_layout_validate_shader(&self.layout, vertex_code, fmt.tprintf("%v (vertex)", self.name))
    fragment_ok := pipeline_layout_validate_shader(&self.layout, fragment_code, fmt.tprintf("%v (fragment)", self.name))
    return vertex_ok && fragment_ok
}

Material_Shader_Pipelines :: struct {
    opaque: Material_Pipeline,
    transparent: Material_Pipeline,
}

material_shader_rebuild_pipelines :: proc(
    self: ^Material_Shader,
    engine: ^Engine,
    vertex_code, fragment_code: []byte,
) -> (pipelines: Material_Shader_Pipelines, ok: bool) {
    material_shader_validate(self, vertex_code, fragment_code) or_return
    vertex_shader := create_shader_module(engine.vk_device, vertex_code) or_return
    defer vk.DestroyShaderModule(engine.vk_device, vertex_shader, nil)
    fragment_shader := create_shader_module(engine.vk_device, fragment_code) or_return
    defer vk.DestroyShaderModule(engine.vk_device, fragment_shader, nil)
    return material_shader_create_pipelines(self, engine, vertex_shader, fragment_shader)
}

material_shader_create_pipelines :: proc(
    self: ^Material_Shader,
    engine: ^Engine,
    vertex_shader, fragment_shader: vk.ShaderModule,
) -> (pipelines: Material_Shader_Pipelines, ok: bool) {
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

    pipeline_builder.pipeline_layout = self.layout.handle

    pipelines.opaque = {
        pipeline = pipeline_builder_build(&pipeline_builder, engine.vk_device) or_return,
        layout = self.layout.handle,
    }
    defer if !ok {
        vk.DestroyPipeline(engine.vk_device, pipelines.opaque.pipeline, nil)
    }

    pipeline_builder_enable_blending_additive(&pipeline_builder)
    pipeline_builder_enable_depth_test(&pipeline_builder, false, .GREATER_OR_EQUAL)

    pipelines.transparent = {
        pipeline = pipeline_builder_build(&pipeline_builder, engine.vk_device) or_return,
        layout = self.layout.handle,
    }
    ok = true
    return pipelines, true
}

