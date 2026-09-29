package astro

import la "core:math/linalg"


Ocean :: struct {

    plane_size: u32,
    plane_size2: u32,

    ocean_material: Material_Shader,
    ocean_material_data: Material_Instance,


    ocean_data: ^Ocean_Data,
}

Ocean_Data :: struct {
    time: f32,
    _padding: [3]f32,
}

ocean_init::proc(self:^Ocean) ->(ok:bool,) {
    self.plane_size = 30
    self.plane_size2 = self.plane_size / 2

    return true
}

ocean_init_default_data :: proc(self:^Ocean, engine:^Engine) ->(ok:bool,) {

    ocean_constants_buffer := create_buffer(
                            engine,
                            size_of(Ocean_Data),
                            {.UNIFORM_BUFFER},
                            .CPU_TO_GPU,) or_return
    self.ocean_data = cast(^Ocean_Data)ocean_constants_buffer.info.pMappedData
    deletion_queue_push(&engine.main_deletion_queue, ocean_constants_buffer)
    self.ocean_material_data = material_shader_write(
        &self.ocean_material,
        engine.vk_device,
        .Main_Color,
        &engine.global_descriptor_allocator,
    ) or_return


    writer: Descriptor_Writer
    descriptor_writer_init(&writer, engine.vk_device)


    descriptor_writer_write_buffer(
        &writer,
        binding = 1,
        buffer = ocean_constants_buffer.buffer,
        size = size_of(Ocean_Data),
        offset = 0,
        type = .UNIFORM_BUFFER,
    )    
    descriptor_writer_update_set(&writer, self.ocean_material_data.material_set)



    ocean_material_idx := append_and_get_idx(
        &engine.scene.materials, self.ocean_material_data,
    )
    plane_mesh_idx := generate_plane(engine, &engine.scene.meshes, self.plane_size, self.plane_size, 5.0) or_return
    plane_idx := scene_add_mesh_node(
                   &engine.scene,
                   parent = -1,
                   mesh_index = plane_mesh_idx,
                   material_index = ocean_material_idx,
                   name = "Plane"
               )
    engine.scene.local_transforms[plane_idx] = la.matrix_mul(
        engine.scene.local_transforms[plane_idx], 
    la.matrix4_translate_f32({-f32(self.plane_size / 2.0) , -f32(self.plane_size / 2.0), 0})
    )
    return true
}

ocean_build_pipeline :: proc(self: ^Ocean, engine: ^Engine) -> (ok: bool) {
    layout_builder: Descriptor_Layout_Builder
    descriptor_layout_builder_init(&layout_builder, engine.vk_device)
    descriptor_layout_builder_add_binding(&layout_builder, 0, .COMBINED_IMAGE_SAMPLER)
    descriptor_layout_builder_add_binding(&layout_builder, 1, .UNIFORM_BUFFER) 
    descriptor_layout_builder_add_binding(&layout_builder, 2, .COMBINED_IMAGE_SAMPLER)
    material_layout := descriptor_layout_builder_build(&layout_builder, {.VERTEX, .FRAGMENT}) or_return

    if "ocean.frag" not_in engine.shader_manager.shaders && "sin_ocean.vert" not_in engine.shader_manager.shaders {
        return false
    }

    fragment :Shader = engine.shader_manager.shaders["ocean.frag"]
    vertex :Shader = engine.shader_manager.shaders["sin_ocean.vert"]

    config := Material_Shader_Config {
        vertex_shader = vertex.spirv_bytes, 
        fragment_shader = fragment.spirv_bytes, 
        material_layout = material_layout,
    }
    material_shader_build(&self.ocean_material, engine, config) or_return
    deletion_queue_push(&engine.main_deletion_queue, self.ocean_material)

    return true
}



