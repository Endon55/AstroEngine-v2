package astro


import "core:strings"
import "core:log"
import "core:os"
import "core:path/filepath"

Shader_Type::enum {
    vertex,
    fragment,
    tesselation,
    compute,
}

Shader::struct {
    name: string,
    type: Shader_Type,
}

Shader_Manager::struct {
    shaders: [dynamic] Shader,
    shader_directory: string,
    compiled_directory: string,
    source_directory: string,
    status_file: string,
    slang_compiler: Slang_Compiler, 
}

shader_manager_init :: proc(self: ^Shader_Manager) -> (ok: bool) {
    slang_compiler_init(&self.slang_compiler) or_return

    calling_directory, err := os.get_executable_directory(context.allocator)
    if err != nil {
        log.warnf("Couldn't get executable directory")
    } 
    shader_root_dir, err_root := strings.concatenate({calling_directory, "/shaders"})
    if err_root != nil {
        log.warnf("Failed to concatenate string")
    } 
    self.shader_directory = shader_root_dir
    compiled, err_c := strings.concatenate({self.shader_directory, "/compiled/"})
    if err_c != nil {
        log.warnf("Failed to concatenate string")
    } 
    source, err_s := strings.concatenate({self.shader_directory, "/source/"})
    if err_s != nil {
        log.warnf("Failed to concatenate string")
    } 
    status, err_st := strings.concatenate({self.shader_directory, "/status.txt"})
    if err_st != nil {
        log.warnf("Failed to concatenate string")
    } 
    self.compiled_directory = compiled
    self.source_directory = source
    self.status_file = status

    file_infos: []os.File_Info = load_directory_contents_from_disc(self.source_directory) or_return 
    shader_manager_compile_shader(self, file_infos[0].fullpath,) or_return 
    shader_manager_update_status(self)

    return true
}

shader_manager_compile_shader :: proc(self: ^Shader_Manager, source_path: string,) -> (spirv: []byte, ok: bool) {
    log.info("Shader Path to Compile: %v", source_path) 
    shader_bytes := load_file_from_disc(source_path,) or_return 


    shaders: []Slang_Compiled_Shader = slang_compile_module(&self.slang_compiler, string(shader_bytes),) or_return

    log.info("%v", shaders)

    return nil, true
}




//Create a file with the last modification time of every source file, and if it differs from the current modification time, then we recompile and update the status file
//So I want to check if every source file has a matching compiled file, I then want to check if the source has been updated since compilation, and 
shader_manager_update_status :: proc(self: ^Shader_Manager) -> (ok: bool){

    status_bytes := load_file_from_disc(self.status_file, os.O_CREATE) or_return
    defer delete(status_bytes)

    status_string := string(status_bytes)
    status_lines_it := status_string 

    for line in strings.split_lines_iterator(&status_lines_it) {

    } 

         
     
    //
    //
    //
    // source_dir_handle, err_s := os.open(self.source_directory)
    // if err_s != nil {
    //     return false
    // }
    // defer os.close(source_dir_handle)
    //
    // source_infos, read_err_s := os.read_dir(source_dir_handle, -1)
    // if read_err_s != os.ERROR_NONE {
    //     return false
    // }
    //
    // for info in source_infos {
    //     if info.is_dir {
    //         continue
    //     }
    //
    // }
    //
    // compiled_dir_handle, err_c := os.open(self.compiled_directory)
    // if err_c != nil {
    //     return false
    // }
    //
    // source_infos, read_err_s := os.read_dir(source_dir_handle, -1)
    // if read_err_s != os.ERROR_NONE {
    //     return false
    // }
    //
    //
    //
    // defer os.close(compiled_dir_handle)
    //
    //
    //

    //
    // source_dir_handle := load_directory_from_disc(self.source_directory) or_return
    // compiled_dir_handle := load_directory_from_disc(self.compiled_directory) or_return
    return true
}

shader_manager_deinit :: proc(self: ^Shader_Manager) {
    slang_compiler_deinit(&self.slang_compiler)
    delete(self.shader_directory)
    delete(self.compiled_directory)
    delete(self.source_directory)
}
