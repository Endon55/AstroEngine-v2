package astro

import "core:os"
import "core:log"
import "core:time"
import "core:strings"
import "core:dynlib"
import "core:mem"
import "base:runtime"

import vk "vendor:vulkan"

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

}

Project :: struct {
    library: dynlib.Library,
    api: GameAPI,
    name: string,
    library_creation_time: time.Time,
    src_time_modification_cache: map[string]time.Time,
    src_time_cache_file: string,
    directory: string,
    src_dir: string,
    shader_dir: string,
    asset_dir: string,
    tmp_dir: string,
    library_path: string,
}

game_manager_get_api :: proc(self:^Game_Manager) -> GameAPI {
    return self.project.api
}
game_manager_init :: proc(self: ^Game_Manager, path_to_project: string, allocator:=context.allocator) ->(ok:bool) {

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

    self.project.src_dir = quick_concat({self.project.directory, "/src"}) or_return
    self.project.shader_dir = quick_concat({self.project.directory, "/shaders"}) or_return
    self.project.asset_dir = quick_concat({self.project.directory, "/assets"}) or_return
    self.project.tmp_dir = quick_concat({self.project.directory, "/tmp"}) or_return
    self.project.library_path = quick_concat({self.project.directory, "/game.so"}) or_return

    game_manager_init_library(&self.project, self) or_return
    
    
    self.project.library, ok = dynlib.load_library(self.project.library_path)
    if ! ok {
        log.errorf("Failed to load game library: %v", dynlib.last_error())
        return false
    }
    
    self.project.api = {
        init = cast(GAME_INIT_FUNC)(dynlib.symbol_address(self.project.library, "game_init") or_else nil),
        update = cast(GAME_UPDATE_FUNC)(dynlib.symbol_address(self.project.library, "game_update") or_else nil),
        draw = cast(GAME_DRAW_FUNC)(dynlib.symbol_address(self.project.library, "game_draw") or_else nil),
        deinit= cast(GAME_DEINIT_FUNC)(dynlib.symbol_address(self.project.library, "game_deinit") or_else nil),
    } 

    if self.project.api.init == nil {
        log.errorf("Game doesn't contain an init function")
        return false
    }
    if self.project.api.update == nil {
        log.errorf("Game doesn't contain an update function")
        return false
    }
    if self.project.api.draw == nil {
        log.errorf("Game doesn't contain an draw function")
        return false
    }
    if self.project.api.deinit == nil {
        log.errorf("Game doesn't contain an deinit function")
        return false
    }
    
    return true
}
@(private="file")
is_library_outdated :: proc(self: ^Project) ->(ok:bool) {
    for key, value in self.src_time_modification_cache {
        if value._nsec > self.library_creation_time._nsec{
            return true
        }
    }
    return false
}

@(private="file")
game_manager_init_library:: proc(self: ^Project, manager: ^Game_Manager) ->(ok:bool, ){
    log.debugf("Compiling Game Library")
    compile_library(self) or_return
    cache_library_save_times(self) or_return


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


    //cache_last save times
    cache_library_save_times(self) or_return

    return true
}

@(private="file")
cache_library_save_times :: proc(self:^Project) ->(ok:bool,) {
 
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
            self.src_time_modification_cache[file_info.fullpath] = file_info.modification_time
        }
        delete(file_info.fullpath) 
    }
    delete(file_infos)
    return true
}

game_manager_deinit :: proc(self: ^Game_Manager, engine: ^Engine) -> (ok:bool,) {
    delete(self.calling_dir)
    delete(self.project.directory)
    delete(self.project.shader_dir)
    delete(self.project.asset_dir)
    delete(self.project.src_dir)
    delete(self.project.tmp_dir)
    delete(self.project.library_path)
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



    return true
}


GAME_INIT_FUNC :: #type proc(self: ^Scene, engine: ^Engine) ->(ok:bool)
GAME_UPDATE_FUNC :: #type proc(self: ^Scene, engine: ^Engine, delta_time:f32,) ->(ok:bool)
GAME_DRAW_FUNC :: #type proc(self: ^Scene, engine: ^Engine, cmd: vk.CommandBuffer) ->(ok:bool)
GAME_DEINIT_FUNC :: #type proc(self: ^Scene, engine: ^Engine,) ->(ok:bool)



GameAPI :: struct {
    init : GAME_INIT_FUNC,
    update : GAME_UPDATE_FUNC,
    draw: GAME_DRAW_FUNC,
    deinit: GAME_DEINIT_FUNC,
}

game_manager_game_init :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine){
    context.allocator = self.game_allocator
    context.logger = self.game_logger
    if !self.project.api.init(scene, engine) {
        log.errorf("Game failed to init properly")
    }
    context.allocator = engine.allocator
    context.logger = engine.logger
}

game_manager_game_update :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine, delta_time: f32){
    if !self.project.api.update(scene, engine, delta_time) {
        log.errorf("Game failed to update properly")
    }
}
game_manager_game_draw :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine, cmd: vk.CommandBuffer){
    if !self.project.api.draw(scene, engine, cmd) {
        log.errorf("Game failed to draw properly")
    }
}

game_manager_game_deinit :: proc(self: ^Game_Manager, scene: ^Scene, engine: ^Engine){
    if !self.project.api.deinit(scene, engine) {
        log.errorf("Game failed to deinit properly")
    }
}
