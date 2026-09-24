package astro

import "core:log"

import vk "vendor:vulkan"
import la "core:math/linalg"


import vma "libs:vma"


engine_init_default_data :: proc(self: ^Engine) -> (ok: bool) {
    
    scene_init(&self.scene)

    camera_init(&self.scene.camera, .Orthographic)

    load_gltf_meshes(self, "build/assets/basicmesh.glb", &self.scene.meshes) or_return
    defer if !ok {
        destroy_mesh_assets(&self.scene.meshes)
    }
   
    white := pack_unorm_4x8({1,1,1,1})
    self.white_image = create_image_from_data(self, &white, {1,1,1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.white_image)

    grey := pack_unorm_4x8({0.66,0.66,0.66,1})
    self.grey_image = create_image_from_data(self, &grey, {1,1,1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.grey_image)

    black := pack_unorm_4x8({0,0,0,0})
    self.black_image = create_image_from_data(self, &black, {1,1,1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.black_image)

    magenta := pack_unorm_4x8({1,0,1,1})
    pixels: [16*16]u32
    for x in 0..<16 {
        for y in 0..<16 {
            pixels[y * 16 + x] = ((x%2) ~ (y%2)) != 0 ? magenta: black
        }
    }
    self.error_checkerboard_image = create_image_from_data(self, raw_data(pixels[:]), {16,16,1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.error_checkerboard_image)

    sampler_info := vk.SamplerCreateInfo {
        sType = .SAMPLER_CREATE_INFO,
        magFilter = .NEAREST,
        minFilter = .NEAREST,
    }

    vk_check(vk.CreateSampler(self.vk_device, &sampler_info, nil, &self.default_sampler_nearest)) or_return

    deletion_queue_push(&self.main_deletion_queue, self.default_sampler_nearest)

    sampler_info.magFilter = .LINEAR
    sampler_info.minFilter = .LINEAR

    vk_check(vk.CreateSampler(self.vk_device, &sampler_info, nil, &self.default_sampler_linear)) or_return
    deletion_queue_push(&self.main_deletion_queue, self.default_sampler_linear)

    material_resources := Metallic_Roughness_Resources {
        color_image = self.white_image,
        color_sampler = self.default_sampler_linear,
        metal_rough_image = self.white_image,
        metal_rough_sampler = self.default_sampler_linear,
    }

    material_constants := create_buffer(
                            self,
                            size_of(Metallic_Roughness_Constants),
                            {.UNIFORM_BUFFER},
                            .CPU_TO_GPU,) or_return
    deletion_queue_push(&self.main_deletion_queue, material_constants)

    scene_uniform_data := 
        cast(^Metallic_Roughness_Constants)material_constants.info.pMappedData

    scene_uniform_data.color_factors = {1,1,1,1}
    scene_uniform_data.metal_rough_factors = {1,0.5,0,0}

    material_resources.data_buffer = material_constants.buffer
    material_resources.data_buffer_ffset = 0

    self.default_material_data = metallic_roughness_write(
        &self.metal_rough_material,
        self.vk_device,
        .Main_Color,
        &material_resources,
        &self.global_descriptor_allocator
    ) or_return
    
    default_material_idx := append_and_get_idx(
        &self.scene.materials, self.default_material_data,
    )
    ocean_constants_buffer := create_buffer(
                            self,
                            size_of(Ocean_Data),
                            {.UNIFORM_BUFFER},
                            .CPU_TO_GPU,) or_return
    self.ocean_data = cast(^Ocean_Data)ocean_constants_buffer.info.pMappedData
    deletion_queue_push(&self.main_deletion_queue, ocean_constants_buffer)
    self.ocean_material_data = material_shader_write(
        &self.ocean_material,
        self.vk_device,
        .Main_Color,
        &self.global_descriptor_allocator,
    ) or_return

    writer: Descriptor_Writer
    descriptor_writer_init(&writer, self.vk_device)
    descriptor_writer_write_image(
        &writer,
        binding = 0,
        image = self.white_image.image_view,
        sampler = self.default_sampler_linear,
        layout = .SHADER_READ_ONLY_OPTIMAL,
        type = .COMBINED_IMAGE_SAMPLER,
    )

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
        &self.scene.materials, self.ocean_material_data,
    )

    for m, i in self.scene.meshes {

        if m.name == "Sphere" {
            continue
        }
        
        node_idx := scene_add_mesh_node(&self.scene, -1, i, default_material_idx, m.name)
        self.name_for_node[m.name] = u32(node_idx)
    }

    // Find and update Suzanne node
    if suzanne_node, suzanne_ok := self.name_for_node["Suzanne"]; suzanne_ok {
        self.scene.local_transforms[suzanne_node] = la.MATRIX4F32_IDENTITY
        self.scene.local_transforms[suzanne_node] = la.matrix_mul(self.scene.local_transforms[suzanne_node], la.matrix4_rotate_f32(1.5, {1, 0, 0}))
    }

    plane_size: u32 = 30
    plane_size2: u32 = plane_size / 2

    // Find and update Cube nodes (create a line of cubes)
    if cube_node, cube_ok := self.name_for_node["Cube"]; cube_ok {
        for x := -i32(plane_size2); x < i32(plane_size2); x += 1 {
            for y := -i32(plane_size2); y < i32(plane_size2); y += 1 {
            scale := la.matrix4_scale(la.Vector3f32{0.2, 0.2, 0.2})
            translation := la.matrix4_translate(la.Vector3f32{f32(x), f32(y), 0})
            transform := la.matrix_mul(translation, scale)

            // For simplicity, assume one node per cube
            if x == -3 {
                // Use the original cube node for x = -3
                self.scene.local_transforms[cube_node] = transform
            } else {
                // Add new nodes for additional cubes
                new_cube_idx := scene_add_mesh_node(
                    scene = &self.scene,
                    parent = cube_node,
                    mesh_index = cube_node,
                    material_index = cube_node,
                    name = "Cube",
                )
                self.scene.local_transforms[u32(new_cube_idx)] = transform
            }
        }
        }
    }
    generate_plane(self, &self.scene.meshes, plane_size, plane_size, 5.0) or_return
    plane_idx := scene_add_mesh_node(
                   &self.scene,
                   parent = -1,
                   mesh_index = len(self.scene.meshes) - 1,
                   material_index = ocean_material_idx,
                   name = "Plane"
               )
    self.scene.local_transforms[plane_idx] = la.matrix_mul(
        self.scene.local_transforms[plane_idx], 
    la.matrix4_translate_f32({-f32(plane_size / 2.0) , -f32(plane_size / 2.0), 0})
    )


    return true
}


