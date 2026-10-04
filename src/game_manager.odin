package astro

import "core:os"
import "core:log"
import "core:time"
import "core:strings"


Game :: struct {
    name: string,
    scenes: [dynamic]Scene,
}

Game_Manager :: struct {
    game: Game,
    project: Project,
    calling_dir: string,
    executable_path: string,
}

Project :: struct {
    name: string,
    directory: string,
    src_dir: string,
    shader_dir: string,
    asset_dir: string,
    tmp_dir: string,
    game_so: string,
}

game_manager_init :: proc(self: ^Game_Manager, path_to_project: string, allocator:=context.allocator) ->(ok:bool) {


    self.calling_dir = quick_calling_dir() or_return
    self.executable_path = os.args[0]

    if path_to_project == "" {
        self.project.directory = quick_concat({self.calling_dir, "/game"}, allocator) or_return
    }
    else {
        self.project.directory = strings.clone(path_to_project)
    }
    //open the file, grab the assets, shaders, src, file handles. Grab the .so file handle if available.
    if !os.exists(self.project.directory) {
        log.errorf("Project path is invalid: %v", path_to_project)
    }    
    self.project.src_dir = quick_concat({self.project.directory, "/src"}) or_return
    self.project.shader_dir = quick_concat({self.project.directory, "/shaders"}) or_return
    self.project.asset_dir = quick_concat({self.project.directory, "/assets"}) or_return
    self.project.tmp_dir = quick_concat({self.project.directory, "/tmp"}) or_return
    self.project.game_so = quick_concat({self.project.directory, "/game.so"}) or_return

    game_manager_init_so(&self.project, self) or_return
    
       return true
}


@(private="file")
game_manager_init_so:: proc(self: ^Project, manager: ^Game_Manager) ->(ok:bool, ){
    if os.exists(self.game_so) {
        so_time: time.Time = get_file_modification_time(self.game_so) or_return 
        exe_time: time.Time = get_file_modification_time(manager.executable_path) or_return

        if exe_time._nsec < so_time._nsec {
            game_manager_compile(self) or_return
        }
    } else {
        game_manager_compile(self) or_return
    }
    return true
}


@(private="file")
game_manager_compile :: proc(self: ^Project) -> (ok: bool) {
    out: string = quick_concat({"-out:", self.game_so}) or_return
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
game_manager_deinit :: proc(self: ^Game_Manager, engine: ^Engine) -> (ok:bool,) {
    delete(self.calling_dir)
    delete(self.project.directory)
    delete(self.project.shader_dir)
    delete(self.project.asset_dir)
    delete(self.project.src_dir)
    delete(self.project.tmp_dir)
    delete(self.project.game_so)

    return true
}
