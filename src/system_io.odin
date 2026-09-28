package astro

import "core:os"
import "core:log"


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

save_file_to_disc :: proc(fullpath: string, data:[]byte, flags:= os.File_Flags{}) ->(ok:bool,) {

    err := os.write_entire_file(fullpath, data,)
    if err != nil {
        log.warnf("Failed to write file: %v, to disc", fullpath)
        return false
    } 

    return true
}
