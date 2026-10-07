package astro

import "core:os"
import "core:log"
import "core:time"
import "core:path/filepath"




load_file_from_disc :: proc(file_name: string, flags:= os.File_Flags{}) ->(bytes : []byte, ok:bool,){
    file_handle, err := os.open(file_name, flags) 
    if err != nil {
        log.error("Failed to open the file: %v", file_name)
        return nil, false
    }
    defer os.close(file_handle)
    data, read_err := os.read_entire_file(file_handle, context.allocator)
    if read_err != nil {
        log.error("Failed to read file data %v", file_name)
        return nil, false
    }
    return data, true
}

load_directory_contents_from_disc :: proc(dir_name: string) -> (file_infos: []os.File_Info, ok: bool) {
    
    dir_handle, err := os.open(dir_name)
    if err != nil {
        return nil, false
    }
    defer os.close(dir_handle)
    

    infos, read_err := os.read_dir(dir_handle, -1, context.allocator)
    if read_err != os.ERROR_NONE {
        return nil, false
    }
    return infos, true
}

get_file_modification_time :: proc(fullpath: string) ->(mod_time: time.Time, ok:bool,) {

        stats, err := os.stat(fullpath, context.allocator)
        if err != os.ERROR_NONE {
            log.errorf("Failed to read file data from: %v", fullpath)
            return mod_time, false 
        }
        defer delete(stats.fullpath)
        return stats.modification_time, true

}

modify_file_metadata_time :: proc(fullpath: string, modification_time, access_time: time.Time) ->(ok:bool,) {

    err := os.change_times(fullpath, access_time, modification_time)
    if err != os.ERROR_NONE{
        log.errorf("Failed to update time metadata for file: %v, with Access Time = %v, Modification Time = %v", fullpath, access_time, modification_time)
        return false
    }
    return true
}

save_file_to_disc :: proc(fullpath: string, data:[]byte, flags:= os.File_Flags{}) ->(ok:bool,) {

    dir := filepath.dir(fullpath)
    if !os.exists(dir) {
        mk_err := os.make_directory_all(dir)
        if mk_err != nil {
            log.warnf("Failed to make parent directories for file. Err: %v, File: %v", mk_err, dir)
            return false
        }
    }
    
    err := os.write_entire_file(fullpath, data,)
    if err != os.ERROR_NONE{
        log.warnf("Failed to write file to disc.Error: %v,  File: %v", err, fullpath,)
        return false
    } 

    return true
}

quick_calling_dir :: proc(allocator := context.allocator) -> (calling_dir: string, ok:bool,){
    
    calling_directory, err := os.get_executable_directory(allocator)
    if err != nil {
        log.errorf("Couldn't get executable directory")
        return calling_dir, false
    } 
    return calling_directory, true
}

quick_calling_dir_subpath :: proc(subpath: string, allocator := context.allocator) -> (full_subpath:string, ok:bool) {
    calling_dir := quick_calling_dir(allocator) or_return
    full_subpath = quick_concat({calling_dir, subpath}, allocator) or_return 
    delete(calling_dir)
    return full_subpath, true
}


quick_cmd_line_runner :: proc(command:[]string, allocator := context.allocator) -> (ok:bool,) {
    
    info, std_out, std_err := quick_cmd_line_runner_with_output(command, allocator) or_return 
    success := info.exit_code == 0
    if(!success) {
        log.errorf("Program ended with non 0 exit code, piping output\nStd_Out: %v\nStd_Err: %v", string(std_out), string(std_err))
    }
    delete(std_out)
    delete(std_err)

    return success 
}

quick_cmd_line_runner_with_output :: proc(command:[]string, allocator := context.allocator) -> (process_state: os.Process_State, std_out:[]byte, std_err: []byte, ok:bool,) {

    cmd := os.Process_Desc {
        command = command,
    }
    info, out, out_err, err := os.process_exec(cmd, allocator)

    if err != nil {
        log.errorf("Failed to run Terminal command -err: %v, command: %v\nStd_Out: %v\nStd_Err: %v",err, command, out, out_err)
        return process_state, std_out, std_err, false
    }

    return info, out, out_err, true
}

