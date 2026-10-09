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
import vk "vendor:vulkan"

Shader::struct {
    name: string,
    compiled_path: string,
    source_path: string,
    stage: vk.ShaderStageFlag,
    modify_time: time.Time,
    spirv_bytes:[]byte,
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
    shader_manager_update_shaders(self, &self.shader_dirs[len(self.shader_dirs) - 1], "")
    return true
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
    shader_manager_add_directory(self, shader_dir)
    delete(calling_directory)
    delete(shader_dir)
    self.build_status = .Success

    return true
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

        return self.modify_time != compile_info.modification_time
    }
    return true
}

shader_determine_stage :: proc(filename: string) -> (stage:vk.ShaderStageFlag) {
 
    split_name, err_split := strings.split(filename, ".", context.allocator)
    defer delete(split_name)
    if err_split != .None  {
        return ._MAX
    }
    //means that it's not defined in the file path and we assume it's an include file
    size := len(split_name)  
    if size < 2 {
        return ._MAX
    }
    else if size == 2 {
        return .CALLABLE_KHR
    }
    switch split_name[1]{
    case "vert", "vertex": 
        return .VERTEX
    case "frag", "fragment":
        return .FRAGMENT
    case "comp", "compute":
        return .COMPUTE
    }
    log.warnf("Un-Mapped shader type: %v", split_name[1])
    return ._MAX 
}

shader_manager_update_shaders :: proc(self: ^Shader_Manager, shader_dir: ^Shader_Dir, path_from_shader_dir:string) ->(ok:bool) {
    
    src: string = quick_concat({shader_dir.source_directory, path_from_shader_dir})or_return
    defer delete(src)

    file_infos: []os.File_Info = load_directory_contents_from_disc(src) or_return 
    defer delete(file_infos) 
    for i in 0..<len(file_infos) {   
        info := file_infos[i]
        if info.type == .Directory {
            next:= quick_concat({path_from_shader_dir, info.name, "/"}) or_return
            shader_manager_update_shaders(self, shader_dir, next)
            delete(next)
        }
        if !strings.ends_with(info.name, ".slang") {
            defer delete(info.fullpath)
            continue
        }

        spirv: []byte
        stage: vk.ShaderStageFlag = shader_determine_stage(info.name)    
        if stage == ._MAX {
            log.errorf("Failed to determine shader type for: %v", info.fullpath)
            return false
        } 
        else if stage == .CALLABLE_KHR {
            delete(info.fullpath)
            continue
        }
        filename_stripped := strings.substring(info.name, 0, len(info.name) - len(".slang")) or_return 
        relative_name := quick_concat({path_from_shader_dir, filename_stripped} ) or_return

        compile_path := quick_concat({shader_dir.compiled_directory,relative_name, ".spv"}, context.allocator) or_return


        shader: Shader = {
            name = relative_name,
            source_path = info.fullpath,
            modify_time = info.modification_time,
            compiled_path = compile_path,
            stage = stage,
        }
        out_of_date:= shader_manager_is_out_of_date(&shader)
        
        if out_of_date
        {
            log.debugf("shader(%v) is out of date: recompiling", shader.name)
            spirv = shader_manager_compile_shader(self, shader_dir, shader.source_path) or_return
        }
        else if self.compile_only {
            delete(shader.name)
            delete(shader.source_path)
            delete(shader.compiled_path)
            continue
        }
        else {
            spirv = load_file_from_disc(shader.compiled_path,) or_return
        }

        shader.spirv_bytes = spirv
        shader.stage = stage
        if self.compile_only {
            saved := shader_manager_save_compiled_shader(self, &shader)
            delete(shader.name)
            delete(shader.spirv_bytes)
            delete(shader.source_path)
            delete(shader.compiled_path)
            saved or_return
            continue
        }
        qualified_name := shader_manager_qualify_name(shader_dir.domain, relative_name)
        if old_key, existing := delete_key(&self.shaders, qualified_name); old_key != "" {
            delete(old_key)
            delete(existing.name)
            delete(existing.spirv_bytes)
            delete(existing.compiled_path)
            delete(existing.source_path)
        }
        self.shaders[qualified_name] = shader

        if out_of_date{
            shader_manager_save_compiled_shader(self, &self.shaders[qualified_name])or_return
        }
    }   
    return true
}

shader_manager_save_compiled_shader :: proc(self: ^Shader_Manager, shader: ^Shader,) -> (ok:bool,){
    ensure(shader != nil, "Invalid Shader")
    save_file_to_disc(shader.compiled_path, shader.spirv_bytes, {.Create}) or_return
    return modify_file_metadata_time(shader.compiled_path, shader.modify_time, time.now())
}


shader_manager_compile_shader :: proc(self: ^Shader_Manager, shader_dir:^ Shader_Dir, source_path: string,) -> (spirv: []byte, ok: bool) {

    shader_bytes := load_file_from_disc(source_path,) or_return 
    defer delete(shader_bytes)
    module_name := filepath.stem(source_path)
    search_paths: [dynamic]string
    for dir in self.shader_dirs {
        append(&search_paths, dir.source_directory)
    }
    defer delete(search_paths)
    shaders: []Slang_Compiled_Shader = slang_compile_module(
        &self.slang_compiler,
        string(shader_bytes),
        module_name,
        source_path,
        search_paths[:],
    ) or_return
    if len(shaders) > 1 {
        log.warnf("Uh oh too many shaders in array")
    }  
    if len(shaders) == 0 {
        delete(shaders)
        return nil, false
    }
    result_spirv := shaders[0].spirv
    for shader in shaders {
        delete(shader.name)
    }
    delete(shaders)

    return result_spirv, true
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
    }

    delete(self.shaders)
}







