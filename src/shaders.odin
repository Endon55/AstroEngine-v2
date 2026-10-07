package astro

import "core:strings"
import "core:log"
import "core:os"
import "core:path/filepath"
import "base:runtime"
import "core:time"
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
}
Shader_Manager::struct {
    shader_dirs: [dynamic]Shader_Dir,
    shaders: map[string]Shader,
    slang_compiler: Slang_Compiler, 
    build_status: Build_Status,
}

shader_manager_get_shader_index_by_name :: proc (self:^Shader_Manager, name:string) -> ^Shader{
   return &self.shaders[name] 
}
shader_manager_add_directory :: proc(self:^Shader_Manager, directory: string, allocator:=context.allocator) ->(ok:bool) {
    
    shader_dir : Shader_Dir 
    shader_dir.shader_directory = strings.clone(directory) 
    shader_dir.compiled_directory = quick_concat({shader_dir.shader_directory, "compiled/"}, allocator) or_return
    shader_dir.source_directory = quick_concat({shader_dir.shader_directory, "source/"}, allocator) or_return
     
    append(&self.shader_dirs, shader_dir)
    // Failure is sticky across directories.
    prev_failed := self.build_status == .Failed
    self.build_status = .Compiling
    if shader_manager_update_shaders(self, &self.shader_dirs[len(self.shader_dirs) - 1], "") && !prev_failed {
        self.build_status = .Success
    } else {
        self.build_status = .Failed
    }
    return true
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

    return true
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
            log.infof("shader(%v) is out of date: recompiling", shader.name)
            spirv = shader_manager_compile_shader(self, shader_dir, shader.source_path) or_return
        }
        else {
            spirv = load_file_from_disc(shader.compiled_path,) or_return
        }

        shader.spirv_bytes = spirv
        shader.stage = stage
        self.shaders[filename_stripped] = shader

        if out_of_date{
            shader_manager_save_compiled_shader(self, &self.shaders[filename_stripped])or_return
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
    shaders: []Slang_Compiled_Shader = slang_compile_module(
        &self.slang_compiler,
        string(shader_bytes),
        module_name,
        source_path,
        {shader_dir.source_directory},
    ) or_return
    if len(shaders) > 1 {
        log.warnf("Uh oh too many shaders in array")
    }  
    for shader in shaders {
        delete(shader.name)
    }
    delete(shaders)

    return shaders[0].spirv, true
}
shader_manager_deinit :: proc(self: ^Shader_Manager) {
    slang_compiler_deinit(&self.slang_compiler)
    for shader_dir in self.shader_dirs {
        delete(shader_dir.shader_directory)
        delete(shader_dir.compiled_directory)
        delete(shader_dir.source_directory)
    }
    delete(self.shader_dirs)

    for key, value in self.shaders {
        delete(value.name)
        delete(value.spirv_bytes)
        delete(value.compiled_path)
        delete(value.source_path)
    }

    delete(self.shaders)
}







