package astro


import "core:strings"
import "core:log"
import "core:os"
import "core:path/filepath"

import vk "vendor:vulkan"

Shader::struct {
    name: string,
    compiled_path: string,
    source_path: string,
    type: SlangStage,
    spirv_bytes:[]byte,
}

Shader_Manager::struct {
    shaders: map[string]Shader,
    shader_directory: string,
    compiled_directory: string,
    source_directory: string,
    status_file: string,
    slang_compiler: Slang_Compiler, 
}
shader_manager_get_shader_index_by_name :: proc (self:^Shader_Manager, name:string) -> ^Shader{
   return &self.shaders[name] 
}

shader_manager_init :: proc(self: ^Shader_Manager) -> (ok: bool) {
    slang_compiler_init(&self.slang_compiler) or_return
    self.shaders = make(map[string]Shader)

    calling_directory, err := os.get_executable_directory(context.allocator)
    if err != nil {
        log.warnf("Couldn't get executable directory")
    } 
    shader_root_dir, err_root := strings.concatenate({calling_directory, "/shaders"}, context.allocator)
    if err_root != nil {
        log.warnf("Failed to concatenate string")
    } 
    self.shader_directory = shader_root_dir
    compiled, err_c := strings.concatenate({self.shader_directory, "/compiled/"}, context.allocator)
    if err_c != nil {
        log.warnf("Failed to concatenate string")
    } 
    source, err_s := strings.concatenate({self.shader_directory, "/source/"}, context.allocator)
    if err_s != nil {
        log.warnf("Failed to concatenate string")
    } 
    status, err_st := strings.concatenate({self.shader_directory, "/status.txt"}, context.allocator)
    if err_st != nil {
        log.warnf("Failed to concatenate string")
    } 
    self.compiled_directory = compiled
    self.source_directory = source
    self.status_file = status

    shader_manager_update_shaders(self)

    delete(calling_directory)

    return true
}

shader_manager_is_compiled :: proc(self: ^Shader_Manager, full_path: string) -> (compiled:bool) {
    return os.exists(full_path) 
}

shader_manager_update_shaders :: proc(self: ^Shader_Manager) -> (ok:bool,) {

    file_infos: []os.File_Info = load_directory_contents_from_disc(self.source_directory) or_return 
    defer delete(file_infos) 
    for i in 0..<len(file_infos) {   
        info := file_infos[i]
        if !strings.ends_with(info.fullpath, ".slang"){
            delete(info.fullpath)
            continue
        }
        if strings.starts_with(info.name, "inc_") {
            delete(info.fullpath)
            continue
        }

        spirv: []byte
        stage: SlangStage

        filename_stripped := strings.substring(info.name, 0, len(info.name) - len(".slang")) or_return 
        save_path, err_c := strings.concatenate({self.shader_directory, "/compiled/", filename_stripped, ".spv"}, context.allocator)
        if err_c != nil {
            log.warnf("Failed to concatenate string")
        }  

        should_save: bool
        if !shader_manager_is_compiled(self, save_path)
        {
            should_save = true
           spirv, stage = shader_manager_compile_shader(self, info.fullpath) or_return 
        }
        else {
            spirv = load_file_from_disc(save_path,) or_return
        }
        log.infof("Filename_Stripped: %v", filename_stripped)
        self.shaders[filename_stripped] = {
            name = filename_stripped,
            source_path = info.fullpath,
            type = stage,
            spirv_bytes = spirv, 
            compiled_path = save_path,
        }
        if should_save {
            shader_manager_save_compiled_shader(self, &self.shaders[filename_stripped])or_return
        }
    }   
    
    log.infof("Map Info")
    for key, value in self.shaders {
        log.infof("k(%v)\n", key)
    }

    return true
}
shader_manager_save_compiled_shader :: proc(self: ^Shader_Manager, shader: ^Shader,) -> (ok:bool,){
    ensure(shader != nil, "Invalid Shader")
    return save_file_to_disc(shader.compiled_path, shader.spirv_bytes) 
}


shader_manager_compile_shader :: proc(self: ^Shader_Manager, source_path: string,) -> (spirv: []byte, shader_stage: SlangStage, ok: bool) {

    shader_bytes := load_file_from_disc(source_path,) or_return 

    module_name := filepath.stem(source_path)
    shaders: []Slang_Compiled_Shader = slang_compile_module(
        &self.slang_compiler,
        string(shader_bytes),
        module_name,
        source_path,
        {self.source_directory},
    ) or_return
    if len(shaders) > 1 {
        log.warnf("Uh oh too many shaders in array")
    }  

    return shaders[0].spirv, shaders[0].stage, true
}
shader_manager_deinit :: proc(self: ^Shader_Manager) {
    slang_compiler_deinit(&self.slang_compiler)
    delete(self.shader_directory)
    delete(self.compiled_directory)
    delete(self.source_directory)
    delete(self.status_file)

    for key, value in self.shaders {
        delete(value.spirv_bytes)
        delete(value.compiled_path)
        delete(value.source_path)
    }
    delete(self.shaders)
}
