package astro


import "base:intrinsics"
import "core:mem"
import "core:log"
import "base:runtime"

import vk "vendor:vulkan"
import "libs:vma"

FRAME_UNIFORM_SIZE :: mem.Kilobyte * 4
ARENA_SIZE :: mem.Kilobyte * 128
TEXTURE_BUFFER_CAPACITY :: 1024
DATA_FRAMES_BUFFERED:: 3


/*
3 types of data based on how often the CPU has to touch it.

Large Amounts of Data, Set and forget, like textures and vertex data, the cpu doesn't need to modify or touch this data on the gpu ever again.

Medium Amounts of Data that need to be updated every frame.(Particle effects, GUI). Stage it in a cpu ring buffer and have the gpu copy it to its own ring buffer.

Small Amounts of Data that need to be updated frequently. Like uniform data and push constants. , ocean parameters. The cpu directly copies this to the gpu memory.



    Plan - 
    Ill make some kind of large global buffer to store images, and vertex data

*/
Memory_Reference :: struct {
    cpu_pointer: rawptr,
    gpu_offset: vk.DeviceSize, 
    size: vk.DeviceSize,
}

Texture_Reference :: struct {
    image: Allocated_Image,
    index: u32,
    heap_address: vk.DeviceAddress,
    heap_offset: vk.DeviceSize,
}

Arena_Reference :: struct {
    arena_address: vk.DeviceAddress,
    arena_offset: vk.DeviceSize,
    descriptor_size: vk.DeviceSize,
    frames_buffered: vk.DeviceSize,
}
Ping_Pong_Reference :: struct {
    textures: [2]Texture_Reference,
    read_index: u32,
    write_index: u32,
}

Uniform_Buffer :: struct {
    total_allocation_offset: vk.DeviceSize,
    shadow_buffer_ptr: rawptr,
    frame_ptr: rawptr,
    
    ring_buffer: Allocated_Buffer,
    frame_buffer_size: vk.DeviceSize,
    total_buffer_size: vk.DeviceSize,
}

Texture_Heap :: struct {
    max_textures: u32,
    next_index: u32,
    freed_indexes: [dynamic] u32,
    pipeline_layout2: Pipeline_Layout2,

    descriptor_size: vk.DeviceSize,
    arena_reference: Arena_Reference,
    bind_info: vk.DescriptorBufferBindingInfoEXT,
    buffer: Allocated_Buffer,
}
Descriptor_Arena:: struct {
    size: vk.DeviceSize,
    bump_offset: vk.DeviceSize,
    alignment: vk.DeviceSize,
    
    bind_info: vk.DescriptorBufferBindingInfoEXT,
    buffer: Allocated_Buffer,
}

Memory_Manager :: struct {
    vk_device: vk.Device,
    MIN_UNIFORM_ALIGNMENT: vk.DeviceSize,
    vma_allocator: vma.Allocator,
    device_limits: vk.PhysicalDeviceLimits,
    physical_device: ^Physical_Device,
    uniform : Uniform_Buffer,
    texture_heap: Texture_Heap,
    descriptor_arena: Descriptor_Arena,
    frames_buffered: vk.DeviceSize,
    universal_layout: Set_Layout,
    universal_memory: Set_Memory,
    draw_frame: u32,
    write_frame: u32,
}


memory_manager_init :: proc(self:^ Memory_Manager, engine: ^Engine)->(ok:bool) {
    
    self.vk_device = engine.vk_device
    self.physical_device = &engine.vk_context.physical_device
    self.device_limits = engine.vk_context.physical_device.properties.limits
    self.frames_buffered = DATA_FRAMES_BUFFERED
    device_vtable: vk.Device_VTable
    vk.load_proc_addresses_device_vtable(engine.vk_device, &device_vtable)
    vma_vulkan_functions := vma.create_device_vulkan_functions(device_vtable)

    self.MIN_UNIFORM_ALIGNMENT = self.device_limits.minUniformBufferOffsetAlignment
    if self.MIN_UNIFORM_ALIGNMENT == 0 {
        panic("Uhhhh alignment is 0")
    }

    vma_create_info: vma.AllocatorCreateInfo = {
        flags = {.BUFFER_DEVICE_ADDRESS},
        instance = engine.vk_instance,
        physicalDevice = engine.vk_physical_device,
        device = engine.vk_device,
        pVulkanFunctions = &vma_vulkan_functions,
        vulkanApiVersion = vk.API_VERSION_1_4,
    }

    vk_check(vma.CreateAllocator(vma_create_info, &self.vma_allocator), "Failed to create VMA Allocator") or_return

    deletion_queue_push(&engine.main_deletion_queue, self.vma_allocator)

    init_descriptor_arena(self, engine) or_return
    init_uniform_buffers(self, engine) or_return
    init_texture_heap(self, engine) or_return
    self.universal_layout = self.texture_heap.pipeline_layout2.set_layouts[0]
    return true
}

@(private="file")
init_uniform_buffers:: proc(self:^Memory_Manager, engine: ^Engine) ->(ok:bool,) {

    buffer:= &self.uniform.ring_buffer
    self.uniform.frame_buffer_size = get_aligned_uniform_size(self, FRAME_UNIFORM_SIZE) 
    self.uniform.total_buffer_size = self.uniform.frame_buffer_size * vk.DeviceSize(self.frames_buffered)
    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = self.uniform.total_buffer_size,
        usage = {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
    }
    alloc_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
    }

    vk_check(vma.CreateBuffer(self.vma_allocator, buffer_info, alloc_info, &buffer.buffer, &buffer.allocation, &buffer.info), "Failed to create VMA Ring Buffer") or_return

    buffer.mapped_ptr = buffer.info.pMappedData

    shadow_buffer, err:= mem.alloc(int(self.uniform.frame_buffer_size), int(self.MIN_UNIFORM_ALIGNMENT), context.allocator)
    if err != mem.Allocator_Error.None {
        log.errorf("Failed to allocate shadow buffer.")
        return false
    }
    self.uniform.shadow_buffer_ptr = shadow_buffer
    self.uniform.frame_ptr = buffer.mapped_ptr

    buffer.allocator = self.vma_allocator
    buffer.size = self.uniform.total_buffer_size

    address_info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.buffer,
    }
    buffer.device_address = vk.GetBufferDeviceAddress(self.vk_device, &address_info)

    deletion_queue_push(&engine.main_deletion_queue, Raw_Memory{ptr = shadow_buffer, allocator = context.allocator, size = u32(self.uniform.frame_buffer_size)})
    deletion_queue_push(&engine.main_deletion_queue, buffer^)    
    return true
}


@(private="file")
init_texture_heap :: proc(self:^Memory_Manager, engine:^Engine) ->(ok:bool,) {

    //Create the Texture storage buffer
    self.texture_heap.max_textures = TEXTURE_BUFFER_CAPACITY
    self.texture_heap.freed_indexes = make([dynamic]u32)
    binding:= vk.DescriptorSetLayoutBinding {
        binding = 0,
        descriptorType = .SAMPLED_IMAGE,
        descriptorCount = self.texture_heap.max_textures,
        stageFlags = {.COMPUTE, .VERTEX, .FRAGMENT},
        pImmutableSamplers = nil,
    }
    binding_flags := vk.DescriptorBindingFlags {
        .PARTIALLY_BOUND,
    }

    layout_binding_flags_info := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        bindingCount = 1,
        pBindingFlags = &binding_flags,
    }

    layout_info := vk.DescriptorSetLayoutCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        pNext = &layout_binding_flags_info,
        flags = {.DESCRIPTOR_BUFFER_EXT,},
        bindingCount = 1,
        pBindings = &binding,
    }
    self.texture_heap.pipeline_layout2.set_layouts = make([]Set_Layout, 1)
    vk_check(vk.CreateDescriptorSetLayout(
            self.vk_device,
            &layout_info,   
            nil,
            &self.texture_heap.pipeline_layout2.set_layouts[0].vk_layout), "Failed to create Texture[] descriptors") or_return

    deletion_queue_push(&engine.main_deletion_queue, Raw_Memory{ptr = raw_data(self.texture_heap.pipeline_layout2.set_layouts), allocator = context.allocator})

    vk.GetDescriptorSetLayoutSizeEXT(self.vk_device, self.texture_heap.pipeline_layout2.set_layouts[0].vk_layout, &self.texture_heap.pipeline_layout2.set_layouts[0].total_set_size)
    self.texture_heap.pipeline_layout2.set_layouts[0].binding_layouts= make([]Binding_Layout, 1)
    deletion_queue_push(&engine.main_deletion_queue, Raw_Memory{ptr = raw_data(self.texture_heap.pipeline_layout2.set_layouts[0].binding_layouts), allocator = context.allocator})
    vk.GetDescriptorSetLayoutBindingOffsetEXT(self.vk_device,  self.texture_heap.pipeline_layout2.set_layouts[0].vk_layout, 0, &self.texture_heap.pipeline_layout2.set_layouts[0].binding_layouts[0].offset)
    self.texture_heap.pipeline_layout2.set_layouts[0].binding_layouts[0].vk_layout = binding
    self.texture_heap.pipeline_layout2.set_layouts[0].binding_layouts[0].type = binding.descriptorType 
    self.texture_heap.pipeline_layout2.set_layouts[0].binding_layouts[0].binding_size = get_descriptor_size(self, binding.descriptorType) 

    push_constants_range := vk.PushConstantRange{
        stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
        offset = 0,
        size = 128,
    }
    pipeline_layout_info := vk.PipelineLayoutCreateInfo {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &self.texture_heap.pipeline_layout2.set_layouts[0].vk_layout,
        pushConstantRangeCount = 1, 
        pPushConstantRanges =  &push_constants_range,
    }

    vk_check(vk.CreatePipelineLayout(self.vk_device, &pipeline_layout_info, nil, &self.texture_heap.pipeline_layout2.vk_layout), "Failed to create Master Pipeline Layout") or_return
    deletion_queue_push(&engine.main_deletion_queue, self.texture_heap.pipeline_layout2.vk_layout)

    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = self.texture_heap.pipeline_layout2.set_layouts[0].total_set_size,
        usage = {.RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS},
    }
    alloc_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
    }

    buffer:= &self.texture_heap.buffer
    vk_check(vma.CreateBuffer(self.vma_allocator, buffer_info, alloc_info, &buffer.buffer, &buffer.allocation, &buffer.info), "Failed to create VMA Texture heap buffer") or_return

    device_address_info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.buffer,
    }
    buffer.device_address = vk.GetBufferDeviceAddress(self.vk_device, &device_address_info)
    buffer.mapped_ptr = buffer.info.pMappedData
    self.texture_heap.descriptor_size = get_descriptor_size(self, .SAMPLED_IMAGE)
    buffer.allocator = self.vma_allocator
    self.texture_heap.bind_info = vk.DescriptorBufferBindingInfoEXT {
        sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
        address = buffer.device_address,
        usage = {
            .RESOURCE_DESCRIPTOR_BUFFER_EXT,
        }
    }

    buffer.size = self.texture_heap.pipeline_layout2.set_layouts[0].total_set_size


    deletion_queue_push(&engine.main_deletion_queue, self.texture_heap.pipeline_layout2.set_layouts[0].vk_layout)
    deletion_queue_push(&engine.main_deletion_queue, buffer^)
    return true
}

@(private="file")
init_descriptor_arena :: proc(self:^Memory_Manager, engine:^Engine) ->(ok:bool,) {
    
    arena := &self.descriptor_arena
    arena.size = vk.DeviceSize(ARENA_SIZE)
    buffer:= &arena.buffer
    arena.alignment = engine.vk_context.physical_device.properties_buffer.descriptorBufferOffsetAlignment
    
    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = arena.size,
        usage = {
            .RESOURCE_DESCRIPTOR_BUFFER_EXT,
            .SHADER_DEVICE_ADDRESS,
        },
    }
    alloc_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        flags = {
            .HOST_ACCESS_SEQUENTIAL_WRITE,
            .MAPPED,
        }
    }
    vk_check(vma.CreateBuffer(self.vma_allocator, buffer_info, alloc_info, &buffer.buffer, &buffer.allocation, &buffer.info), "Failed to create the general Descriptor Arena buffer") or_return

    address_info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.buffer,
    }
    buffer.device_address = vk.GetBufferDeviceAddress(self.vk_device, &address_info)
    buffer.mapped_ptr = buffer.info.pMappedData
    buffer.allocator = self.vma_allocator

    self.descriptor_arena.bind_info = vk.DescriptorBufferBindingInfoEXT {
        sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
        address = buffer.device_address,
        usage = {
            .RESOURCE_DESCRIPTOR_BUFFER_EXT,
        }
    }
    buffer.size = arena.size
    deletion_queue_push(&engine.main_deletion_queue, buffer^)
    return true
}

memory_manager_bind_self :: proc(self:^ Memory_Manager, cmd: vk.CommandBuffer) {
    //
    // vk.CmdBindDescriptorSets(cmd, .COMPUTE, self.texture_heap.pipeline_layout, 0, 1, &self.texture_heap.set, 0, nil,)
    // vk.CmdBindDescriptorSets(cmd, .GRAPHICS, self.texture_heap.pipeline_layout, 0, 1, &self.texture_heap.set, 0, nil,)

}

memory_manager_advance_frame :: proc(self: ^Memory_Manager) {

    //send all data to gpu.
    assert(self.uniform.shadow_buffer_ptr != nil, "Bad shadow_buffer_ptr")
    assert(self.uniform.frame_ptr != nil, "Bad frame_ptr")

    intrinsics.mem_copy_non_overlapping(self.uniform.frame_ptr, self.uniform.shadow_buffer_ptr, self.uniform.frame_buffer_size) 

    self.draw_frame = self.write_frame
    self.write_frame += 1
    self.write_frame = self.write_frame % DATA_FRAMES_BUFFERED 

    self.uniform.frame_ptr = ptr_offset(self.uniform.ring_buffer.mapped_ptr, self.uniform.frame_buffer_size * vk.DeviceSize(self.write_frame))


}

memory_manager_bind_uniform :: proc(self: ^Memory_Manager, size: u32) -> (memref:Memory_Reference) {
    
    memref.size = get_aligned_uniform_size(self, cast(vk.DeviceSize)size)
    memref.cpu_pointer = ptr_offset(self.uniform.shadow_buffer_ptr, self.uniform.total_allocation_offset) 
    memref.gpu_offset = self.uniform.total_allocation_offset
    self.uniform.total_allocation_offset += memref.size
    assert(memref.cpu_pointer != nil, "Bad pointer binding")
    return memref 
}

get_aligned_uniform_size :: proc(self: ^Memory_Manager, data_size: vk.DeviceSize) -> vk.DeviceSize{
/*
    Only works on powers of 2 which is guaranteed to be the case for this type of data
    We add nearly a full chunk(ex. 16), this ensures that if we're at 15 bytes of a 16 byte chunk we add (16-1) more bytes so that we actually round up. 
    16 = 10000
    15 = 01111
    30 = 11110
    We need to make 15 look like 16. We started by adding and getting 30, so now we just need to drop those lower 4 bits.
    We flip all the bits of 15 with ~
    ~15 = 10000
    we do 30 & ~15
    11110
    10000
    -----
    10000
    */
    return (data_size + self.MIN_UNIFORM_ALIGNMENT - 1) & (~(self.MIN_UNIFORM_ALIGNMENT - 1))
}
@(private="file")
get_aligned_arena_start :: proc(self:^Memory_Manager) -> vk.DeviceSize {
    return (self.descriptor_arena.bump_offset + self.descriptor_arena.alignment - 1) & ~(self.descriptor_arena.alignment - 1)
}

ptr_offset :: proc {
    ptr_offset_vk,
    ptr_offset_raw,
}
ptr_offset_vk :: proc(ptr:rawptr, offset:vk.DeviceSize) -> rawptr {
    return rawptr(uintptr(ptr) + uintptr(offset))
}

ptr_offset_raw :: proc(ptr:rawptr, offset:uint) -> rawptr {
    return rawptr(uintptr(ptr) + uintptr(offset))
}


memory_manager_register_texture :: proc(self:^ Memory_Manager, image: Allocated_Image) ->(texture_reference: Texture_Reference, ok:bool,) {
 
    if len(self.texture_heap.freed_indexes) > 0 {
        texture_reference.index = pop(&self.texture_heap.freed_indexes)
    } 
    else if self.texture_heap.next_index >= self.texture_heap.max_textures {
        log.errorf("No more room in heap")
        return texture_reference, false
    }
    else {
        texture_reference.index = self.texture_heap.next_index
    }
    texture_reference.image = image
    descriptor_image_info := vk.DescriptorImageInfo {
        imageView = texture_reference.image.image_view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    } 
    get_info := vk.DescriptorGetInfoEXT {
        sType = .DESCRIPTOR_GET_INFO_EXT,
        type = .SAMPLED_IMAGE,
        data = {pSampledImage = &descriptor_image_info},
    }
    texture_reference.heap_offset = self.texture_heap.pipeline_layout2.set_layouts[0].binding_layouts[0].offset + vk.DeviceSize(texture_reference.index) * self.texture_heap.descriptor_size

    dst := ptr_offset(self.texture_heap.buffer.mapped_ptr, texture_reference.heap_offset)

    vk.GetDescriptorEXT(self.vk_device, &get_info, int(self.texture_heap.descriptor_size), dst)
    texture_reference.heap_address = self.texture_heap.buffer.device_address
    if texture_reference.index == self.texture_heap.next_index{
        self.texture_heap.next_index += 1
    }

    return texture_reference, true
}

memory_manager_register_descriptor :: proc(self:^Memory_Manager, size:vk.DeviceSize, frames_buffered: vk.DeviceSize = 1, loc:=#caller_location) -> (ref:Arena_Reference){
    
    start := get_aligned_arena_start(self) 
    size_full:= size * frames_buffered
    assert(start + size_full <= self.descriptor_arena.size, "Descriptor Arena full, sucks to suck") 
    self.descriptor_arena.bump_offset = start + size_full

    ref.frames_buffered = frames_buffered
    ref.arena_address = self.descriptor_arena.buffer.device_address
    ref.arena_offset = start
    ref.descriptor_size = size

    return ref
}

get_descriptor_offset :: proc(self:^Arena_Reference, frame: vk.DeviceSize) -> vk.DeviceSize {
    if self.frames_buffered > 1 {
        assert(self.frames_buffered > frame)
        return self.arena_offset + (self.descriptor_size * frame)
    }
    return self.arena_offset
}

get_descriptor_size :: proc(self: ^Memory_Manager, descriptor: vk.DescriptorType) ->(vk.DeviceSize) {
    
    #partial switch descriptor {
        case .UNIFORM_BUFFER:
            return vk.DeviceSize(self.physical_device.properties_buffer.uniformBufferDescriptorSize)
        case .STORAGE_BUFFER:
            return vk.DeviceSize(self.physical_device.properties_buffer.storageBufferDescriptorSize)
        case .STORAGE_IMAGE:
            return vk.DeviceSize(self.physical_device.properties_buffer.storageImageDescriptorSize)
        case .SAMPLED_IMAGE:
            return vk.DeviceSize(self.physical_device.properties_buffer.sampledImageDescriptorSize)
    }
    log.errorf("Dont have size info for: %v", descriptor)
    runtime.panic("Shouldn't have made it here, it means we don't have the size for the type")
    // return 0

}
