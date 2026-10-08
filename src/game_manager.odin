package astro

import "core:os"
import "core:log"
import "core:time"
import "core:strings"
import "core:dynlib"
import "core:mem"
import "base:runtime"
import "core:thread"
import "core:sync/chan"
import "core:fmt"
import "core:reflect"

import vk "vendor:vulkan"
import im "libs:imgui"




Game_Compile_State :: struct {
    validated: bool,
    build_status: Build_Status,
}

Game :: struct {
    name: string,
    scene: Scene,

    game_data_ptr: rawptr,
}

Game_Manager :: struct {
    game: Game,
    project: Project,
    calling_dir: string,
    executable_path: string,

    game_allocator_track: mem.Tracking_Allocator,
    game_allocator: runtime.Allocator,
    game_logger: runtime.Logger,
    game_initialized: bool,

    compiler_thread: ^thread.Thread,
    compiler_args : Project_Compiler_Worker_Args,
    library: Game_Library,

}
Project_Compiler_Worker_Args :: struct {
    build_status_pipe: chan.Chan(Build_Status),
    thread_status_pipe: chan.Chan(Thread_Status),
    project: ^Project,
}


Game_Library :: struct {
    library: dynlib.Library,
    api: GameAPI,
    library_path: string,
    loaded_library_path: string,
    build_status: Build_Status,
    reloads: u32,
}
Project :: struct {
    name: string,
    library_creation_time: time.Time,
    src_time_modification_cache: map[string]time.Time,
    directory: string,
    src_dir: string,
    shader_dir: string,
    asset_dir: string,
    tmp_dir: string,
    library_path: string,
}

game_manager_init :: proc(self: ^Game_Manager, engine: ^Engine, path_to_project: string, allocator:=context.allocator) ->(ok:bool) {

    when ODIN_DEBUG {
        
        self.game_logger = log.create_console_logger(lowest = .Debug, opt = {.Level, .Terminal_Color}, ident = "GAME")

        mem.tracking_allocator_init(&self.game_allocator_track, DEFAULT_ALLOCATOR)
        self.game_allocator = mem.tracking_allocator(&self.game_allocator_track)
    }


    self.calling_dir = quick_calling_dir() or_return
    self.executable_path = os.args[0]

    if path_to_project == "" {
        self.project.directory = quick_concat({self.calling_dir, "/game"}, allocator) or_return
    }
    else {
        self.project.directory = strings.clone(path_to_project)
    }

    self.project.src_time_modification_cache = make(map[string]time.Time) 
    self.project.name = "Game"
    //open the file, grab the assets, shaders, src, file handles. Grab the .so file handle if available.
    if !os.exists(self.project.directory) {
        log.errorf("Project path is invalid: %v", path_to_project)
    }    

    self.project.src_dir = quick_concat({self.project.directory, "/src/"}) or_return
    self.project.shader_dir = quick_concat({self.project.directory, "/shaders/"}) or_return
    self.project.asset_dir = quick_concat({self.project.directory, "/assets/"}) or_return
    self.project.tmp_dir = quick_concat({self.project.directory, "/tmp/"}) or_return
    self.library.library_path = quick_concat({self.project.directory, "/game.so"}) or_return
    self.project.library_path = self.library.library_path


    shader_manager_add_directory(&engine.shader_manager, self.project.shader_dir)
    if ok := spawn_game_compiler_thread(self); !ok {
        log.errorf("Failed to spawn the game compiler thread")
        return false
    }
    //game_manager_init_library(&self.project, self, engine) or_return
    
      return true
}
game_manager_update :: proc(self: ^ Game_Manager, engine: ^Engine) {

    if build_status, has_output:= chan.try_recv(self.compiler_args.build_status_pipe); has_output {
        switch build_status {
        case .Idle: 
        case .Compiling: 
            log.debugf("Thread has started compiling library")
            self.library.build_status = build_status
        case .Success: 
            log.debugf("Thread has successfully compiled library")
             if !game_manager_init_library(&self.project, self, engine) {
                 return
             }
            self.library.build_status = build_status

            if !self.game_initialized {
                game_manager_game_init(self, &engine.scene, engine)
            } else {
                game_manager_game_reload(self, &engine.scene, engine)
            }
            if !chan.try_send(self.compiler_args.thread_status_pipe, Thread_Status.Continue) {
                log.debugf("Failed to send the thread the continue directive")
            }

        case .Failed: 
            log.debugf("Thread has failed to compile library")
            self.library.build_status = build_status
        }
    }
}

@(private="file")
spawn_game_compiler_thread :: proc(self: ^Game_Manager) ->(ok:bool) {

    build_status, _ := chan.create_buffered(chan.Chan(Build_Status), 5, context.allocator)
    thread_status,_ := chan.create_buffered(chan.Chan(Thread_Status), 5, context.allocator)

    self.compiler_args = {
        build_status_pipe = build_status,
        thread_status_pipe = thread_status,
        project = &self.project,
    }

   self.compiler_thread = thread.create_and_start_with_data(rawptr(&self.compiler_args), game_compiler_thread_proc)
   thread.start(self.compiler_thread)

    return true
}

@(private="file")
game_compiler_thread_proc :: proc(data: rawptr) {

    args := cast(^Project_Compiler_Worker_Args)data
    build_status_pipe := &args.build_status_pipe
    thread_status_pipe := &args.thread_status_pipe
    project := args.project

    build_status: Build_Status = .Idle
    thread_status: Thread_Status = .Continue
    for thread_status != .Stop {
        new_status, new_data := chan.try_recv(thread_status_pipe^)
        if new_data {
  
            if new_status == .Stop {
                fmt.println("Got the command to cease functions")
                thread_status = new_status
                continue
            }

            if thread_status != .Stop {
                thread_status = new_status
            }
        }
        if thread_status == .Continue {
            if  is_library_outdated(project) && sources_settled(project) {
                // Snapshot before compiling so edits made mid-build still trigger a rebuild.
                cache_library_save_times(project)
                fmt.println("Compiling Library")
                if !chan.try_send(build_status_pipe^, Build_Status.Compiling) {

                    fmt.println("Our mother is dead(1), we too must enter the void.")
                    thread_status = .Stop 
                }

                if compile_library(project) {
                    fmt.println("Finished Compiling Library")
                    if !chan.try_send(build_status_pipe^, Build_Status.Success) {

                        fmt.println("Our mother is dead(2), we too must enter the void.")
                        thread_status = .Stop 
                    } else do thread_status = .Wait
                }
                else {
                    fmt.println("W-T-FUCK, we couldn't compile the library")
                }
            } 

            //Idle or Die
            if build_status != .Idle {
                if !chan.try_send(build_status_pipe^, Build_Status.Idle) {
                    fmt.println("Our mother is dead, we too must enter the void.")
                    thread_status = .Stop
                }
                build_status = .Idle
            }
        }
        time.sleep(time.Millisecond * 1000)
    }    
}

@(private="file")
is_library_outdated :: proc(self: ^Project) ->(ok:bool) {
    if len(self.src_time_modification_cache) == 0 {
        return true
    }
    count := 0
    outdated := is_dir_outdated(self, self.src_dir, &count)
    // A differing file count means a source file was added or removed.
    return outdated || count != len(self.src_time_modification_cache)
}

COMPILE_DEBOUNCE :: time.Second * 3

// True once the newest source edit is older than COMPILE_DEBOUNCE.
@(private="file")
sources_settled :: proc(self: ^Project) -> bool {
    newest: time.Time
    newest_source_time(self.src_dir, &newest)
    return time.diff(newest, time.now()) >= COMPILE_DEBOUNCE
}

@(private="file")
newest_source_time :: proc(dir: string, newest: ^time.Time) {
    file_infos, ok := load_directory_contents_from_disc(dir)
    if !ok {
        return
    }
    for file_info in file_infos {
        if file_info.type == .Directory {
            newest_source_time(file_info.fullpath, newest)
        }
        else if strings.ends_with(file_info.name, ".odin") && file_info.modification_time._nsec > newest._nsec {
            newest^ = file_info.modification_time
        }
        delete(file_info.fullpath)
    }
    delete(file_infos)
}

@(private="file")
is_dir_outdated :: proc(self: ^Project, dir: string, count: ^int) -> (outdated: bool) {
    file_infos, ok := load_directory_contents_from_disc(dir)
    if !ok {
        return false
    }
    for file_info in file_infos {
        if file_info.type == .Directory {
            if is_dir_outdated(self, file_info.fullpath, count) {
                outdated = true
            }
        }
        else if strings.ends_with(file_info.name, ".odin") {
            count^ += 1
            cached, found := self.src_time_modification_cache[file_info.fullpath]
            if !found || cached != file_info.modification_time {
                outdated = true
            }
        }
        delete(file_info.fullpath)
    }
    delete(file_infos)
    return outdated
}

@(private="file")
validate_library :: #force_inline proc(self: ^Game_Manager, library: dynlib.Library) ->(api: GameAPI, ok:bool,) {
    base_info := reflect.type_info_base(type_info_of(GameAPI))
    struct_info, valid:= base_info.variant.(reflect.Type_Info_Struct)

    if !valid {
        log.warnf("Failed to parse GameAPI struct info")
        return api, false,
    }
     
    for i in 0..<struct_info.field_count {
        name: = struct_info.names[i]
        offset := struct_info.offsets[i]
        type_id := struct_info.types[i].id
        field_ptr := cast(^rawptr)rawptr(uintptr(&api) + offset)
        library_proc_name := quick_concat({"game_", name}) or_return

        defer delete(library_proc_name)
        symbol := dynlib.symbol_address(library, library_proc_name) or_else nil
        if (symbol == nil) {
            log.debugf("Library Invalid: Doesn't contain a (%v)0 field", library_proc_name)
            return api, false
        } 
        field_ptr^ = symbol
    }
    init := dynlib.symbol_address(library, "game_init")
    return api, true
}

@(private="file")
game_manager_init_library:: proc(self: ^Project, manager: ^Game_Manager, engine: ^Engine) ->(ok:bool){
    log.debugf("Compiling Game Library")
    library_path := copy_file_rename(self.library_path, manager.project.tmp_dir, fmt.tprint(manager.library.reloads)) or_return
    library, load := dynlib.load_library(library_path)
    if !load {
        log.errorf("Failed to load game library: %v", dynlib.last_error())
        return false
    }
    api, valid := validate_library(manager, library) 
    if !valid {
        if !dynlib.unload_library(library) {
            log.errorf("Failed to unload invalid library")
        }
       return false 
    }
    
    if manager.library.library != nil {
        log.debugf("Unloading game library")

        if !dynlib.unload_library(manager.library.library) {
            log.errorf("Failed to unload game library")
            return false
        }
        delete(manager.library.loaded_library_path)

    } 

    manager.library.library = library
    manager.library.api = api
    manager.library.loaded_library_path = library_path

    return true
}

@(private="file")
compile_library :: proc(self: ^Project) -> (ok: bool) {
    out: string = quick_concat({"-out:", self.library_path}) or_return
    defer delete(out)
    quick_cmd_line_runner({
        "odin",
        "build",
        self.src_dir,
        "-build-mode:shared",
        out,
        "--collection:libs=libs",
        "-debug",
        "-define:GLFW_SHARED=false",
    }, context.allocator) or_return

    return true
}

@(private="file")
cache_library_save_times :: proc(self:^Project) ->(ok:bool,) {
    for key in self.src_time_modification_cache {
        delete(key)
    }
    clear(&self.src_time_modification_cache)
    cache_library_save_times_recursive(self, self.src_dir) or_return
    return true
}


@(private="file")
cache_library_save_times_recursive :: proc(self:^Project, dir:string) ->(ok:bool,) {
  
    file_infos := load_directory_contents_from_disc(dir) or_return
    for file_info in file_infos {
       
        if file_info.type == .Directory {
            cache_library_save_times_recursive(self, file_info.fullpath,) or_return
        }
        else if strings.ends_with(file_info.name, ".odin") {
            // The map keeps the key string, so it needs its own copy.
            self.src_time_modification_cache[strings.clone(file_info.fullpath)] = file_info.modification_time
        }
        delete(file_info.fullpath) 
    }
    delete(file_infos)
    return true
}

game_manager_deinit :: proc(self: ^Game_Manager, engine: ^Engine) -> (ok:bool,) {
    if okk := chan.try_send(self.compiler_args.thread_status_pipe, Thread_Status.Stop); !okk {
        log.errorf("Failed to get thread under control, all is lost")
    } 
    game_manager_game_deinit(self, &engine.scene, engine)
    delete(self.calling_dir)
    delete(self.project.directory)
    delete(self.project.shader_dir)
    delete(self.project.asset_dir)
    delete(self.project.src_dir)
    delete(self.project.tmp_dir)
    delete(self.library.library_path)
    delete(self.library.loaded_library_path)
    // for key in self.project.src_time_modification_cache {
    //     delete(key)
    // }
    delete(self.project.src_time_modification_cache)
 
    when ODIN_DEBUG {


        logger := context.logger
        context.logger = self.game_logger
        if len(self.game_allocator_track.allocation_map) > 0 {
            log.errorf("=== %v allocations not freed ===", len(self.game_allocator_track.allocation_map))
            for _, entry in self.game_allocator_track.allocation_map {
                log.debugf("%v bytes @ %v", entry.size, entry.location)
            }
        }
        if len(self.game_allocator_track.bad_free_array) > 0 {
            log.errorf("=== %v incorrect frees ===", len(self.game_allocator_track.bad_free_array))
            for entry in self.game_allocator_track.bad_free_array {
                log.debugf("%p @ %v", entry.memory, entry.location)
            }
        }
    context.logger = logger 
    log.destroy_console_logger(self.game_logger)
    mem.tracking_allocator_destroy(&self.game_allocator_track)
    }

    thread.join(self.compiler_thread)
    thread.destroy(self.compiler_thread)
    chan.destroy(self.compiler_args.thread_status_pipe)
    chan.destroy(self.compiler_args.build_status_pipe)
    return true
}

GAME_INIT_FUNC :: #type proc(self: ^Scene, engine: ^Engine) ->(ok:bool)
GAME_UPDATE_FUNC :: #type proc(self: ^Scene, engine: ^Engine, delta_time:f32,) ->(ok:bool)
GAME_DRAW_FUNC :: #type proc(self: ^Scene, engine: ^Engine, cmd: vk.CommandBuffer) ->(ok:bool)
GAME_DRAW_UI_FUNC :: #type proc(self: ^Scene, engine: ^Engine,) ->(ok:bool)
GAME_DEINIT_FUNC :: #type proc(self: ^Scene, engine: ^Engine,) ->(ok:bool)
// Per-module global state that must be re-established inside game.so.
Game_Globals :: struct {
    vk_proc_address:  rawptr,
    vk_instance:      vk.Instance,
    imgui_context:    ^im.Context,
    imgui_alloc_func: im.MemAllocFunc,
    imgui_free_func:  im.MemFreeFunc,
    imgui_user_data:  rawptr,
}

GAME_RELOAD_FUNC :: #type proc(self: ^Scene, engine: ^Engine, globals: Game_Globals) ->(ok:bool,)


GameAPI :: struct {
    init : GAME_INIT_FUNC,
    update : GAME_UPDATE_FUNC,
    draw: GAME_DRAW_FUNC,
    draw_ui: GAME_DRAW_UI_FUNC,
    deinit: GAME_DEINIT_FUNC,
    reload: GAME_RELOAD_FUNC,
}

game_manager_game_init :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine){
    if self.library.api.init == nil {
        return
    } 
    assert(scene != nil, "Invalid Scene")
    // game.so has its own copy of the vk/imgui globals; they must be loaded before init uses them.
    game_manager_game_reload(self, scene, engine)
    log.debug("Calling Game Initializer")
    context.allocator = self.game_allocator
    context.logger = self.game_logger

    if !self.library.api.init(scene, engine) {
        context.logger = engine.logger
        log.errorf("Game failed to init properly")
        return 
    }
    self.game_initialized = true
    context.allocator = engine.allocator
    context.logger = engine.logger
}

game_manager_game_update :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine, delta_time: f32){
    if self.library.api.update == nil {
        return
    } 
    context.allocator = self.game_allocator
    context.logger = self.game_logger

    if !self.library.api.update(scene, engine, delta_time) {
        context.logger = engine.logger
        log.errorf("Game failed to update properly")
    }
    context.allocator = engine.allocator
    context.logger = engine.logger
}
game_manager_game_draw :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine, cmd: vk.CommandBuffer){
    if self.library.api.draw == nil {
        return
    } 
    context.allocator = self.game_allocator
    context.logger = self.game_logger

    if !self.library.api.draw(scene, engine, cmd) {
        context.logger = engine.logger
        log.errorf("Game failed to draw properly")
    }
    context.allocator = engine.allocator
    context.logger = engine.logger
}

game_manager_game_draw_ui :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine ){
    if self.library.api.draw_ui == nil {
        return
    } 
    context.allocator = self.game_allocator
    context.logger = self.game_logger

    if !self.library.api.draw_ui(scene, engine) {
        context.logger = engine.logger
        log.errorf("Game failed to draw properly")
    }
    context.allocator = engine.allocator
    context.logger = engine.logger
}

game_manager_game_reload :: proc(self: ^Game_Manager, scene: ^ Scene, engine: ^Engine){
    if self.library.api.reload== nil {
        return
    } 
    globals := Game_Globals {
        vk_proc_address = rawptr(vk.GetInstanceProcAddr),
        vk_instance     = engine.vk_instance,
        imgui_context   = im.GetCurrentContext(),
    }
    im.GetAllocatorFunctions(&globals.imgui_alloc_func, &globals.imgui_free_func, &globals.imgui_user_data)

    context.allocator = self.game_allocator
    context.logger = self.game_logger

    if !self.library.api.reload(scene, engine, globals) {
        context.logger = engine.logger
        log.errorf("Game failed to reload properly")
    }
    context.allocator = engine.allocator
    context.logger = engine.logger
    self.library.reloads += 1
}

game_manager_game_deinit :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine){
    if self.library.api.deinit == nil {
        return
    } 
    log.debug("Calling Game De-Initializer")
    context.allocator = self.game_allocator
    context.logger = self.game_logger

    if !self.library.api.deinit(scene, engine) {
        context.logger = engine.logger
        log.errorf("Game failed to deinit properly")
    }
    context.allocator = engine.allocator
    context.logger = engine.logger
}


