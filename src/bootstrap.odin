package astro

import vk "vendor:vulkan"
import "vendor:glfw"
import "core:log"
import "core:slice"
import "base:runtime"



Vulkan_Creation_Context::struct {
    vk_instance: vk.Instance,
    vk_device: vk.Device,
    vk_feature_requirements: Vulkan_Feature_Requirements,
    physical_device: Physical_Device,
    vk_debug_messenger: vk.DebugUtilsMessengerEXT,
    debug_message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    debug_message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    debug_ser_data_pointer: rawptr,
    allocation_callbacks: ^vk.AllocationCallbacks,
    vk_surface: vk.SurfaceKHR,
    swapchain_context: Swapchain_Context,
}

Swapchain_Context::struct {

    vk_device: vk.Device,
    physical_device: Physical_Device,
    vk_swapchain: vk.SwapchainKHR,
    image_count: u32,
    vk_surface: vk.SurfaceKHR,
    vk_surface_format: vk.SurfaceFormatKHR,
    vk_image_usage_flags: vk.ImageUsageFlags,
    vk_extent: vk.Extent2D,
    vk_present_mode: vk.PresentModeKHR,
    allocation_callbacks: ^vk.AllocationCallbacks,
}

Physical_Device::struct{

    vk_physical_device: vk.PhysicalDevice,
    queue_families: []vk.QueueFamilyProperties,
    
    universal_queue_family_index: u32,
    present_queue_family_index: u32,

    has_universal_queue_family: bool,
    properties : vk.PhysicalDeviceProperties,
    features : vk.PhysicalDeviceFeatures,
    features_11: vk.PhysicalDeviceVulkan11Features, 
    features_12: vk.PhysicalDeviceVulkan12Features,
    features_13: vk.PhysicalDeviceVulkan13Features,
    features_14: vk.PhysicalDeviceVulkan14Features,
    extensions: []vk.ExtensionProperties,
    surface_capabilities: vk.SurfaceCapabilitiesKHR,
    surface_formats: []vk.SurfaceFormatKHR,
    surface_present_modes: []vk.PresentModeKHR,

}

Vulkan_Feature_Requirements::struct{
    instance_extensions: [dynamic]cstring,
    device_properties: vk.PhysicalDeviceProperties,
    device_features: vk.PhysicalDeviceFeatures,
    device_features_11: vk.PhysicalDeviceVulkan11Features,
    device_features_12: vk.PhysicalDeviceVulkan12Features,
    device_features_13: vk.PhysicalDeviceVulkan13Features,
    device_features_14: vk.PhysicalDeviceVulkan14Features,
    device_extensions: [dynamic]cstring,
}

create_vk_instance :: proc(self: ^Vulkan_Creation_Context, feature_requirements: Vulkan_Feature_Requirements, engine: ^Engine) -> (ok: bool,) {
    g_logger = context.logger
    ta:= context.temp_allocator
    self.vk_feature_requirements = feature_requirements
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
    
    glfw_extensions:= glfw.GetRequiredInstanceExtensions()
    extensions: [dynamic]cstring = slice.clone_to_dynamic(glfw_extensions[:])
    defer delete(extensions)

    append(&extensions, "VK_EXT_debug_utils")
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
        log.debugf("Adding debug callback to Vulkan")


   
        debug_utils_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
            sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            pNext = nil,
            messageSeverity = self.debug_message_severity,
            messageType = self.debug_message_type,
            pfnUserCallback = default_debug_callback,
            pUserData = engine
        }
        assert(vk.CreateDebugUtilsMessengerEXT != nil)
        vk.CreateDebugUtilsMessengerEXT(self.vk_instance, &debug_utils_create_info, self.allocation_callbacks, &self.vk_debug_messenger)
    }
    return true
}

select_vk_physical_device :: proc(self: ^Vulkan_Creation_Context, vk_surface: vk.SurfaceKHR) -> (ok:bool,) {

    ta := context.temp_allocator
    self.vk_surface = vk_surface
    self.swapchain_context.vk_surface = self.vk_surface

    // self.physical_device_requirements.extensions = make([dynamic]cstring, context.allocator)
    // append(&self.physical_device_requirements.extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
    //
    // append(&self.physical_device_requirements.extensions, vk.KHR_PIPELINE_LIBRARY_EXTENSION_NAME)
    // append(&self.physical_device_requirements.extensions, vk.EXT_GRAPHICS_PIPELINE_LIBRARY_EXTENSION_NAME)
    //
    physical_device_count: u32  
    vk_check(vk.EnumeratePhysicalDevices(self.vk_instance, &physical_device_count, nil)) or_return
    
    vk_physical_devices := make([]vk.PhysicalDevice, physical_device_count, ta)
        vk_check(vk.EnumeratePhysicalDevices(self.vk_instance, &physical_device_count, raw_data(vk_physical_devices))) or_return

    physical_devices := make([]Physical_Device, physical_device_count, ta)
    
    best_device: i32 = -1
    best_score: i32 = -1
    for i in 0..<physical_device_count {
        physical_devices[i].vk_physical_device = vk_physical_devices[i]
        query_physical_device(&physical_devices[i], vk_surface)
        suitable, score := evaluate_physical_device(physical_devices[i], self.vk_feature_requirements)
        if suitable {
            if score > best_score {
                best_score = score
                best_device = i32(i)
            } 
        }
    }
    
    if best_device == -1 {
        log.debugf("Test")
        return false
    } 

    self.physical_device = physical_devices[best_device]

    return true
}

create_vk_logical_device :: proc(self: ^Vulkan_Creation_Context)  -> (ok: bool,) {

    // ta := context.temp_allocator

    buffer_device_address_features:= vk.PhysicalDeviceBufferDeviceAddressFeatures {
        sType = .PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES,
        bufferDeviceAddress = true,
    }

    queue_priority: f32 = 1.0
    device_queue_create_info := vk.DeviceQueueCreateInfo {
        sType = .DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = self.physical_device.universal_queue_family_index,
        queueCount = 1,
        pQueuePriorities = &queue_priority,
    }

    device_create_info := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        pNext = &buffer_device_address_features,
        pQueueCreateInfos = &device_queue_create_info,
        queueCreateInfoCount = 1,
        pEnabledFeatures = &self.physical_device.features,
        enabledExtensionCount = u32(len(self.vk_feature_requirements.device_extensions)),
        ppEnabledExtensionNames = raw_data(self.vk_feature_requirements.device_extensions),
    }
    
    vk_check(vk.CreateDevice(self.physical_device.vk_physical_device, &device_create_info, nil, &self.vk_device)) or_return

    self.swapchain_context.physical_device = self.physical_device
    self.swapchain_context.vk_device = self.vk_device

    return true
}

create_vk_swapchain ::proc(self: ^Swapchain_Context, width, height :u32 ) -> (ok: bool,) {

    self.vk_extent = choose_swapchain_extents(self.physical_device.surface_capabilities, width, height)
    self.vk_present_mode = choose_swapchain_present_mode(self.physical_device)
    self.vk_surface_format = choose_swapchain_format(self.physical_device)
    self.vk_image_usage_flags = {.COLOR_ATTACHMENT, .TRANSFER_DST}
  

    //max image of 0 indicates infinite max
    min_images := self.physical_device.surface_capabilities.minImageCount
    max_images := self.physical_device.surface_capabilities.maxImageCount

    if self.image_count < min_images {self.image_count = min_images}
    if max_images > 0 && self.image_count > max_images {self.image_count = max_images}

    swapchain_create_info := vk.SwapchainCreateInfoKHR {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        flags = {},
        surface = self.vk_surface,
        minImageCount = self.image_count,
        imageFormat = self.vk_surface_format.format,
        imageColorSpace = self.vk_surface_format.colorSpace,
        imageExtent = choose_swapchain_extents(self.physical_device.surface_capabilities, width, height),
        imageArrayLayers = 1,
        imageUsage = self.vk_image_usage_flags,
        preTransform = self.physical_device.surface_capabilities.currentTransform,
        compositeAlpha = {.OPAQUE},
        presentMode = choose_swapchain_present_mode(self.physical_device),
        clipped = true,
    }

    queue_family_indices := []u32 {
        self.physical_device.universal_queue_family_index, self.physical_device.present_queue_family_index,
    }
    if queue_family_indices[0] != queue_family_indices[1] {
        swapchain_create_info.imageSharingMode = .CONCURRENT
        swapchain_create_info.queueFamilyIndexCount = u32(len(queue_family_indices))
        swapchain_create_info.pQueueFamilyIndices = raw_data(queue_family_indices)
    } else {
        swapchain_create_info.imageSharingMode = .EXCLUSIVE
    }
    vk_check(vk.CreateSwapchainKHR(self.vk_device, &swapchain_create_info, self.allocation_callbacks, &self.vk_swapchain), "Failed to create swapchain") or_return


    return true
}


/* ***************************************************************
   -----------------------Helper Functions------------------------
   ************************************************************ */



@(private="file")
query_physical_device ::proc(self: ^Physical_Device, surface: vk.SurfaceKHR){

    vk.GetPhysicalDeviceProperties(self.vk_physical_device, &self.properties)

    vk.GetPhysicalDeviceFeatures(self.vk_physical_device, &self.features)
    
    self.features_14 = {
        sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
        pNext = nil,
    }
    self.features_13 = {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        pNext = &self.features_14,
    }
    self.features_12 = {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        pNext = &self.features_13,
    }
    self.features_11 = {
        sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        pNext = &self.features_12,
    }


    feature_chain := vk.PhysicalDeviceFeatures2 {
        sType = .PHYSICAL_DEVICE_FEATURES_2,
        pNext = &self.features_11,
    }

    vk.GetPhysicalDeviceFeatures2(self.vk_physical_device, &feature_chain)

    extension_count: u32

    vk.EnumerateDeviceExtensionProperties(self.vk_physical_device, nil, &extension_count, nil)
    self.extensions = make([]vk.ExtensionProperties, extension_count, context.allocator)
    vk.EnumerateDeviceExtensionProperties(self.vk_physical_device, nil, &extension_count, raw_data(self.extensions))

    queue_family_count: u32

    vk.GetPhysicalDeviceQueueFamilyProperties(self.vk_physical_device, &queue_family_count, nil)
    self.queue_families = make([]vk.QueueFamilyProperties, queue_family_count, context.allocator)

    vk.GetPhysicalDeviceQueueFamilyProperties(self.vk_physical_device, &queue_family_count, raw_data(self.queue_families))

    for i in 0..<queue_family_count {
        family:= self.queue_families[i]
        if .COMPUTE in family.queueFlags && .GRAPHICS in family.queueFlags && .TRANSFER in family.queueFlags {

            self.has_universal_queue_family = true
            self.universal_queue_family_index = (u32(i))
        }
    }

    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(self.vk_physical_device, surface, &self.surface_capabilities)


    format_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(self.vk_physical_device, surface, &format_count, nil)
    if format_count > 0 {
        self.surface_formats = make([]vk.SurfaceFormatKHR, format_count, context.allocator)
        vk.GetPhysicalDeviceSurfaceFormatsKHR(self.vk_physical_device, surface, &format_count, raw_data(self.surface_formats))
    }
    present_count: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(self.vk_physical_device, surface, &present_count, nil)
    if present_count > 0 {
        self.surface_present_modes = make([]vk.PresentModeKHR, present_count, context.allocator)
        vk.GetPhysicalDeviceSurfacePresentModesKHR(self.vk_physical_device, surface, &present_count, raw_data(self.surface_present_modes))
    }
    // for i in 0..<format_count {
    //     format := self.surface_formats[i]
    //     log.infof("Format: %#v", format)
    // }
}

@(private="file")
evaluate_physical_device :: proc(self: Physical_Device, requirements: Vulkan_Feature_Requirements) ->(suitable: bool, score:i32) {

    suitable = true
    score = 0
    suitable = self.has_universal_queue_family && len(self.surface_formats) > 0 && len(self.surface_present_modes) > 0 //&& supports_all_features(self, requirements)
    if !suitable {
        return suitable, score
    }
    ext_count := len(requirements.device_extensions)

    for i in 0..<ext_count {
        found : bool
        for j in 0..<len(self.extensions) {
            if cstring(&self.extensions[j].extensionName[0]) == requirements.device_extensions[i]{
                found = true
                break 
            }
        }
        if found  == false{
            suitable = false
        }
    }

    


    #partial switch self.properties.deviceType {
    case .DISCRETE_GPU:
        score += 1000 
    case .INTEGRATED_GPU:
        score += 500 
    case .VIRTUAL_GPU:
        score += 100
    }
    return suitable, score
}

@(private="file")
supports_all_features :: proc(self: Physical_Device, reqs: Vulkan_Feature_Requirements) ->(suitable: bool) {



    return compare_structs(self.features, reqs.device_features) &&
            compare_structs(self.features, reqs.device_features_11)
}



@(private="file")
choose_swapchain_format :: proc(self: Physical_Device) -> (format: vk.SurfaceFormatKHR) {
    

    for i in 0..<len(self.surface_formats) {
        format := self.surface_formats[i]
        if format.format == .B8G8R8_UNORM && format.colorSpace == .SRGB_NONLINEAR {
            return format
        } 
    }
    return self.surface_formats[0]
}

@(private="file")
choose_swapchain_present_mode :: proc(self: Physical_Device) -> (mode: vk.PresentModeKHR) {
 
    immediate: int = -1
    fifo: int = -1
    for i in 0..<len(self.surface_present_modes) {
        mode := self.surface_present_modes[i]
        if mode == .MAILBOX {
            return mode     
        } 
        else if mode == .IMMEDIATE {
            immediate = i
        }
        else if mode == .FIFO {
            fifo = i
        }
    }


    if immediate != -1 {
        return self.surface_present_modes[immediate]
    }

    return self.surface_present_modes[fifo]
}

@(private="file")
choose_swapchain_extents :: proc(capabilities: vk.SurfaceCapabilitiesKHR, width, height: u32) -> (vk.Extent2D,) {

   if  capabilities.currentExtent.width != max(u32) {
       return capabilities.currentExtent
   }

   fixed_extent: vk.Extent2D = {width, height}

  	fixed_extent.width = max(
		capabilities.minImageExtent.width,
		min(capabilities.maxImageExtent.width, fixed_extent.width),
	)
	fixed_extent.height = max(
		capabilities.minImageExtent.height,
		min(capabilities.maxImageExtent.height, fixed_extent.height),
	)

return fixed_extent
}

default_debug_callback :: proc "system" (message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: rawptr) -> b32 {

    context = runtime.default_context()
    context.logger = g_logger
    if .WARNING in message_severity {
        log.warnf("[%v]: %s", message_types, p_callback_data.pMessage)
    } else if .ERROR in message_severity {
        log.errorf("[%v]: %s", message_types, p_callback_data.pMessage)
        runtime.debug_trap()
    } else {
        log.infof("[%v]: %s", message_types, p_callback_data.pMessage)
    }

    return false
}

swapchain_get_images :: proc (self: Swapchain_Context, max_images:u32 = 0, allocator:= context.allocator, loc := #caller_location) -> (images: []vk.Image, err :bool,) {

    assert(self.vk_swapchain != {}, "Invalid Swapchain", loc)

    image_count: u32
    vk_check(vk.GetSwapchainImagesKHR(self.vk_device, self.vk_swapchain, &image_count, nil)) or_return

    if max_images > 0 && image_count > max_images {
        image_count = max_images
    }

    images = make([]vk.Image, image_count, allocator)
    defer if err {delete(images, allocator)}


    vk_check(vk.GetSwapchainImagesKHR(self.vk_device, self.vk_swapchain, &image_count, raw_data(images)), "Failed to create swapchain images") or_return
    return
}

swapchain_get_image_views :: proc (self: Swapchain_Context, images :[]vk.Image, allocator := context.allocator, loc:= #caller_location) ->(views: []vk.ImageView, err:bool,) {

    view_usage_info := vk.ImageViewUsageCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        usage = self.vk_image_usage_flags,
        
    }

    views = make([]vk.ImageView, len(images), allocator)
    defer if err {
        delete(views, allocator)
    }

    for i in 0..<len(images) {
        view_info := vk.ImageViewCreateInfo {
            sType = .IMAGE_VIEW_CREATE_INFO,
            //pNext = &view_usage_info,
            image = images[i],
            viewType = .D2,
            format = self.vk_surface_format.format,
            components = {
                r = .IDENTITY,
                g = .IDENTITY,
                b = .IDENTITY,
                a = .IDENTITY,
            },
            subresourceRange = {
                aspectMask = {.COLOR},
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            }
        }
        vk_check(vk.CreateImageView(self.vk_device, &view_info, self.allocation_callbacks, &views[i])) or_return
    }

        return
}


device_get_universal_queue :: proc (self: Vulkan_Creation_Context) ->(out_queue: vk.Queue, err: bool) {

    vk.GetDeviceQueue(self.vk_device, self.physical_device.universal_queue_family_index, 0, &out_queue)
    return

}

device_get_universal_queue__index :: proc (self: Vulkan_Creation_Context) -> (index: u32, err: bool) {
    
    return self.physical_device.universal_queue_family_index, false
}

compare_features_structs :: proc (self, comparitor_struct: $T) -> (suitable: bool) {

    if !intrinsics.type_is_struct(T) {
        return false
    } 

    type_info := reflect.Type_Info_Struct(T)
    
    for i in 0..<type_info.field_count {
        
        offset := type_info.offsets[i]
        self_value := (^b32)(uintptr(&self) + offset)^
        comparitor_value := (^b32)(uintptr(&comparitor_struct) + offset)^
        
        if !comparitor_value {
            continue
        }
        if !self_value {
            return false
        }
    }
    return true
}
