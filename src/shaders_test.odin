package astro

import "core:fmt"
import "core:hash"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import vk "vendor:vulkan"
import spirv "libs:spirv-reflect"

TEST_SHADER_VERTEX :: `
struct V { float4 pos : SV_Position; [vk_location(0)] float3 color; };
V main(uint id : SV_VertexID) {
    V output;
    output.pos = float4(float(id), 0, 0, 1);
    output.color = float3(1, 0, 0);
    return output;
}`

TEST_SHADER_TESS_CONTROL :: `
struct V { float4 pos : SV_Position; [vk_location(0)] float3 color; };
struct Patch { float edge[3] : SV_TessFactor; float inside : SV_InsideTessFactor; };
Patch patchConstants(InputPatch<V, 3> input) {
    Patch p; p.edge[0] = 1; p.edge[1] = 1; p.edge[2] = 1; p.inside = 1; return p;
}
[domain("tri")]
[partitioning("integer")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[patchconstantfunc("patchConstants")]
V main(InputPatch<V, 3> input, uint id : SV_OutputControlPointID) { return input[id]; }`

TEST_SHADER_TESS_EVALUATION :: `
struct V { float4 pos : SV_Position; [vk_location(0)] float3 color; };
struct Patch { float edge[3] : SV_TessFactor; float inside : SV_InsideTessFactor; };
[domain("tri")]
V main(Patch patch, float3 bary : SV_DomainLocation, const OutputPatch<V, 3> input) {
    V output;
    output.pos = input[0].pos * bary.x + input[1].pos * bary.y + input[2].pos * bary.z;
    output.color = input[0].color;
    return output;
}`

TEST_SHADER_GEOMETRY :: `
struct V { float4 pos : SV_Position; [vk_location(0)] float3 color; };
[maxvertexcount(1)]
void main(point V input[1], inout PointStream<V> output) { output.Append(input[0]); }`

TEST_SHADER_FRAGMENT :: `
struct V { float4 pos : SV_Position; [vk_location(0)] float3 color; };
float4 main(V input) : SV_Target0 { return float4(input.color, 1); }`

TEST_SHADER_COMPUTE :: `[numthreads(1, 1, 1)] void main() {}`
TEST_SHADER_RAY :: `void main() {}`
TEST_SHADER_TASK :: `[shader("amplification")][numthreads(1, 1, 1)] void main() {}`
TEST_SHADER_MESH :: `
struct V { float4 pos : SV_Position; };
[outputtopology("triangle")]
[numthreads(1, 1, 1)]
void main(out vertices V verts[3], out indices uint3 tris[1]) {
    SetMeshOutputCounts(3, 1);
    verts[0].pos = float4(0, 0, 0, 1);
    verts[1].pos = float4(1, 0, 0, 1);
    verts[2].pos = float4(0, 1, 0, 1);
    tris[0] = uint3(0, 1, 2);
}`

@(test)
shader_stage_filename_test :: proc(t: ^testing.T) {
    cases := []struct {filename: string, stage: vk.ShaderStageFlag} {
        {"ocean.vert.slang", .VERTEX},
        {"ocean.vertex.slang", .VERTEX},
        {"ocean.tesc.slang", .TESSELLATION_CONTROL},
        {"ocean.tesscontrol.slang", .TESSELLATION_CONTROL},
        {"ocean.tess_control.slang", .TESSELLATION_CONTROL},
        {"ocean.hull.slang", .TESSELLATION_CONTROL},
        {"ocean.tessellation_control.slang", .TESSELLATION_CONTROL},
        {"ocean.tese.slang", .TESSELLATION_EVALUATION},
        {"ocean.tesseval.slang", .TESSELLATION_EVALUATION},
        {"ocean.tess_eval.slang", .TESSELLATION_EVALUATION},
        {"ocean.domain.slang", .TESSELLATION_EVALUATION},
        {"ocean.tessellation_evaluation.slang", .TESSELLATION_EVALUATION},
        {"ocean.geom.slang", .GEOMETRY},
        {"ocean.geometry.slang", .GEOMETRY},
        {"ocean.frag.slang", .FRAGMENT},
        {"ocean.fragment.slang", .FRAGMENT},
        {"ocean.pixel.slang", .FRAGMENT},
        {"ocean.comp.slang", .COMPUTE},
        {"ocean.compute.slang", .COMPUTE},
        {"ocean.rgen.slang", .RAYGEN_KHR},
        {"ocean.raygen.slang", .RAYGEN_KHR},
        {"ocean.raygeneration.slang", .RAYGEN_KHR},
        {"ocean.ray_generation.slang", .RAYGEN_KHR},
        {"ocean.rint.slang", .INTERSECTION_KHR},
        {"ocean.intersection.slang", .INTERSECTION_KHR},
        {"ocean.rahit.slang", .ANY_HIT_KHR},
        {"ocean.anyhit.slang", .ANY_HIT_KHR},
        {"ocean.any_hit.slang", .ANY_HIT_KHR},
        {"ocean.rchit.slang", .CLOSEST_HIT_KHR},
        {"ocean.closesthit.slang", .CLOSEST_HIT_KHR},
        {"ocean.closest_hit.slang", .CLOSEST_HIT_KHR},
        {"ocean.rmiss.slang", .MISS_KHR},
        {"ocean.miss.slang", .MISS_KHR},
        {"ocean.rcall.slang", .CALLABLE_KHR},
        {"ocean.callable.slang", .CALLABLE_KHR},
        {"ocean.task.slang", .TASK_EXT},
        {"ocean.amplification.slang", .TASK_EXT},
        {"ocean.mesh.slang", .MESH_EXT},
        {"nested/ocean.debug.geom.slang", .GEOMETRY},
        {"common.slang", ._MAX},
        {"ocean.unknown.slang", ._MAX},
        {"ocean.geom", ._MAX},
    }
    for tc in cases {
        stage := shader_determine_stage(tc.filename)
        testing.expectf(t, stage == tc.stage, "%v: expected %v, got %v", tc.filename, tc.stage, stage)
    }
}

@(test)
shader_compile_all_stages_test :: proc(t: ^testing.T) {
    compiler: Slang_Compiler
    if !testing.expect(t, slang_compiler_init(&compiler)) do return
    defer slang_compiler_deinit(&compiler)

    cases := []struct {stage: vk.ShaderStageFlag, source: string} {
        {.VERTEX, TEST_SHADER_VERTEX},
        {.TESSELLATION_CONTROL, TEST_SHADER_TESS_CONTROL},
        {.TESSELLATION_EVALUATION, TEST_SHADER_TESS_EVALUATION},
        {.GEOMETRY, TEST_SHADER_GEOMETRY},
        {.FRAGMENT, TEST_SHADER_FRAGMENT},
        {.COMPUTE, TEST_SHADER_COMPUTE},
        {.RAYGEN_KHR, TEST_SHADER_RAY},
        {.INTERSECTION_KHR, TEST_SHADER_RAY},
        {.ANY_HIT_KHR, TEST_SHADER_RAY},
        {.CLOSEST_HIT_KHR, TEST_SHADER_RAY},
        {.MISS_KHR, TEST_SHADER_RAY},
        {.CALLABLE_KHR, TEST_SHADER_RAY},
        {.TASK_EXT, TEST_SHADER_TASK},
        {.MESH_EXT, TEST_SHADER_MESH},
    }
    for tc in cases {
        expected := shader_slang_stage(tc.stage)
        compiled, ok := slang_compile_module(&compiler, tc.source, expected_stage = expected)
        if !testing.expectf(t, ok, "Could not compile %v", tc.stage) do continue
        defer slang_compiled_module_destroy(&compiled)

        testing.expectf(t, len(compiled.entry_points) == 1, "%v entry point count", tc.stage)
        if len(compiled.entry_points) == 1 {
            testing.expectf(t, compiled.entry_points[0].stage == expected, "%v reflected stage", tc.stage)
        }
        names, valid := spirv_entry_point_names(compiled.spirv, tc.stage)
        if testing.expectf(t, valid, "%v SPIR-V entry point stage", tc.stage) {
            testing.expectf(t, len(names) == 1 && names[0] == "main", "%v entry point name", tc.stage)
            for name in names do delete(name)
            delete(names)
        }
        if tc.stage == .TASK_EXT || tc.stage == .MESH_EXT {
            words := mem.slice_data_cast([]u32, compiled.spirv)
            testing.expectf(t, len(words) >= 2 && words[1] >= 0x00010400, "%v requires SPIR-V 1.4", tc.stage)
        }
    }
    testing.expect(t, shader_spirv_stage(u32(spirv.SpvExecutionModel.TaskNV)) == .TASK_EXT)
    testing.expect(t, shader_spirv_stage(u32(spirv.SpvExecutionModel.MeshNV)) == .MESH_EXT)
}

@(test)
shader_tagged_entry_points_test :: proc(t: ^testing.T) {
    compiler: Slang_Compiler
    if !testing.expect(t, slang_compiler_init(&compiler)) do return
    defer slang_compiler_deinit(&compiler)

    source := `
    [[vk_binding(0, 1)]] RWTexture2D<float4> image_a;
    [[vk_binding(1, 1)]] RWTexture2D<float4> image_b;
    [shader("compute")][numthreads(1, 1, 1)]
    void first(uint3 id : SV_DispatchThreadID) { image_a[id.xy] = float4(1, 0, 0, 1); }
    [shader("compute")][numthreads(1, 1, 1)]
    void second(uint3 id : SV_DispatchThreadID) { image_b[id.xy] = float4(0, 1, 0, 1); }`
    compiled, ok := slang_compile_module(&compiler, source, expected_stage = SLANG_STAGE_COMPUTE)
    if !testing.expect(t, ok) do return
    defer slang_compiled_module_destroy(&compiled)
    names, valid := spirv_entry_point_names(compiled.spirv, .COMPUTE)
    if testing.expect(t, valid) {
        defer delete(names)
        defer for name in names do delete(name)
        testing.expect(t, len(names) == 2)
        if len(names) == 2 {
            testing.expect(t, names[0] == "first" && names[1] == "second")
        }
    }
    layout, layout_ok := shaders_generate_raw_layout_compute(nil, {
        compute = {name = "multi", stage = .COMPUTE, spirv_bytes = compiled.spirv},
    })
    defer delete_reflected_shaders(&layout)
    if testing.expect(t, layout_ok) {
        testing.expect(t, "image_a" in layout.binding_by_name && "image_b" in layout.binding_by_name)
        testing.expect(t, .COMPUTE in layout.layout[1][0].stageFlags && .COMPUTE in layout.layout[1][1].stageFlags)
    }
    _, wrong_stage := spirv_entry_point_names(compiled.spirv, .GEOMETRY)
    testing.expect(t, !wrong_stage)
    _, truncated := spirv_entry_point_names(compiled.spirv[:len(compiled.spirv) - 1], .COMPUTE)
    testing.expect(t, !truncated)
    unterminated := [?]u32{0x07230203, 0x00010400, 0, 3, 0, (4 << 16) | 15, 3, 1, 0x41414141}
    _, unterminated_ok := spirv_entry_point_names(mem.slice_data_cast([]byte, unterminated[:]), .GEOMETRY)
    testing.expect(t, !unterminated_ok)
    mixed := [?]u32{
        0x07230203, 0x00010400, 0, 3, 0,
        (5 << 16) | 15, 5, 1, 0x6e69616d, 0,
        (5 << 16) | 15, 4, 2, 0x6e69616d, 0,
    }
    _, mixed_ok := spirv_entry_point_names(mem.slice_data_cast([]byte, mixed[:]), .COMPUTE)
    testing.expect(t, !mixed_ok)

    previous_logger := context.logger
    context.logger = log.nil_logger()
    _, mismatch := slang_compile_module(&compiler, source, expected_stage = SLANG_STAGE_GEOMETRY)
    _, untagged_task := slang_compile_module(&compiler, TEST_SHADER_COMPUTE, expected_stage = SLANG_STAGE_AMPLIFICATION)
    context.logger = previous_logger
    testing.expect(t, !mismatch)
    testing.expect(t, !untagged_task)
}

@(test)
shader_manager_all_stages_test :: proc(t: ^testing.T) {
    root, err := os.make_directory_temp("", "astro-all-stages-*", context.allocator)
    if !testing.expect(t, err == nil) do return
    defer delete(root)
    defer os.remove_all(root)
    if !testing.expect(t, os.make_directory_all(fmt.tprintf("%s/source", root)) == nil) do return

    cases := []struct {suffix: string, stage: vk.ShaderStageFlag, source: string} {
        {"vert", .VERTEX, TEST_SHADER_VERTEX},
        {"tesc", .TESSELLATION_CONTROL, TEST_SHADER_TESS_CONTROL},
        {"tese", .TESSELLATION_EVALUATION, TEST_SHADER_TESS_EVALUATION},
        {"geom", .GEOMETRY, TEST_SHADER_GEOMETRY},
        {"frag", .FRAGMENT, TEST_SHADER_FRAGMENT},
        {"comp", .COMPUTE, TEST_SHADER_COMPUTE},
        {"rgen", .RAYGEN_KHR, TEST_SHADER_RAY},
        {"rint", .INTERSECTION_KHR, TEST_SHADER_RAY},
        {"rahit", .ANY_HIT_KHR, TEST_SHADER_RAY},
        {"rchit", .CLOSEST_HIT_KHR, TEST_SHADER_RAY},
        {"rmiss", .MISS_KHR, TEST_SHADER_RAY},
        {"rcall", .CALLABLE_KHR, TEST_SHADER_RAY},
        {"task", .TASK_EXT, TEST_SHADER_TASK},
        {"mesh", .MESH_EXT, TEST_SHADER_MESH},
    }
    for tc in cases {
        path := fmt.tprintf("%s/source/all.%s.slang", root, tc.suffix)
        if !testing.expect(t, os.write_entire_file(path, tc.source) == nil) do return
    }

    manager: Shader_Manager
    manager.shaders = make(map[string]Shader)
    manager.shader_dirs = make([dynamic]Shader_Dir)
    if !testing.expect(t, slang_compiler_init(&manager.slang_compiler)) do return
    defer shader_manager_deinit(&manager)
    if !testing.expect(t, shader_manager_add_directory(&manager, fmt.tprintf("%s/", root), .Game)) do return
    testing.expect(t, len(manager.shaders) == len(cases))
    // A second scan exercises the cached path for every stage.
    if !testing.expect(t, shader_manager_update_shaders(&manager, &manager.shader_dirs[0], "")) do return
    for tc in cases {
        key := fmt.tprintf("game/all.%s", tc.suffix)
        shader, found := manager.shaders[key]
        if !testing.expectf(t, found, "Missing shader %s", key) do continue
        testing.expectf(t, shader.stage == tc.stage && len(shader.entry_points) == 1, "Wrong stage or entry points for %s", key)
        names, valid := spirv_entry_point_names(shader.spirv_bytes, tc.stage)
        testing.expectf(t, valid, "Invalid cached SPIR-V for %s", key)
        for name in names do delete(name)
        delete(names)
    }
}

@(test)
shader_graphics_stage_order_test :: proc(t: ^testing.T) {
    compiler: Slang_Compiler
    if !testing.expect(t, slang_compiler_init(&compiler)) do return
    defer slang_compiler_deinit(&compiler)

    stages := [?]vk.ShaderStageFlag{.VERTEX, .TESSELLATION_CONTROL, .TESSELLATION_EVALUATION, .GEOMETRY, .FRAGMENT}
    sources := [?]string{TEST_SHADER_VERTEX, TEST_SHADER_TESS_CONTROL, TEST_SHADER_TESS_EVALUATION, TEST_SHADER_GEOMETRY, TEST_SHADER_FRAGMENT}
    modules: [5]Slang_Compiled_Module
    defer for &module in modules do slang_compiled_module_destroy(&module)
    shaders: [5]Shader
    for i in 0..<len(stages) {
        compiled, ok := slang_compile_module(&compiler, sources[i], expected_stage = shader_slang_stage(stages[i]))
        if !testing.expectf(t, ok, "Could not compile graphics stage %v", stages[i]) do return
        modules[i] = compiled
        shaders[i] = {name = "test", stage = stages[i], spirv_bytes = modules[i].spirv}
    }
    layout, ok := shaders_generate_raw_layout_render(nil, {
        vertex = shaders[0],
        tessellation_control = shaders[1],
        tessellation_evaluation = shaders[2],
        geometry = shaders[3],
        fragment = shaders[4],
    })
    defer delete_reflected_shaders(&layout)
    if !testing.expect(t, ok) do return
    if testing.expect(t, len(layout.stage_params) == len(stages)) {
        for stage, i in stages {
            testing.expectf(t, layout.stage_params[i].stage == stage, "Graphics stage order at %v", i)
        }
    }
    testing.expect(t, validate_input_outputs(&layout.stage_params))

    geometry_layout, geometry_ok := shaders_generate_raw_layout_render(nil, {
        vertex = shaders[0], geometry = shaders[3], fragment = shaders[4],
    })
    defer delete_reflected_shaders(&geometry_layout)
    if testing.expect(t, geometry_ok && len(geometry_layout.stage_params) == 3) {
        testing.expect(t, geometry_layout.stage_params[1].stage == .GEOMETRY)
        testing.expect(t, validate_input_outputs(&geometry_layout.stage_params))
    }

    previous_logger := context.logger
    context.logger = log.nil_logger()
    incomplete, incomplete_ok := shaders_generate_raw_layout_render(nil, {
        vertex = shaders[0], tessellation_evaluation = shaders[2], fragment = shaders[4],
    })
    context.logger = previous_logger
    defer delete_reflected_shaders(&incomplete)
    testing.expect(t, !incomplete_ok)
}

@(test)
shader_manager_nested_cache_and_failure_test :: proc(t: ^testing.T) {
    root, err := os.make_directory_temp("", "astro-shader-test-*", context.allocator)
    if !testing.expect(t, err == nil) do return
    defer delete(root)
    defer os.remove_all(root)

    source_dir := fmt.tprintf("%s/source/nested", root)
    if !testing.expect(t, os.make_directory_all(source_dir) == nil) do return
    include_path := fmt.tprintf("%s/source/common.slang", root)
    geometry_path := fmt.tprintf("%s/source/nested/surface.debug.geom.slang", root)
    named_path := fmt.tprintf("%s/source/nested/named.geometry.slang", root)
    callable_path := fmt.tprintf("%s/source/nested/payload.rcall.slang", root)
    include := `struct V { float4 pos : SV_Position; [vk_location(0)] float3 color; };`
    geometry := `#include "../common.slang"
[maxvertexcount(1)]
void main(point V input[1], inout PointStream<V> output) { output.Append(input[0]); }`
    named_geometry := `#include "../common.slang"
[shader("geometry")][maxvertexcount(1)]
void draw_normals(point V input[1], inout PointStream<V> output) { output.Append(input[0]); }`
    if !testing.expect(t, os.write_entire_file(include_path, transmute([]byte)include) == nil) do return
    if !testing.expect(t, os.write_entire_file(geometry_path, transmute([]byte)geometry) == nil) do return
    if !testing.expect(t, os.write_entire_file(named_path, transmute([]byte)named_geometry) == nil) do return
    if !testing.expect(t, os.write_entire_file(callable_path, string(TEST_SHADER_RAY)) == nil) do return

    manager: Shader_Manager
    manager.shaders = make(map[string]Shader)
    manager.shader_dirs = make([dynamic]Shader_Dir)
    if !testing.expect(t, slang_compiler_init(&manager.slang_compiler)) do return
    defer shader_manager_deinit(&manager)
    directory := fmt.tprintf("%s/", root)
    if !testing.expect(t, shader_manager_add_directory(&manager, directory, .Game)) do return
    direct, direct_ok := shader_manager_compile_shader(&manager, &manager.shader_dirs[0], geometry_path)
    if !testing.expect(t, direct_ok) do return
    defer slang_compiled_module_destroy(&direct)
    geometry_key := "game/nested/surface.debug.geom"
    named_key := "game/nested/named.geometry"
    callable_key := "game/nested/payload.rcall"
    testing.expect(t, len(manager.shaders) == 3)
    shader, found := manager.shaders[geometry_key]
    if !testing.expect(t, found) do return
    testing.expect(t, shader.stage == .GEOMETRY)
    callable, found_callable := manager.shaders[callable_key]
    testing.expect(t, found_callable && callable.stage == .CALLABLE_KHR)
    named, found_named := manager.shaders[named_key]
    if !testing.expect(t, found_named && len(named.entry_points) == 1) do return
    named_entry := strings.clone(named.entry_points[0])
    defer delete(named_entry)
    testing.expect(t, named_entry == "draw_normals")
    reflection: spirv.SpvReflectShaderModule
    if !testing.expect(t, spirv.spvReflectCreateShaderModule(uint(len(named.spirv_bytes)), raw_data(named.spirv_bytes), &reflection) == .SUCCESS) do return
    testing.expect(t, named_entry == string(reflection.entry_point_name))
    spirv.spvReflectDestroyShaderModule(&reflection)

    cache_path := strings.clone(shader.compiled_path)
    defer delete(cache_path)
    cache_time := shader.modify_time
    fragment, fragment_ok := slang_compile_module(&manager.slang_compiler, TEST_SHADER_FRAGMENT, expected_stage = SLANG_STAGE_FRAGMENT)
    if !testing.expect(t, fragment_ok) do return
    defer slang_compiled_module_destroy(&fragment)
    if !testing.expect(t, os.write_entire_file(cache_path, fragment.spirv) == nil) do return
    if !testing.expect(t, os.change_times(cache_path, time.now(), cache_time) == nil) do return
    testing.expect(t, shader_manager_update_shaders(&manager, &manager.shader_dirs[0], ""))
    after_reload := manager.shaders[named_key]
    testing.expect(t, len(after_reload.entry_points) == 1 && after_reload.entry_points[0] == named_entry)

    if !testing.expect(t, os.write_entire_file(cache_path, []byte{1, 2, 3, 4}) == nil) do return
    if !testing.expect(t, os.change_times(cache_path, time.now(), cache_time) == nil) do return
    testing.expect(t, shader_manager_update_shaders(&manager, &manager.shader_dirs[0], ""))
    repaired := manager.shaders[geometry_key]
    names, valid := spirv_entry_point_names(repaired.spirv_bytes, .GEOMETRY)
    if testing.expect(t, valid) {
        for name in names do delete(name)
        delete(names)
    }
    include_time := time.time_add(cache_time, 2 * time.Second)
    if !testing.expect(t, os.change_times(include_path, time.now(), include_time) == nil) do return
    testing.expect(t, shader_manager_update_shaders(&manager, &manager.shader_dirs[0], ""))
    repaired = manager.shaders[geometry_key]
    testing.expect(t, repaired.modify_time == include_time)
    cache_time = repaired.modify_time
    original_hash := hash.fnv64a(repaired.spirv_bytes)

    unknown_path := fmt.tprintf("%s/source/nested/not-a-stage.unknown.slang", root)
    if !testing.expect(t, os.write_entire_file(unknown_path, string(TEST_SHADER_RAY)) == nil) do return
    previous_logger := context.logger
    context.logger = log.nil_logger()
    manager.compile_only = true
    unknown_ok := shader_manager_update_shaders(&manager, &manager.shader_dirs[0], "")
    manager.compile_only = false
    context.logger = previous_logger
    testing.expect(t, !unknown_ok)
    if !testing.expect(t, os.remove(unknown_path) == nil) do return

    if !testing.expect(t, os.write_entire_file(geometry_path, string(`this is invalid slang`)) == nil) do return
    if !testing.expect(t, os.change_times(geometry_path, time.now(), time.time_add(cache_time, time.Second)) == nil) do return
    context.logger = log.nil_logger()
    updated := shader_manager_update_shaders(&manager, &manager.shader_dirs[0], "")
    manager.compile_only = true
    worker_updated := shader_manager_update_shaders(&manager, &manager.shader_dirs[0], "")
    manager.compile_only = false
    context.logger = previous_logger
    testing.expect(t, !updated && !worker_updated)
    old_shader, still_present := manager.shaders[geometry_key]
    testing.expect(t, still_present && hash.fnv64a(old_shader.spirv_bytes) == original_hash)

    second: Shader_Manager
    second.shaders = make(map[string]Shader)
    second.shader_dirs = make([dynamic]Shader_Dir)
    if !testing.expect(t, slang_compiler_init(&second.slang_compiler)) do return
    defer shader_manager_deinit(&second)
    context.logger = log.nil_logger()
    added := shader_manager_add_directory(&second, directory, .Game)
    context.logger = previous_logger
    testing.expect(t, !added && second.build_status == .Failed)
    testing.expect(t, callable_key in second.shaders)
}
