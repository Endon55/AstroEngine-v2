package astro

import vk "vendor:vulkan"
import "vendor:glfw"


create_vk_instance :: proc(self: ^Engine) -> (ok: bool,) {

    ta:= context.temp_allocator
    app_info := vk.ApplicationInfo {
        sType = .APPLICATION_INFO,
        pApplicationName = "Astro",
        applicationVersion = vk.MAKE_API_VERSION(1, 0, 0, 0),
        pEngineName = "Astro",
        engineVersion = vk.MAKE_API_VERSION(1, 0, 0, 0),
        apiVersion = vk.API_VERSION_1_0,
    }
    extensions:= glfw.GetRequiredInstanceExtensions()
    layers := make([dynamic]cstring, ta)

    instance_create_info := vk.InstanceCreateInfo {
        sType = .INSTANCE_CREATE_INFO,
        pApplicationInfo = &app_info,
        enabledExtensionCount = u32(len(extensions)),
        ppEnabledExtensionNames = raw_data(extensions),
        enabledLayerCount = 0,
    }


    vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
    assert(vk.CreateInstance != nil)

    vk_check(vk.CreateInstance(&instance_create_info, 
            nil,
            &self.vk_instance)) or_return

    return true
}
