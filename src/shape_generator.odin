package astro

 import "core:strings"
 import "core:log"

    /*
           Top Vertices(+z)                      Bottom Vertices(-z)
              v0______v1                             v12______v13  
               |      |                                |      |        
               |      |                                |      |         
 v10 __________|      |___________ v3   v22  __________|      |___________ v15
    |        v11      v2         |          |        v23     v14         |
    |                            |          |                            |
 v9 |_________v8      v5_________| v4   v21 |________v20     v17_________| v16
               |      |                                |      |
               |      |                                |      |        
               |______|                                |______|
              v7    v6                              v19    v18
    */

generate_cross :: proc (engine: ^ Engine, meshes: ^Mesh_Asset_List, arm_width:f32=1.0, arm_length:f32=1.0, cross_depth:f32=1.0) -> (mesh_index: int, ok: bool) {

    edge_length : f32 = arm_length
    square: f32 = arm_width
    square2: f32 = square / 2.0 
    full_edge: f32 = edge_length + square2
    depth2 :f32 = cross_depth / 2.0
    
    //12 vertices per side
    vertices:= make([]Vertex, 24)  
    indices:= make([]u32, 52 * 3)

    defer delete(indices)
    defer delete(vertices)
    //6 triangles per side(12), then 24 triangles for the entire edge
    //offset

    vertices[0].position   =  {-square2, full_edge, depth2}
    vertices[1].position   =  {square2, full_edge, depth2}
    vertices[2].position   =  {square2, square2, depth2}
    vertices[3].position   =  {full_edge, square2, depth2}
    vertices[4].position   =  {full_edge, -square2, depth2}
    vertices[5].position   =  {square2, -square2, depth2}
    vertices[6].position   =  {square2, -full_edge, depth2}
    vertices[7].position   =  {-square2, -full_edge, depth2}
    vertices[8].position   =  {-square2, -square2, depth2}
    vertices[9].position   =  {-full_edge, -square2, depth2}
    vertices[10].position  =  {-full_edge, square2, depth2}
    vertices[11].position  =  {-square2, square2, depth2}

    vertices[12].position  =   {-square2, full_edge, -depth2}
    vertices[13].position  =   {square2, full_edge, -depth2}
    vertices[14].position  =   {square2, square2, -depth2}
    vertices[15].position  =   {full_edge, square2, -depth2}
    vertices[16].position  =   {full_edge, -square2, -depth2}
    vertices[17].position  =   {square2, -square2, -depth2}
    vertices[18].position  =   {square2, -full_edge, -depth2}
    vertices[19].position  =   {-square2, -full_edge, -depth2}
    vertices[20].position  =   {-square2, -square2, -depth2}
    vertices[21].position  =   {-full_edge, -square2, -depth2}
    vertices[22].position  =   {-full_edge, square2, -depth2}
    vertices[23].position  =   {-square2, square2, -depth2}

    o: f32 = 0.5

    for i in 0..<len(vertices) {
        vertices[i].normal = {0,0,0}
        vertices[i].color = {1,1,1,1}
        vertices[i].uv_x = 0
        vertices[i].uv_y = 0
    }
    //12 outer faces
    index: int = 0

    //Full edge strip
    for i in u32(0)..<12 {
        top_left, top_right, bottom_left, bottom_right: u32

        top_right = i
        top_left = (top_right + 1) % 12
        bottom_right = top_right + 12
        bottom_left = top_left + 12

        indices[index] = top_left 
        indices[index+1] = bottom_left
        indices[index+2] = top_right

        indices[index+3] = top_right
        indices[index+4] = bottom_left
        indices[index+5] = bottom_right
        index += 6
    }
    //Cross Wings
    for i in u32(0)..<4 {
        top_left, top_right, bottom_left, bottom_right: u32
        shift := i * 3
        top_left = shift
        top_right = (shift + 1) % 12
        bottom_right = (shift + 2) % 12
        if i == 0 {
            bottom_left = 11
        }
        else {
            bottom_left = shift - 1
        }
        //Top triangles, counterclockwise from this perspective
        indices[index] = top_left 
        indices[index+1] = bottom_left
        indices[index+2] = top_right

        indices[index+3] = top_right
        indices[index+4] = bottom_left
        indices[index+5] = bottom_right       
        index += 6
        
        top_left += 12
        top_right += 12
        bottom_left += 12
        bottom_right += 12

        //bottom_triangles, these one are clockwise from this perspective
        indices[index] = top_right
        indices[index+1] = bottom_right
        indices[index+2] = top_left

        indices[index+3] = top_left
        indices[index+4] = bottom_right
        indices[index+5] = bottom_left
        index += 6
    }
        //Top Center Triangles
        indices[index] = 11
        indices[index+1] = 8
        indices[index+2] = 2

        indices[index+3] = 2
        indices[index+4] = 8
        indices[index+5] = 5
        index += 6   
        //Bottom Center Triangles 
        indices[index]   = 23
        indices[index+1] = 17
        indices[index+2] = 20

        indices[index+3] = 23
        indices[index+4] = 14
        indices[index+5] = 17
        index += 6   
 
    new_mesh := append_and_get_ref(meshes, Mesh_Asset{})

    new_mesh.name = strings.clone("Cross")
    new_mesh.surfaces = make([dynamic]Geo_Surface, context.allocator)
    new_surface: Geo_Surface
    new_surface.start_index = 0
    new_surface.count = u32(len(indices))

    append(&new_mesh.surfaces, new_surface)
    new_mesh.mesh_buffers = upload_mesh(engine, indices[:], vertices[:]) or_return

    return (len(meshes) - 1), true
}


generate_plane :: proc (engine: ^Engine, meshes: ^Mesh_Asset_List, size_x, size_y: u32, density: f32,) -> (mesh_index:int, ok: bool){

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
    x_gap := f32(size_x) / f32(x_gaps)
    y_gap := f32(size_y) / f32(y_gaps)


    //create vertices
    index: u32 = 0
    for y in 0..< y_vertices {
        for x in 0..< x_vertices {
            uv_x := f32(x) / f32(x_vertices)
            uv_y := f32(y) / f32(y_vertices)
            vertices[index] = {
                position = {x_gap * f32(x), y_gap * f32(y), 0},
                normal = {1,0,0},
                uv_x = uv_x,
                uv_y = uv_y,
                color = {(uv_x + uv_y) / 2.0, uv_x,uv_y, 1},
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


   return (len(meshes) - 1), true 

}


