package astro

import "core:time"


Timer :: struct {

    frame_time_target: f64,
    previous_time: time.Tick,
    delta_time: f64,

    update_interval: f64,
    update_timer: f64,
    frame_counter: u32,
    last_fps: f64,
    fps_updated: bool,

}

timer_init :: proc(t: ^Timer, refresh_rate: u32, update_interval: f64 = 1.0) {
    t^ = Timer{}
    t.frame_time_target = 1.0 / f64(refresh_rate)
    t.previous_time = time.tick_now()
    t.update_interval = update_interval
}

timer_tick :: proc(t: ^Timer) {
    
    t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))

    if t.delta_time < t.frame_time_target {
        remaining := t.frame_time_target - t.delta_time

        sleep_buffer :: 1e-3

        if remaining > sleep_buffer {
            time.sleep(time.Duration((remaining - sleep_buffer) * 1e9))
        }
        //busy waiting
        for time.duration_seconds(time.tick_since(t.previous_time)) < t.frame_time_target {}

        t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))
    }

    t.frame_counter += 1
    t.update_timer += t.delta_time
    t.fps_updated = t.update_timer >= t.update_interval

    if t.fps_updated {
        t.last_fps = f64(t.frame_counter) / t.update_timer
        t.frame_counter = 0
        t.update_timer -= t.update_interval
    }

    t.previous_time = time.tick_now()

}

timer_get_delta_time :: proc(t: Timer) -> f64 {
    return t.delta_time
}
timer_check_fps_updated :: proc(t: Timer) -> bool {
    return t.fps_updated
}
timer_get_fps :: proc(t: Timer) -> f64 {
    return t.last_fps
}
timer_get_frame_time_target :: proc(t: Timer) -> f64 {
    return t.frame_time_target
}
