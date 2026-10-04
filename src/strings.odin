package astro

import "core:strings"
import "core:log"

quick_concat :: proc(strs: []string, allocator:= context.allocator, loc := #caller_location) ->(concat: string, ok:bool) {
    concatstr, err_c := strings.concatenate(strs, context.allocator, loc)
    if err_c != nil {
        log.warnf("Failed to concatenate strings: %s, %s")
        return concat, false
    } 
    return concatstr, true
}


