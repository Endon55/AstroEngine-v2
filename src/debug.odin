package astro

import "core:debug/trace"
import "core:log"


print_stack_trace :: proc() {
    capture:= trace.capture(2)
    locations, err := trace.resolve(capture)
    if err != nil {
       log.errorf("Failed to read stack trace") 
        return
    }
    defer trace.locations_destroy(locations)
    trace.print(locations)
}
