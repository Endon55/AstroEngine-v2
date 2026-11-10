package astro

import "core:strings"
import "core:log"
import "core:os"
import "core:path/filepath"
import "base:runtime"
import "core:time"
import "core:thread"
import "core:sync/chan"
import "core:mem"
import "core:hash"
import "core:math/bits"

import vk "vendor:vulkan"
import spirv "libs:spirv-reflect"

// v3 uses filename-aware stages, SPIR-V 1.4, and preserved entry-point names.
SHADER_CACHE_VERSION :: "v3"

Shader :: struct {
    name: string,
    compiled_path: string,
    source_path: string,
    stage: vk.ShaderStageFlag,
    modify_time: time.Time,
    spirv_bytes: []byte,
    // Every entry point contained in `spirv_bytes`, in SPIR-V order. Multi-entry-point
    // modules keep all their pipelines compatible with one layout.
    entry_points: []string,
    //Not Guaranteed to be valid, call Shader_Get_Module().
    module: vk.ShaderModule,
}
Shader_Dir::struct {
    shader_directory: string,
    compiled_directory: string,
    source_directory: string,
    domain: Shader_Domain,
}
Shader_Domain :: enum {
    Engine,
    Game,
}
Shader_Manager::struct {
    shader_dirs: [dynamic]Shader_Dir,
    shaders: map[string]Shader,
    slang_compiler: Slang_Compiler, 
    build_status: Build_Status,
    hot_reload_thread: ^thread.Thread,
    hot_reload_args: Shader_Compiler_Worker_Args,
    compile_only: bool,
}
Shader_Compiler_Worker_Args :: struct {
    build_status_pipe: chan.Chan(Build_Status),
    thread_status_pipe: chan.Chan(Thread_Status),
    manager: ^Shader_Manager,
}

shader_manager_get_shader_index_by_name :: proc (self:^Shader_Manager, name:string) -> ^Shader{
    if name in self.shaders {
        return &self.shaders[name]
    }
    game_key := shader_manager_qualify_name(.Game, name)
    if game_key in self.shaders {
        defer delete(game_key)
        return &self.shaders[game_key]
    }
    delete(game_key)
    engine_key := shader_manager_qualify_name(.Engine, name)
    if engine_key in self.shaders {
        defer delete(engine_key)
        return &self.shaders[engine_key]
    }
    delete(engine_key)
    return nil
}
shader_manager_add_directory :: proc(self: ^Shader_Manager, directory: string, domain: Shader_Domain = .Engine, allocator:=context.allocator) ->(ok:bool) {
    
    shader_dir : Shader_Dir 
    shader_dir.shader_directory = strings.clone(directory) 
    shader_dir.compiled_directory = quick_concat({shader_dir.shader_directory, "compiled/"}, allocator) or_return
    shader_dir.source_directory = quick_concat({shader_dir.shader_directory, "source/"}, allocator) or_return
    shader_dir.domain = domain
     
    append(&self.shader_dirs, shader_dir)
    ok = shader_manager_update_shaders(self, &self.shader_dirs[len(self.shader_dirs) - 1], "")
    if !ok {
        self.build_status = .Failed
    }
    return ok
}

shader_manager_get_shader :: proc(self:^Shader_Manager, name: string, loc:=#caller_location) -> (shader: Shader, ok:bool) {

    if shader, found := self.shaders[name]; found {
        return shader, true
    }
    game_key := shader_manager_qualify_name(.Game, name)
    if shader, found := self.shaders[game_key]; found {
        delete(game_key)
        return shader, true
    }
    delete(game_key)
    engine_key := shader_manager_qualify_name(.Engine, name)
    if shader, found := self.shaders[engine_key]; found {
        delete(engine_key)
        return shader, true
    }
    delete(engine_key)
    log.warnf("Couldn't find shader: %v, Total Shader Count: %v, loc: %v", name, len(self.shaders), loc)
    for key, value in self.shaders {

        log.warnf("Available Shaders: %v",key)
    }
    return shader, false
}

shader_manager_qualify_name :: proc(domain: Shader_Domain, name: string) -> string {
    prefix := domain == .Game ? "game/" : "engine/"
    return quick_concat({prefix, name}) or_else ""
}

shader_manager_update :: proc(self: ^Shader_Manager, engine: ^Engine) {
    if self.hot_reload_thread == nil {
        log.errorf("Hot reload thread doesn't exist home boy")
        return
    }

    if build_status, has_output := chan.try_recv(self.hot_reload_args.build_status_pipe); has_output {
        self.build_status = build_status
        switch build_status {
        case .Success:
        self.build_status = build_status
            for &shader_dir in self.shader_dirs {
                if !shader_manager_update_shaders(self, &shader_dir, "") {
                    self.build_status = .Failed
                }
            }
            if self.build_status == .Success {
                if !engine_build_pipelines(engine) {
                } else if !game_manager_game_build_pipelines(&engine.game_manager, &engine.scene, engine) {
                    log.errorf("Failed to rebuild pipelines after a recompile")
                }
            }
            if !chan.try_send(self.hot_reload_args.thread_status_pipe, Thread_Status.Continue) {
                log.errorf("Failed to resume the shader compiler thread")
            }
        case .Failed:
            self.build_status = build_status
            log.errorf("Shader compilation failed")
            if !chan.try_send(self.hot_reload_args.thread_status_pipe, Thread_Status.Continue) {
                log.errorf("Failed to resume the shader compiler thread")
            }
        case .Compiling:
            self.build_status = build_status
        case .Idle:
        }
    }
}


shader_manager_init :: proc(self: ^Shader_Manager) -> (ok: bool) {

    self.shaders = make(map[string]Shader)
    self.shader_dirs = make([dynamic]Shader_Dir)
    slang_compiler_init(&self.slang_compiler) or_return


    calling_directory := quick_calling_dir(context.allocator) or_return
    shader_dir := quick_concat({calling_directory, "/shaders/"}) or_return
    self.build_status = .Success
    ok = shader_manager_add_directory(self, shader_dir)
    delete(calling_directory)
    delete(shader_dir)

    return ok
}

SHADER_COMPILE_DEBOUNCE :: time.Second * 3
SHADER_POLL_INTERVAL :: time.Second

shader_manager_start_hot_reload :: proc(self: ^Shader_Manager) -> (ok: bool) {
    build_status, _ := chan.create_buffered(chan.Chan(Build_Status), 5, context.allocator)
    thread_status, _ := chan.create_buffered(chan.Chan(Thread_Status), 5, context.allocator)
    self.hot_reload_args = {
        build_status_pipe = build_status,
        thread_status_pipe = thread_status,
        manager = self,
    }
    self.hot_reload_thread = thread.create_and_start_with_data(rawptr(&self.hot_reload_args), shader_compiler_thread_proc)
    thread.start(self.hot_reload_thread)
    return true
}

@(private="file")
shader_compiler_thread_proc :: proc(data: rawptr) {
    // The main thread's allocator (tracking) is not thread safe, so the worker uses the plain heap.
    context.allocator = runtime.heap_allocator()
    context.logger = g_logger
    args := cast(^Shader_Compiler_Worker_Args)data
    manager := args.manager
    build_status_pipe := args.build_status_pipe
    thread_status_pipe := args.thread_status_pipe

    // The worker only compiles stale shaders to disk; the main thread loads the results.
    worker_manager: Shader_Manager
    worker_manager.compile_only = true
    worker_manager.shader_dirs = manager.shader_dirs
    if !slang_compiler_init(&worker_manager.slang_compiler) {
        log.errorf("Slang Compiler failed to initialize")
        if !chan.try_send(build_status_pipe, Build_Status.Failed) {

        }
        return
    }
    defer slang_compiler_deinit(&worker_manager.slang_compiler)

    scratch: mem.Dynamic_Arena
    mem.dynamic_arena_init(&scratch)
    defer mem.dynamic_arena_destroy(&scratch)
    scratch_allocator := mem.dynamic_arena_allocator(&scratch)

    applied := shader_source_fingerprint(manager, scratch_allocator)
    observed := applied
    mem.dynamic_arena_free_all(&scratch)
    last_change := time.now()
    thread_status: Thread_Status = .Continue

    for thread_status != .Stop {
        if new_status, has_data := chan.try_recv(thread_status_pipe); has_data {
            thread_status = new_status
        }
        if thread_status == .Stop {
            break
        }

        // While waiting on the main thread there is nothing to do.
        if thread_status == .Continue {
            current := shader_source_fingerprint(manager, scratch_allocator)
            mem.dynamic_arena_free_all(&scratch)
            if current != observed {
                observed = current
                last_change = time.now()
                log.debugf("Shader sources changed, recompiling in %v", SHADER_COMPILE_DEBOUNCE)
            }

            if observed != applied && time.diff(last_change, time.now()) >= SHADER_COMPILE_DEBOUNCE {
                if !chan.try_send(build_status_pipe, Build_Status.Compiling) {
                    log.error("Failed to send shader compiling status")
                    break
                }

                compile_ok := true
                for &shader_dir in manager.shader_dirs {
                    if !shader_manager_update_shaders(&worker_manager, &shader_dir, "") {
                        compile_ok = false
                    }
                }
                applied = observed

                result: Build_Status = compile_ok ? .Success : .Failed
                if !chan.try_send(build_status_pipe, result) {
                    log.errorf("Failed to send shader compile result: %v", result)
                    break
                }
                thread_status = .Wait
            }
        }

        time.sleep(SHADER_POLL_INTERVAL)
    }
}

// Order independent hash of every shader source path and modification time.
@(private="file")
shader_source_fingerprint :: proc(self: ^Shader_Manager, allocator: runtime.Allocator) -> (fingerprint: u64) {
    for shader_dir in self.shader_dirs {
        fingerprint += shader_source_fingerprint_dir(shader_dir.source_directory, allocator)
    }
    return
}

@(private="file")
shader_source_fingerprint_dir :: proc(dir: string, allocator: runtime.Allocator) -> (fingerprint: u64) {
    file_infos, ok := load_directory_contents_from_disc(dir, allocator)
    if !ok {
        return
    }
    for file_info in file_infos {
        if file_info.type == .Directory {
            fingerprint += shader_source_fingerprint_dir(file_info.fullpath, allocator)
        } else if strings.ends_with(file_info.name, ".slang") {
            path_hash := hash.fnv64a(transmute([]byte)file_info.fullpath)
            time_hash := u64(time.to_unix_nanoseconds(file_info.modification_time)) * 0x9E3779B97F4A7C15
            fingerprint += path_hash ~ time_hash
        }
    }
    return
}

shader_manager_is_out_of_date :: proc(self: ^Shader) ->(ok:bool,) {

    if os.exists(self.compiled_path)
    {
        compile_info, err := os.stat(self.compiled_path, context.allocator)
        if err != os.ERROR_NONE {
            log.errorf("Failed to read file data from: %v", self.compiled_path)
            return true
        }

        defer delete(compile_info.fullpath)

        if self.modify_time != compile_info.modification_time {
            // log.debugf(
            //     "shader(%v) is stale: newest source/include time %v, cached SPIR-V time %v",
            //     self.name,
            //     self.modify_time,
            //     compile_info.modification_time,
            // )
            return true
        }
        return false
    }
    return true
}

// ---------------------------------------------------------------------------
// Include dependency tracking
// ---------------------------------------------------------------------------
// `#include`/`#import` files are not compiled as standalone shaders, so they have
// no cache entry of their own. If a shared header changes (for example, a uniform
// struct gains a field) every shader that includes it must be recompiled. Without
// this the GPU would keep using cached SPIR-V with the old struct layout, which can
// read the wrong uniform member and index a bindless descriptor array out of bounds
// (a GPU hang, not a validation error).
//
// These helpers walk the include graph and return the newest modification time
// across a shader and everything it pulls in.

@(private = "file")
shader_path_directory :: proc(path: string) -> string {
    for i := len(path) - 1; i >= 0; i -= 1 {
        if path[i] == '/' || path[i] == '\\' {
            return path[:i]
        }
    }
    return "."
}

// Extracts the contents of the first double-quoted string in `line`.
@(private = "file")
shader_extract_quoted :: proc(line: string) -> (value: string, ok: bool) {
    open := strings.index_byte(line, '"')
    if open < 0 {
        return "", false
    }
    rest := line[open + 1:]
    close := strings.index_byte(rest, '"')
    if close < 0 {
        return "", false
    }
    return rest[:close], true
}

// Resolves an include name the same way Slang does: relative to the including
// file first, then against every configured shader source directory.
@(private = "file")
shader_resolve_include :: proc(
    self: ^Shader_Manager,
    including_file: string,
    name: string,
    allocator := context.allocator,
) -> (resolved: string, ok: bool) {
    if filepath.is_abs(name) {
        if os.exists(name) {
            return strings.clone(name, allocator), true
        }
        return "", false
    }

    local, local_err := strings.concatenate({shader_path_directory(including_file), "/", name}, allocator)
    if local_err == nil {
        if os.exists(local) {
            return local, true
        }
        delete(local, allocator)
    }

    for shader_dir in self.shader_dirs {
        candidate, candidate_err := strings.concatenate({shader_dir.source_directory, name}, allocator)
        if candidate_err != nil {
            continue
        }
        if os.exists(candidate) {
            return candidate, true
        }
        delete(candidate, allocator)
    }
    return "", false
}

@(private = "file")
shader_source_latest_time :: proc(
    self: ^Shader_Manager,
    path: string,
    visited: ^map[string]bool,
    allocator := context.allocator,
) -> (latest: time.Time, latest_path: string, ok: bool) {
    latest_path = path
    if path in visited^ {
        return {}, latest_path, true
    }
    visited^[path] = true

    info, stat_ok := quick_file_stat(path)
    if !stat_ok {
        return {}, latest_path, false
    }
    latest = info.modification_time
    delete(info.fullpath)

    source, read_ok := load_file_from_disc(path, allocator = allocator)
    if !read_ok {
        return latest, latest_path, true
    }

    remaining := string(source)
    for {
        line, has_line := strings.split_lines_iterator(&remaining)
        if !has_line {
            break
        }

        trimmed := strings.trim_space(line)
        if !strings.has_prefix(trimmed, "#include") &&
           !strings.has_prefix(trimmed, "#import") &&
           !strings.has_prefix(trimmed, "import") {
            continue
        }

        name, has_name := shader_extract_quoted(trimmed)
        if !has_name {
            continue
        }

        resolved, resolved_ok := shader_resolve_include(self, path, name, allocator)
        defer delete(resolved, allocator)
        if !resolved_ok {
            log.warnf("Could not resolve shader dependency '%v' included by '%v'", name, path)
            continue
        }

        dependency_time, dependency_path, dependency_ok := shader_source_latest_time(self, resolved, visited, allocator)
        if !dependency_ok {
            continue
        }
        if time.to_unix_nanoseconds(dependency_time) > time.to_unix_nanoseconds(latest) {
            latest = dependency_time
            latest_path = dependency_path
        }
    }

    return latest, latest_path, true
}

// The stage is the last component before .slang, so names may themselves contain dots.
// Files without a stage suffix are treated as includes by the directory scanner.
shader_determine_stage :: proc(filename: string) -> (stage: vk.ShaderStageFlag) {
    base := filepath.base(filename)
    if !strings.ends_with(base, ".slang") {
        return ._MAX
    }
    stem := base[:len(base) - len(".slang")]
    dot := strings.last_index_byte(stem, '.')
    if dot < 0 {
        return ._MAX
    }

    switch stem[dot + 1:] {
    case "vert", "vertex":                                      return .VERTEX
    case "tesc", "tesscontrol", "tess_control", "tessellation_control", "hull":
        return .TESSELLATION_CONTROL
    case "tese", "tesseval", "tess_eval", "tessellation_evaluation", "domain":
        return .TESSELLATION_EVALUATION
    case "geom", "geometry":                                    return .GEOMETRY
    case "frag", "fragment", "pixel":                           return .FRAGMENT
    case "comp", "compute":                                     return .COMPUTE
    case "rgen", "raygen", "raygeneration", "ray_generation":   return .RAYGEN_KHR
    case "rint", "intersection":                                return .INTERSECTION_KHR
    case "rahit", "anyhit", "any_hit":                          return .ANY_HIT_KHR
    case "rchit", "closesthit", "closest_hit":                  return .CLOSEST_HIT_KHR
    case "rmiss", "miss":                                       return .MISS_KHR
    case "rcall", "callable":                                   return .CALLABLE_KHR
    case "task", "amplification":                               return .TASK_EXT
    case "mesh":                                                return .MESH_EXT
    }
    return ._MAX
}

@(private)
shader_slang_stage :: proc(stage: vk.ShaderStageFlag) -> SlangStage {
    #partial switch stage {
    case .VERTEX:                  return SLANG_STAGE_VERTEX
    case .TESSELLATION_CONTROL:    return SLANG_STAGE_HULL
    case .TESSELLATION_EVALUATION: return SLANG_STAGE_DOMAIN
    case .GEOMETRY:                return SLANG_STAGE_GEOMETRY
    case .FRAGMENT:                return SLANG_STAGE_FRAGMENT
    case .COMPUTE:                 return SLANG_STAGE_COMPUTE
    case .RAYGEN_KHR:              return SLANG_STAGE_RAY_GENERATION
    case .INTERSECTION_KHR:        return SLANG_STAGE_INTERSECTION
    case .ANY_HIT_KHR:             return SLANG_STAGE_ANY_HIT
    case .CLOSEST_HIT_KHR:         return SLANG_STAGE_CLOSEST_HIT
    case .MISS_KHR:                return SLANG_STAGE_MISS
    case .CALLABLE_KHR:            return SLANG_STAGE_CALLABLE
    case .TASK_EXT:                return SLANG_STAGE_AMPLIFICATION
    case .MESH_EXT:                return SLANG_STAGE_MESH
    }
    return SLANG_STAGE_NONE
}

@(private = "file")
shader_delete_data :: proc(shader: ^Shader) {
    delete(shader.name)
    delete(shader.spirv_bytes)
    delete(shader.compiled_path)
    delete(shader.source_path)
    for entry_point in shader.entry_points {
        delete(entry_point)
    }
    delete(shader.entry_points)
    shader^ = {}
}

shader_manager_update_shaders :: proc(self: ^Shader_Manager, shader_dir: ^Shader_Dir, path_from_shader_dir: string) -> (ok: bool) {
    src: string = quick_concat({shader_dir.source_directory, path_from_shader_dir}) or_return
    defer delete(src)

    file_infos: []os.File_Info = load_directory_contents_from_disc(src) or_return
    defer delete(file_infos)
    all_ok := true
    for info in file_infos {
        defer delete(info.fullpath)
        if info.type == .Directory {
            next := quick_concat({path_from_shader_dir, info.name, "/"}) or_return
            if !shader_manager_update_shaders(self, shader_dir, next) {
                all_ok = false
            }
            delete(next)
            continue
        }
        if !strings.ends_with(info.name, ".slang") {
            continue
        }

        filename_stripped := info.name[:len(info.name) - len(".slang")]
        if strings.last_index_byte(filename_stripped, '.') < 0 {
            // Unstaged .slang files are includes, not callable shaders.
            continue
        }
        stage := shader_determine_stage(info.name)
        if stage == ._MAX {
            log.errorf("Unknown shader stage in filename: %v", info.fullpath)
            all_ok = false
            continue
        }

        shader: Shader
        keep_shader := false
        defer if !keep_shader {
            shader_delete_data(&shader)
        }
        shader.name = quick_concat({path_from_shader_dir, filename_stripped}) or_return
        shader.source_path = strings.clone(info.fullpath)
        shader.compiled_path = quick_concat({shader_dir.compiled_directory, shader.name, ".", SHADER_CACHE_VERSION, ".spv"}) or_return
        shader.stage = stage
        shader.module = bits.U64_MAX

        // The newest include timestamp invalidates the dependent shader's cache.
        scan_arena: mem.Dynamic_Arena
        mem.dynamic_arena_init(&scan_arena)
        defer mem.dynamic_arena_destroy(&scan_arena)
        scan_allocator := mem.dynamic_arena_allocator(&scan_arena)
        shader.modify_time = info.modification_time
        visited := make(map[string]bool)
        if latest, _, latest_ok := shader_source_latest_time(self, info.fullpath, &visited, scan_allocator); latest_ok {
            shader.modify_time = latest
        }
        delete(visited)

        out_of_date := shader_manager_is_out_of_date(&shader)
        if !out_of_date && self.compile_only {
            continue
        }
        if !out_of_date {
            cached, loaded := load_file_from_disc(shader.compiled_path)
            if loaded {
                shader.spirv_bytes = cached
                shader.entry_points, loaded = spirv_entry_point_names(cached, stage)
            }
            if !loaded {
                log.warnf("Cached shader '%v' is invalid or has the wrong stage; recompiling", shader.name)
                delete(shader.spirv_bytes)
                shader.spirv_bytes = nil
                out_of_date = true
            }
        }
        if out_of_date {
            log.debugf("shader(%v) is out of date: recompiling", shader.name)
            compiled, compiled_ok := shader_manager_compile_shader(self, shader_dir, shader.source_path, stage)
            if !compiled_ok {
                log.errorf("Failed to compile shader(%v)", shader.name)
                all_ok = false
                continue
            }
            shader.spirv_bytes = compiled.spirv
            compiled.spirv = nil
            slang_compiled_module_destroy(&compiled)
            valid: bool
            shader.entry_points, valid = spirv_entry_point_names(shader.spirv_bytes, stage)
            if !valid {
                log.errorf("Compiled shader '%v' has invalid SPIR-V or an unexpected stage", shader.name)
                all_ok = false
                continue
            }
            if !shader_manager_save_compiled_shader(self, &shader) {
                all_ok = false
                continue
            }
        }
        if self.compile_only {
            continue
        }

        qualified_name := shader_manager_qualify_name(shader_dir.domain, shader.name)
        if old_key, existing := delete_key(&self.shaders, qualified_name); old_key != "" {
            delete(old_key)
            shader_delete_data(&existing)
        }
        self.shaders[qualified_name] = shader
        keep_shader = true
    }
    return all_ok
}



shader_manager_save_compiled_shader :: proc(self: ^Shader_Manager, shader: ^Shader,) -> (ok:bool,){
    ensure(shader != nil, "Invalid Shader")
    save_file_to_disc(shader.compiled_path, shader.spirv_bytes, {.Create}) or_return
    return modify_file_metadata_time(shader.compiled_path, shader.modify_time, time.now())
}


shader_manager_compile_shader :: proc(self: ^Shader_Manager, shader_dir: ^Shader_Dir, source_path: string, stage: vk.ShaderStageFlag = ._MAX) -> (compiled: Slang_Compiled_Module, ok: bool) {

    selected_stage := stage
    if selected_stage == ._MAX {
        selected_stage = shader_determine_stage(source_path)
    }
    expected_stage := shader_slang_stage(selected_stage)
    if expected_stage == SLANG_STAGE_NONE {
        log.errorf("Slang does not support shader stage %v for %v", selected_stage, source_path)
        return {}, false
    }
    shader_bytes := load_file_from_disc(source_path,) or_return 
    defer delete(shader_bytes)
    module_name := filepath.stem(source_path)
    search_paths: [dynamic]string
    for dir in self.shader_dirs {
        append(&search_paths, dir.source_directory)
    }
    defer delete(search_paths)
    compiled = slang_compile_module(
        &self.slang_compiler,
        string(shader_bytes),
        module_name,
        source_path,
        search_paths[:],
        expected_stage = expected_stage,
    ) or_return
    // for entry_point in compiled.entry_points {
    //     log.debugf("Entry Point: %v", entry_point.name)
    // }

    return compiled, true
}

@(private)
shader_spirv_stage :: proc(model: u32) -> vk.ShaderStageFlag {
    #partial switch spirv.SpvExecutionModel(model) {
    case .Vertex:                 return .VERTEX
    case .TessellationControl:    return .TESSELLATION_CONTROL
    case .TessellationEvaluation: return .TESSELLATION_EVALUATION
    case .Geometry:               return .GEOMETRY
    case .Fragment:               return .FRAGMENT
    case .GLCompute:              return .COMPUTE
    case .RayGenerationKHR:       return .RAYGEN_KHR
    case .IntersectionKHR:        return .INTERSECTION_KHR
    case .AnyHitKHR:              return .ANY_HIT_KHR
    case .ClosestHitKHR:          return .CLOSEST_HIT_KHR
    case .MissKHR:                return .MISS_KHR
    case .CallableKHR:            return .CALLABLE_KHR
    case .TaskNV, .TaskEXT:       return .TASK_EXT
    case .MeshNV, .MeshEXT:       return .MESH_EXT
    }
    return ._MAX
}

// Rebuild the entry point list from the actual SPIR-V, both after compilation and
// when loading a cache. Reject malformed files and entry points for the wrong stage.
@(private)
spirv_entry_point_names :: proc(code: []byte, expected_stage: vk.ShaderStageFlag, allocator := context.allocator) -> (result: []string, ok: bool) {
    SPIRV_MAGIC :: 0x07230203
    SPIRV_HEADER_WORDS :: 5
    OP_ENTRY_POINT :: 15

    if len(code) < SPIRV_HEADER_WORDS * 4 || len(code) % 4 != 0 {
        return nil, false
    }
    words := mem.slice_data_cast([]u32, code)
    if words[0] != SPIRV_MAGIC {
        return nil, false
    }

    names := make([dynamic]string, allocator)
    defer delete(names)
    defer if !ok {
        for name in names {
            delete(name, allocator)
        }
    }
    for i := SPIRV_HEADER_WORDS; i < len(words); {
        word_count := int(words[i] >> 16)
        if word_count == 0 || i + word_count > len(words) {
            return nil, false
        }
        opcode := words[i] & 0xFFFF
        if opcode == OP_ENTRY_POINT {
            if word_count < 4 || shader_spirv_stage(words[i + 1]) != expected_stage {
                return nil, false
            }
            name_and_interfaces := string(code[(i + 3) * 4:(i + word_count) * 4])
            name_end := strings.index_byte(name_and_interfaces, 0)
            if name_end <= 0 {
                return nil, false
            }
            append(&names, strings.clone(name_and_interfaces[:name_end], allocator))
        }
        i += word_count
    }

    if len(names) == 0 {
        return nil, false
    }
    result = make([]string, len(names), allocator)
    copy(result, names[:])
    return result, true
}
shader_manager_deinit :: proc(self: ^Shader_Manager) {
    if self.hot_reload_thread != nil {
        if !chan.try_send(self.hot_reload_args.thread_status_pipe, Thread_Status.Stop) {
            log.errorf("Failed to stop the shader compiler thread")
        }
        thread.join(self.hot_reload_thread)
        thread.destroy(self.hot_reload_thread)
        chan.destroy(self.hot_reload_args.thread_status_pipe)
        chan.destroy(self.hot_reload_args.build_status_pipe)
    }

    slang_compiler_deinit(&self.slang_compiler)
    for shader_dir in self.shader_dirs {
        delete(shader_dir.shader_directory)
        delete(shader_dir.compiled_directory)
        delete(shader_dir.source_directory)
    }
    delete(self.shader_dirs)

    for key, value in self.shaders {
        delete(key)
        delete(value.name)
        delete(value.spirv_bytes)
        delete(value.compiled_path)
        delete(value.source_path)
        for entry_point in value.entry_points {
            delete(entry_point)
        }
        delete(value.entry_points)
    }

    delete(self.shaders)
}

shader_get_module :: proc(vk_device: vk.Device, engine: ^Engine, shader:^Shader) -> (module: vk.ShaderModule, ok: bool) {
    if shader.module == bits.U64_MAX {
        shader.module, ok = create_shader_module(vk_device, shader.spirv_bytes)
        deletion_queue_push(&engine.main_deletion_queue, shader.module)
        if !ok {
            log.errorf("Failed to create the shader module: %v", shader.name)
            return module, false
        }
    }

    return shader.module, true
}

Astro_Shaders :: union {
    Render_Shaders,
    Compute_Shaders,
}

Render_Shaders :: struct {
    vertex: Shader,
    tessellation_control: Shader,
    tessellation_evaluation: Shader,
    geometry: Shader,
    fragment: Shader,
}

Compute_Shaders :: struct {
    compute: Shader,
}

Stage_Params :: struct {
    stage: vk.ShaderStageFlag,
    input_count: u32,
    inputs: []^spirv.SpvReflectInterfaceVariable,

    output_count: u32,
    outputs: []^spirv.SpvReflectInterfaceVariable,
    module : spirv.SpvReflectShaderModule,
}

Binding_Location :: struct {
    set:     u32,
    binding: u32,
}

// Everything the pipeline builder needs to verify that the value it is about to
// bind actually matches what the shader declared. The block/member pointers live
// inside the SPIRV-Reflect module owned by `Stage_Params`, so they stay valid
// for as long as `Reflected_Shaders` does.
Resource_Reflection :: struct {
    shader_name:     string,
    stage:           vk.ShaderStageFlag,
    set:             u32,
    binding:         u32,
    descriptor_type: vk.DescriptorType,
    image:           spirv.SpvReflectImageTraits,
    block:           ^spirv.SpvReflectBlockVariable,
    type_description: ^spirv.SpvReflectTypeDescription,
}

Reflected_Shaders :: struct {
    layout: map[u32]map[u32]vk.DescriptorSetLayoutBinding,
    // Resource name as reported by SPIRV-Reflect -> its actual set/binding.
    // Host code binds by these names instead of hardcoding descriptor numbers.
    binding_by_name: map[string]Binding_Location,
    // Resource name -> every declaration of it across the pipeline's stages.
    // Used by the pipeline builder to validate uniform layouts and image types.
    binding_reflections: map[string][dynamic]Resource_Reflection,
    push_constants: [dynamic]vk.PushConstantRange,
    stage_params: [dynamic]Stage_Params,
}

Pipeline_Layout2 :: struct {
    sets: u32,
    set_layouts: []Set_Layout,
    vk_layout: vk.PipelineLayout,
}

Set_Memory :: struct {
    root_memory_block: vk.DeviceAddress,
    offset_into_block: vk.DeviceSize,
    set_size: vk.DeviceSize,
    frames_buffered: vk.DeviceSize,
}

Set_Layout :: struct {
    total_set_size: vk.DeviceSize,
    binding_layouts: []Binding_Layout,
    vk_layout: vk.DescriptorSetLayout,
}
Binding_Layout :: struct {
    binding_size: vk.DeviceSize,
    offset: vk.DeviceSize,
    vk_layout: vk.DescriptorSetLayoutBinding,
    type: vk.DescriptorType,
}

@(private)
validate_input_outputs :: proc(stage_params:^[dynamic]Stage_Params) ->(ok:bool,) {
    count:= len(stage_params)
    if count == 0 || count == 1 {
        return true
    }

    //Inputs are the driving force. An output doesn't matter if there isn't an input to use it, and inputs get pruned by the compiler if they don't get used. This ordering prevents getting errors when for example the fragment shader doesn't use the uv's and they get removed, despite being defined in the spirv.
    //TODO add a better check to this. It would be nice to drop a warning that "uv's arent used in .FRAGMENT"
    for i in 0..<count -1 {
        current:= stage_params[i]
        next:= stage_params[i + 1]
     
            for input_index in 0..< next.input_count {

                input := next.inputs[input_index]
            found: bool
            if input.built_in != -1 || input.location == bits.U32_MAX do continue
        for output_index in 0..< current.output_count {
            output := current.outputs[output_index]
                // log.debugf("Stage: %v, Input:%v, Location: %v, Format: %v", next.stage, input.name, input.location, input.format)
                if output.built_in != -1 || output.location == bits.U32_MAX do continue

                //They share a location
                if output.location == input.location {
                    //now check if the types are the same.
                    if output.format != input.format {
                        // log.debugf("Formats don't match. Output(%v): %v, Input(%v): %v", current.stage, output.format, next.stage, input.format)

                        if (output.type_description != nil && output.type_description.op == spirv.SpvOp.TypeArray) || (input.type_description != nil && input.type_description.op == spirv.SpvOp.TypeArray) {
                            log.errorf("Ive got more info about out outputs/inputs and it's terminal. One of them is an array and we haven't implemented stripping that out yet. Godspeed homie.")
                        }
                        // log.errorf("Stage: %v, Output:%v, Location: %v, Format: %v", current.stage, output.name, output.location, output.format)
                        // log.errorf("Stage: %v, Input:%v, Location: %v, Format: %v", next.stage, input.name, input.location, input.format)
                        log.errorf("They Share a location(%v) but the format is different, Output(%v), Input(%v)", output.location, output.format, input.format)
                        return false
                    }
                    else {
                        //log.debugf("Found the binding Output(%v) -> Input(%v) at location(%v) is type: %v", current.stage, next.stage, output.location, output.format)
                        found = true
                    }
                    break
                }
            }
            if !found {
                log.errorf("Stage: %v Input:%v Location: %v Format: %v doesn't have an equal location in Stage %v", next.stage, input.name, input.location, input.format, current.stage)
                log.errorf("Double check that variables are used")
                
                return false
            }

        }            
        

    }
    return true
}

shaders_generate_layout_raw :: proc(reflect_layout: ^Reflected_Shaders, shader: Shader) -> (ok:bool,) {
    if reflect_layout.binding_by_name == nil {
        reflect_layout.binding_by_name = make(map[string]Binding_Location)
    }
    data_len: uint = len(shader.spirv_bytes)        
    stage := shader.stage


    stage_params := append_and_get_ref(&reflect_layout.stage_params, Stage_Params{})
    
    result := spirv.spvReflectCreateShaderModule(data_len, raw_data(shader.spirv_bytes), &stage_params.module)
    if result != .SUCCESS {
        log.errorf("Failed to parse shader: %v, Err: %v", shader.name, result)
        return false
    }
    binding_count:u32
    spirv.spvReflectEnumerateDescriptorBindings(&stage_params.module, &binding_count, nil)
    bindings := make([]^spirv.SpvReflectDescriptorBinding, binding_count)
    defer delete(bindings)
    spirv.spvReflectEnumerateDescriptorBindings(&stage_params.module, &binding_count, raw_data(bindings))

    spirv.spvReflectEnumerateInputVariables(&stage_params.module, &stage_params.input_count, nil)
    stage_params.inputs = make([]^spirv.SpvReflectInterfaceVariable, stage_params.input_count)
    spirv.spvReflectEnumerateInputVariables(&stage_params.module, &stage_params.input_count, raw_data(stage_params.inputs))

    spirv.spvReflectEnumerateOutputVariables(&stage_params.module, &stage_params.output_count, nil)
    stage_params.outputs = make([]^spirv.SpvReflectInterfaceVariable, stage_params.output_count)
    spirv.spvReflectEnumerateOutputVariables(&stage_params.module, &stage_params.output_count, raw_data(stage_params.outputs))

    push_constants_count: u32
    spirv. spvReflectEnumeratePushConstantBlocks(&stage_params.module, &push_constants_count, nil)
    push_constants := make([]^spirv.SpvReflectBlockVariable, push_constants_count)
    defer delete(push_constants)
    spirv.spvReflectEnumeratePushConstantBlocks(&stage_params.module, &push_constants_count, raw_data(push_constants))

    for binding, index in bindings {
        
        if binding.set not_in reflect_layout.layout {
            reflect_layout.layout[binding.set] = make(map[u32]vk.DescriptorSetLayoutBinding)
        }
        set_map := &reflect_layout.layout[binding.set]

        stage_flag: vk.ShaderStageFlags
        
        redundant_binding, bind_ok := reflect_layout.layout[binding.set][binding.binding]

        descriptor_type := cast(vk.DescriptorType)binding.descriptor_type
        if bind_ok {
            stage_flag = redundant_binding.stageFlags

            if redundant_binding.descriptorType != descriptor_type {
                log.errorf("Conflicted Bindings in Shader: %v(Set:%v, Binding:%v)", shader.name, binding.set, binding.binding)
                return false
            }

        }
        stage_flag += {stage}

        binding_layout := vk.DescriptorSetLayoutBinding{
            binding = binding.binding,
            descriptorType = descriptor_type,
            descriptorCount = binding.count,
            stageFlags = stage_flag,
            pImmutableSamplers = nil,
        }

        set_map^[binding.binding] = binding_layout

        name := string(binding.name)
        if name != "" {
            location := Binding_Location{set = binding.set, binding = binding.binding}
            if existing, found := reflect_layout.binding_by_name[name]; found {
                if existing != location {
                    log.errorf(
                        "Shader resource name '%v' is used for set %v binding %v and set %v binding %v",
                        name, existing.set, existing.binding, location.set, location.binding,
                    )
                    return false
                }
            } else {
                reflect_layout.binding_by_name[name] = location
            }

            // Keep the full reflection for builder-side type validation. A name can
            // be declared by more than one stage (for example a UBO used by both the
            // vertex and fragment shader), so collect every declaration.
            if reflect_layout.binding_reflections == nil {
                reflect_layout.binding_reflections = make(map[string][dynamic]Resource_Reflection)
            }
            reflections := reflect_layout.binding_reflections[name]
            append(&reflections, Resource_Reflection{
                shader_name = shader.name,
                stage = stage,
                set = binding.set,
                binding = binding.binding,
                descriptor_type = descriptor_type,
                image = binding.image,
                block = &binding.block,
                type_description = binding.type_description,
            })
            reflect_layout.binding_reflections[name] = reflections
        }
    }
    for constant in push_constants {
        //log.infof("Push Constants - Name: %v, Size: %v, Offset: %v", constant.name, constant.size, constant.offset)

        push_constant_range := vk.PushConstantRange{
            stageFlags = {stage},
            offset = constant.offset,
            size = constant.size,
        }
        // A combined module can report the same range once per entry point. Vulkan
        // forbids two ranges that expose the same stage bits, so merge identical ranges.
        merged := false
        for &existing in reflect_layout.push_constants {
            if existing.offset == push_constant_range.offset && existing.size == push_constant_range.size {
                existing.stageFlags += push_constant_range.stageFlags
                merged = true
                break
            }
        }
        if !merged {
            append(&reflect_layout.push_constants, push_constant_range)
        }
    }
    stage_params.stage = stage
    return true

}

print_inputs :: proc(inputs: []^spirv.SpvReflectInterfaceVariable, count: u32, levels: u32) {
    for i in 0..<count {
        input := inputs[i]
        if input.built_in != -1 || input.location == bits.U32_MAX do continue
        log.infof("Input ID: %v", input.spirv_id)
        log.infof(" Name: %v", input.name)
        log.infof(" Component : %v", input.component)
        log.infof(" Location:   %v", input.location)
        log.infof(" StorageClass: %v", input.storage_class)
        log.infof(" Semantic: %v", input.semantic)
        log.infof(" Offset: %v", input.word_offset.location)
        log.infof(" Format: %v", input.format)

        if input.member_count > 0 {
            log.infof("---Children---")
            print_inputs(mem.slice_ptr(&input.members, int(input.member_count)), input.member_count, levels + 1)
        }

    }
}

shaders_generate_raw_layout_render:: proc(vk_device: vk.Device, render_shaders: Render_Shaders) -> (layout: Reflected_Shaders, ok: bool) {

    layout.layout = make(map[u32]map[u32]vk.DescriptorSetLayoutBinding)
    layout.binding_reflections = make(map[string][dynamic]Resource_Reflection)
    layout.push_constants = make([dynamic]vk.PushConstantRange)
    layout.stage_params = make([dynamic]Stage_Params)
    if render_shaders.vertex.name == "" || render_shaders.vertex.stage != .VERTEX {
        log.errorf("Invalid Vertex Shader")
        return layout, false
    }
    shaders_generate_layout_raw(&layout, render_shaders.vertex) or_return

    // Interface validation compares adjacent stages, so reflection must follow
    // the actual graphics pipeline order rather than the order of struct fields.
    has_control := render_shaders.tessellation_control.name != ""
    has_evaluation := render_shaders.tessellation_evaluation.name != ""
    if has_control != has_evaluation {
        log.errorf("Tessellation control and evaluation shaders must be provided together")
        return layout, false
    }
    if has_control {
        if render_shaders.tessellation_control.stage != .TESSELLATION_CONTROL {
            log.errorf("Invalid Tessellation Control Shader")
            return layout, false
        }
        shaders_generate_layout_raw(&layout, render_shaders.tessellation_control) or_return
        if render_shaders.tessellation_evaluation.stage != .TESSELLATION_EVALUATION {
            log.errorf("Invalid Tessellation Evaluation Shader")
            return layout, false
        }
        shaders_generate_layout_raw(&layout, render_shaders.tessellation_evaluation) or_return
    }
    if render_shaders.geometry.name != "" {
        if render_shaders.geometry.stage != .GEOMETRY {
            log.errorf("Invalid Geometry Shader")
            return layout, false
        }
        shaders_generate_layout_raw(&layout, render_shaders.geometry) or_return
    }
    if render_shaders.fragment.name != "" {
        if render_shaders.fragment.stage != .FRAGMENT {
            log.errorf("Invalid Fragment Shader")
            return layout, false
        }
        shaders_generate_layout_raw(&layout, render_shaders.fragment) or_return
    }

    return layout, true
}


delete_reflected_shaders :: proc(self:^Reflected_Shaders) {
    for key, &value in self.layout {
        
        delete(value)
    }
    delete(self.layout)
    delete(self.binding_by_name)
    for _, &reflections in self.binding_reflections {
        delete(reflections)
    }
    delete(self.binding_reflections)

    delete(self.push_constants)

    for &params in self.stage_params {
        delete(params.inputs)
        delete(params.outputs)
        spirv.spvReflectDestroyShaderModule(&params.module)
    }
    delete(self.stage_params)

}

shaders_generate_raw_layout_compute :: proc(vk_device: vk.Device, compute_shaders: Compute_Shaders) ->(layout: Reflected_Shaders, ok: bool) {

        if compute_shaders.compute.name != "" && compute_shaders.compute.stage != .COMPUTE{
            log.errorf("Invalid Compute Shader")
            log.errorf("Could not Generate Compute Pipeline Layout")
            return layout, false 
        }
        //set:  binding: layout
        layout.layout = make(map[u32]map[u32]vk.DescriptorSetLayoutBinding)
        layout.binding_reflections = make(map[string][dynamic]Resource_Reflection)
        layout.push_constants = make([dynamic]vk.PushConstantRange)
        layout.stage_params = make([dynamic]Stage_Params) 

        shaders_generate_layout_raw(&layout, compute_shaders.compute) or_return

    return layout, true
}

generate_vk_layout :: proc(vk_device: vk.Device, universal_layout: Set_Layout, layout: ^Reflected_Shaders) ->(p_layout: Pipeline_Layout2, ok:bool,) {

    validate_input_outputs(&layout.stage_params) or_return
    
    /*
        For now we don't support sparse binding. That might change if the need arises later, but for now it's unnecessary.
        Sparse meaning, using set 0,2 but skipping 1. Same with bindings.
     */
    if 0 not_in layout.layout
    {
        layout.layout[0] = {} 
    }
    set_layouts := make([]vk.DescriptorSetLayout, len(layout.layout))
    defer delete(set_layouts)

    p_layout.sets = u32(len(layout.layout))
    p_layout.set_layouts = make([]Set_Layout, p_layout.sets)
    for set, binding_layouts in layout.layout {
        assert(set < u32(len(layout.layout)))

        if set == 0 { //Use Universal texture buffer binding.
            set_layouts[0] = universal_layout.vk_layout
            p_layout.set_layouts[0] = universal_layout
        } else {

            bindings := make([]vk.DescriptorSetLayoutBinding, len(binding_layouts))
            p_layout.set_layouts[set].binding_layouts = make([]Binding_Layout, len(binding_layouts))
            defer delete(bindings)
            for binding, layout in binding_layouts {
                // log.infof("Binding: %v / %v", binding, len(binding_layouts))
                bindings[binding] = layout
                p_layout.set_layouts[set].binding_layouts[binding] = {
                   vk_layout = layout, 
                   type = layout.descriptorType,
                }
            }

            set_layout_info:= vk.DescriptorSetLayoutCreateInfo {
                sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                flags = {.DESCRIPTOR_BUFFER_EXT},
                bindingCount = u32(len(bindings)),
                pBindings = raw_data(bindings),
            }
            vk_check(vk.CreateDescriptorSetLayout(vk_device, &set_layout_info, nil, &p_layout.set_layouts[set].vk_layout)) or_return

            vk.GetDescriptorSetLayoutSizeEXT(vk_device, p_layout.set_layouts[set].vk_layout, &p_layout.set_layouts[set].total_set_size)
            for i in 0..<len(binding_layouts) {

                vk.GetDescriptorSetLayoutBindingOffsetEXT(vk_device, p_layout.set_layouts[set].vk_layout, u32(i), &p_layout.set_layouts[set].binding_layouts[i].offset)
            }
            set_layouts[set] = p_layout.set_layouts[set].vk_layout
        }

        //log.infof("Set: %v, Offsets: %v", set, p_layout.set_layouts[set].binding_layouts)
    }
    pipeline_layout_info := vk.PipelineLayoutCreateInfo {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = u32(len(set_layouts)),
        pSetLayouts = raw_data(set_layouts),
        pushConstantRangeCount = u32(len(layout.push_constants)),
        pPushConstantRanges =  raw_data(layout.push_constants),
    }

    vk_check(vk.CreatePipelineLayout(vk_device, &pipeline_layout_info, nil, &p_layout.vk_layout)) or_return

    return p_layout, true
}
