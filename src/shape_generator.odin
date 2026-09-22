package astro

 import "core:strings"
 import "core:log"


generate_plane :: proc (engine: ^Engine, meshes: ^Mesh_Asset_List, size_x, size_y: u32, density: f32,) -> (ok: bool){

    x_gaps := u32(f32(size_x) * density)
    y_gaps := u32(f32(size_y) * density)
    //Account for the end vertice
    x_vertices := x_gaps + 1
    y_vertices := y_gaps + 1

    //x_gap :
    indices:= make([]u32, x_gaps * y_gaps * 6)
    vertices:= make([]Vertex, x_vertices * y_vertices)
    defer delete(indices)
    defer delete(vertices)
    x_gap := f32(size_x / x_gaps)
    y_gap := f32(size_y / y_gaps)


    //create vertices
    index: u32 = 0
    for y in 0..< y_vertices {
        for x in 0..< x_vertices {
            vertices[index] = {
                position = {x_gap * f32(x), 1, y_gap * f32(y)},
                normal = {1,0,0},
                color = {1,1,1,1},
                uv_x = 0,
                uv_y = 0,
            }
            index += 1
        }
    }
    //draw triangles
    index = 0
    for y in 0..< y_gaps {
        for x in 0..< x_gaps {
            row_index :u32 = y * x_vertices + x
            next_row_index :u32 = (y + 1) * x_vertices + x

            indices[index] = row_index
            indices[index + 1] = row_index + 1
            indices[index + 2] = next_row_index + 1

            indices[index + 3] = row_index
            indices[index + 4] = next_row_index
            indices[index + 5] = next_row_index + 1

            index += 6

        }
    }

    new_mesh := append_and_get_ref(meshes, Mesh_Asset{})

    new_mesh.name = strings.clone("Plane")
    new_mesh.surfaces = make([dynamic]Geo_Surface, context.allocator)
    new_surface: Geo_Surface
    new_surface.start_index = 0
    new_surface.count = u32(len(indices))

    append(&new_mesh.surfaces, new_surface)
    new_mesh.mesh_buffers = upload_mesh(engine, indices[:], vertices[:]) or_return


   return true 

}
