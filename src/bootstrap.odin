package astro

import "core:container/priority_queue"
import vk "vendor:vulkan"
import "vendor:glfw"
import "core:log"
import "base:runtime"
import "core:strings"



Instance_Device_Context::struct {
    vk_instance: vk.Instance,
    device: vk.Device,
    physical_devices: []Physical_Device,  
    physical_device_count: u32,
    physical_device: Physical_Device,
    debug_message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    debug_message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    debug_ser_data_pointer: rawptr,
    allocation_callbacks: ^vk.AllocationCallbacks,
}

Physical_Device::struct{

    vk_physical_device: vk.PhysicalDevice,
    queue_families: []vk.QueueFamilyProperties,
    queue_family_count: u32,
    universal_queue_family_index: u32,
    has_universal_queue_family: bool,
    properties : vk.PhysicalDeviceProperties,
    features : vk.PhysicalDeviceFeatures,
    extensions: []vk.ExtensionProperties,
    score: i32,
    suitable: bool,
}

Queue_Family::struct{
    enabled: bool,
    index: u32,
}

create_vk_instance :: proc(self: ^Instance_Device_Context, engine: ^Engine) -> (ok: bool,) {
    g_logger = context.logger

    ta:= context.temp_allocator

   //required to load the function pointer addresses
    vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
    assert(vk.CreateInstance != nil)


    self.debug_message_severity = {.WARNING, .ERROR}
    self.debug_message_type = {.GENERAL, .VALIDATION, .PERFORMANCE}

    app_info := vk.ApplicationInfo {
        sType = .APPLICATION_INFO,
        pApplicationName = "Astro",
        applicationVersion = vk.MAKE_API_VERSION(1, 4, 0, 0),
        pEngineName = "Astro",
        engineVersion = vk.MAKE_API_VERSION(1, 4, 0, 0),
        apiVersion = vk.API_VERSION_1_4,
    }
    extensions:= glfw.GetRequiredInstanceExtensions()

    layer_count : u32
    layers_used := make([dynamic]cstring, ta)
    vk.EnumerateInstanceLayerProperties(&layer_count, nil)
    layers := make([]vk.LayerProperties, layer_count, ta)
    vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers))

    for i in 0..<layer_count {
        if string(cstring(&layers[i].layerName[0])) == "VK_LAYER_KHRONOS_validation" {
            append(&layers_used, "VK_LAYER_KHRONOS_validation")
        }
    }

    instance_create_info := vk.InstanceCreateInfo {
        sType = .INSTANCE_CREATE_INFO,
        pApplicationInfo = &app_info,
        enabledExtensionCount = u32(len(extensions)),
        ppEnabledExtensionNames = raw_data(extensions),
        enabledLayerCount = u32(len(layers_used)),
        ppEnabledLayerNames = raw_data(layers_used)
    }

     vk_check(vk.CreateInstance(&instance_create_info, 
            self.allocation_callbacks,
            &self.vk_instance)) or_return

    //load the remaining addresses
    vk.load_proc_addresses(self.vk_instance)

    when ODIN_DEBUG {
        log.debugf("Adding debug callback to  Vulkan")


        // vk_debug_messenger: vk.DebugUtilsMessengerCallbackEXT
        debug_utils_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
            sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            pNext = nil,
            messageSeverity = self.debug_message_severity,
            messageType = self.debug_message_type,
            pfnUserCallback = default_debug_callback,
            pUserData = engine
        }
    }
    return true
}

select_vk_physical_device :: proc(self: ^Instance_Device_Context) -> (ok:bool,) {

    ta := context.temp_allocator
    vk_check(vk.EnumeratePhysicalDevices(self.vk_instance, &self.physical_device_count, nil)) or_return

    vk_physical_devices := make([]vk.PhysicalDevice, self.physical_device_count, ta)
        vk_check(vk.EnumeratePhysicalDevices(self.vk_instance, &self.physical_device_count, raw_data(vk_physical_devices))) or_return

    self.physical_devices = make([]Physical_Device, self.physical_device_count, ta)


    best_device: i32 = -1
    best_score: i32 = -1
    for i in 0..<self.physical_device_count {
        self.physical_devices[i].vk_physical_device = vk_physical_devices[i]
        query_physical_device(&self.physical_devices[i])
        if self.physical_devices[i].suitable {
            if self.physical_devices[i].score > best_score {
                best_score = self.physical_devices[i].score
                best_device = i32(i)
            } 
        }
    }
    
    if best_device == -1 {
        log.debugf("Test")
        return false
    } 

    self.physical_device = self.physical_devices[best_device]

    return true
}

query_physical_device ::proc(self: ^Physical_Device){
    self.suitable = true
    self.score = 0
    vk.GetPhysicalDeviceProperties(self.vk_physical_device, &self.properties)
    vk.GetPhysicalDeviceFeatures(self.vk_physical_device, &self.features)

    extension_count: u32

    vk.EnumerateDeviceExtensionProperties(self.vk_physical_device, nil, &extension_count, nil)
    self.extensions = make([]vk.ExtensionProperties, extension_count, context.temp_allocator)
    vk.EnumerateDeviceExtensionProperties(self.vk_physical_device, nil, &extension_count, raw_data(self.extensions))

    vk.GetPhysicalDeviceQueueFamilyProperties(self.vk_physical_device, &self.queue_family_count, nil)
    self.queue_families = make([]vk.QueueFamilyProperties, self.queue_family_count, context.temp_allocator)

    vk.GetPhysicalDeviceQueueFamilyProperties(self.vk_physical_device, &self.queue_family_count, raw_data(self.queue_families))

    for i in 0..<self.queue_family_count {
        family:= self.queue_families[i]
        if .COMPUTE in family.queueFlags && .GRAPHICS in family.queueFlags && .TRANSFER in family.queueFlags {

            self.has_universal_queue_family = true
            self.universal_queue_family_index = (u32(i))
        }
    }
    self.suitable = self.has_universal_queue_family 
    
    #partial switch self.properties.deviceType {

    case .DISCRETE_GPU:
        self.score += 1000 
    case .INTEGRATED_GPU:
        self.score += 500 
    case .VIRTUAL_GPU:
        self.score += 100
    }
               
}

create_vk_logical_device :: proc(self: ^Instance_Device_Context)  -> (ok: bool,) {

    // ta := context.temp_allocator
    queue_priority: f32 = 1.0
    device_queue_create_info := vk.DeviceQueueCreateInfo {
        sType = .DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = self.physical_device.universal_queue_family_index,
        queueCount = 1,
        pQueuePriorities = &queue_priority,
    }

    device_create_info := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        pQueueCreateInfos = &device_queue_create_info,
        queueCreateInfoCount = 1,
        pEnabledFeatures = &self.physical_device.features
    }
    
    vk_check(vk.CreateDevice(self.physical_device.vk_physical_device, &device_create_info, nil, &self.device)) or_return


    return true
}

default_debug_callback :: proc "system" (message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: rawptr) -> b32 {

    context = runtime.default_context()
    context.logger = g_logger

    if .WARNING in message_severity {
        log.warnf("[%v]: %s", message_types, p_callback_data.pMessage)
    } else if .ERROR in message_severity {
        log.errorf("[%v]: %s", message_types, p_callback_data.pMessage)
        //runtime.debug_trap()
    } else {
        log.infof("[%v]: %s", message_types, p_callback_data.pMessage)
    }

    return false
}


create_swapchain ::proc(self:^Engine) -> (ok: bool,) {





    return true
}
