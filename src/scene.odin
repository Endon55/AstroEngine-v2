package astro

import "base:builtin"
import la "core:math/linalg"
import vk "vendor:vulkan"
NO_MESH :: max(u32)
NO_MATERIAL :: max(u32)
NO_NAME :: max(u32)

Render_Object :: struct {
    index_count: u32,
    first_index: u32,
    index_buffer: vk.Buffer,
    material: u32,
    transform: la.Matrix4f32,
    vertex_buffer_address: vk.DeviceAddress,
}

Draw_Context :: struct {
    opaque_surfaces: [dynamic]Render_Object
}

Hierarchy :: struct {
    parent: i32, // -1 means no parent
    first_child: i32, //-1 means no children
    next_sibling: i32, //-1 means no siblings, otherwise next sibling in level
    last_sibling: i32, //-1 means no siblings, otherwise index to last sibling
    level: i32 // Depth in hierarchy, root = 0
}

Scene :: struct {
    camera: Camera,

    local_transforms: [dynamic] la.Matrix4f32,
    world_transforms: [dynamic] la.Matrix4f32,
    
    hierarchy: [dynamic] Hierarchy,
    mesh_for_node: [dynamic] u32,
    material_for_node: [dynamic] u32,
    name_for_node: [dynamic] u32,
    node_names: [dynamic] string,
    
    materials: [dynamic] Material_Instance,

    meshes: Mesh_Asset_List,
}

scene_add_mesh_node :: proc(
    scene: ^Scene,
    #any_int parent: i32,
    #any_int mesh_index, material_index: u32,
    name: string = "",
) -> i32 {

    level := parent > -1 ? scene.hierarchy[parent].level + 1 : 0
    node := scene_add_node(scene, parent, level)

    scene.mesh_for_node[node] = mesh_index
    scene.material_for_node[node] = material_index

    if len(name) > 0 {
        name_idx := append_and_get_idx(&scene.node_names, name)
        scene.name_for_node[u32(node)] = name_idx
    }

    return node
}

update_transforms :: proc(scene: ^Scene, #any_int node_index: i32) {

    node := scene.hierarchy[node_index]
    parent := node.parent

    if parent > -1 {
        scene.world_transforms[node_index] = la.matrix_mul(
            scene.world_transforms[parent],
            scene.local_transforms[node_index],
        )
    } else {
        scene.world_transforms[node_index] = scene.local_transforms[node_index]
    }

    child := node.first_child
    for child != -1 {
        update_transforms(scene, child)
        child = scene.hierarchy[child].next_sibling
    }
}

//updates all root nodes, which recursively update thier own children
update_all_transforms :: proc(scene: ^Scene) {
    for &node, i in scene.hierarchy {
        if node.parent == -1 {
            update_transforms(scene, i)
        }
    }
}

scene_draw_node :: proc(scene: ^Scene, #any_int node_index: i32, ctx: ^Draw_Context) {


    node_matrix := la.matrix_mul(
                     scene.local_transforms[node_index],
                     scene.world_transforms[node_index],
                 )
    if scene.mesh_for_node[node_index] != NO_MESH {
        mesh_index := scene.mesh_for_node[node_index]
        mesh := &scene.meshes[mesh_index]


        for &surface in mesh.surfaces {
            material_index := surface.material_index
            if scene.material_for_node[node_index] != NO_MATERIAL {
                material_index = scene.material_for_node[node_index]
            }

            def := Render_Object {
                index_count = surface.count,
                first_index = surface.start_index,
                index_buffer = mesh.mesh_buffers.index_buffer.buffer,
                material = material_index,
                transform = node_matrix,
                vertex_buffer_address = mesh.mesh_buffers.vertex_buffer_address,
            }

            append(&ctx.opaque_surfaces, def)
        }
    }
    
    child := scene.hierarchy[node_index].first_child
    for child != -1 {
        scene_draw_node(scene, child, ctx)
        child = scene.hierarchy[child].next_sibling
    }

}

scene_get_node_name :: proc(self:^Scene, #any_int node: i32) -> string {
    name_idx := self.name_for_node[u32(node)]
    if name_idx == NO_NAME {
        return ""
    }
    return self.node_names[name_idx]
}
