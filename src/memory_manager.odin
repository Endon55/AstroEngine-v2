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
SAMPLER_BUFFER_CAPACITY :: 32
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
    image: ^Allocated_Image,
    index: u32,
    gpu_address: vk.DeviceAddress,
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

Heap :: struct {
    max_size: u32,
    next_index: u32,
    freed_indexes: [dynamic] u32,
    layout_binding: vk.DescriptorSetLayoutBinding,
    type: vk.DescriptorType,
    descriptor_size: vk.DeviceSize,
    buffer: Allocated_Buffer_View,
}

Descriptor_Arena:: struct {
    size: vk.DeviceSize,
    bump_offset: vk.DeviceSize,
    alignment: vk.DeviceSize,
    
    bind_info: vk.DescriptorBufferBindingInfoEXT,
    buffer: Allocated_Buffer,
}

Universal_Heap:: struct {
    heaps:[dynamic] Heap,

    set_layout: ^Set_Layout,
    pipeline: Pipeline_Layout2,
    set_buffer: Allocated_Buffer,
    bind_info: vk.DescriptorBufferBindingInfoEXT,
}

Memory_Manager :: struct {
    vk_device: vk.Device,
    MIN_UNIFORM_ALIGNMENT: vk.DeviceSize,
    vma_allocator: vma.Allocator,
    device_limits: vk.PhysicalDeviceLimits,
    physical_device: ^Physical_Device,
    uniform : Uniform_Buffer,
    texture_heap: Heap,
    sampler_heap: Heap,
    universal_heap: Universal_Heap,
    descriptor_arena: Descriptor_Arena,
    frames_buffered: vk.DeviceSize,
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
    self.universal_heap.heaps = make([dynamic]Heap) 

    add_heap(self, .SAMPLED_IMAGE, TEXTURE_BUFFER_CAPACITY) or_return
    add_heap(self, .SAMPLER, SAMPLER_BUFFER_CAPACITY) or_return
    init_descriptor_arena(self, engine) or_return
    init_uniform_buffers(self, engine) or_return
    init_universal_set(self, engine) or_return
    return true
}


@(private="file")
init_universal_set :: proc(self:^ Memory_Manager, engine:^Engine) ->(ok:bool,) {
    universal := &self.universal_heap
    binding_count: u32 = u32(len(self.universal_heap.heaps))

    binding_flags := vk.DescriptorBindingFlags {
        .PARTIALLY_BOUND,
    }

    layout_binding_flags_info := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        bindingCount = binding_count,
        pBindingFlags = &binding_flags,
    }
    bindings:[]vk.DescriptorSetLayoutBinding = make([]vk.DescriptorSetLayoutBinding, binding_count)
    defer delete(bindings)

    for i in 0..<binding_count{
        bindings[i] = self.universal_heap.heaps[i].layout_binding
    }

    layout_info := vk.DescriptorSetLayoutCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        pNext = &layout_binding_flags_info,
        flags = {.DESCRIPTOR_BUFFER_EXT,},
        bindingCount = binding_count,
        pBindings = raw_data(bindings),
    }
    universal.pipeline.set_layouts = make([]Set_Layout, 1)
    vk_check(vk.CreateDescriptorSetLayout(
            self.vk_device,
            &layout_info,   
            nil,
            &universal.pipeline.set_layouts[0].vk_layout), "Failed to create Universal texture[] sampler[] descriptors") or_return
    deletion_queue_push(&engine.main_deletion_queue, Raw_Memory{ptr = raw_data(universal.pipeline.set_layouts), allocator = context.allocator})

    set := &universal.pipeline.set_layouts[0] 
    universal.set_layout = &universal.pipeline.set_layouts[0]

    vk.GetDescriptorSetLayoutSizeEXT(self.vk_device, set.vk_layout, &set.total_set_size)
    set.binding_layouts = make([]Binding_Layout, binding_count)

    deletion_queue_push(&engine.main_deletion_queue,
        Raw_Memory{ptr = raw_data(set.binding_layouts), allocator = context.allocator})

    for i in 0..<binding_count {
        vk.GetDescriptorSetLayoutBindingOffsetEXT(
            self.vk_device,
            set.vk_layout, i, &set.binding_layouts[i].offset)  
        set.binding_layouts[i].vk_layout = bindings[i] 
        set.binding_layouts[i].type = bindings[i].descriptorType 
        set.binding_layouts[i].binding_size = get_descriptor_size(bindings[i].descriptorType) 
    }
    push_constants_range := vk.PushConstantRange{
        stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
        offset = 0,
        size = 128,
    }
    pipeline_layout_info := vk.PipelineLayoutCreateInfo {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &set.vk_layout,
        pushConstantRangeCount = 1, 
        pPushConstantRanges =  &push_constants_range,
    }

    vk_check(vk.CreatePipelineLayout(self.vk_device, &pipeline_layout_info, nil, &universal.pipeline.vk_layout), "Failed to create Master Pipeline Layout") or_return
    deletion_queue_push(&engine.main_deletion_queue, universal.pipeline.vk_layout)

    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = set.total_set_size,
        usage = {.RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS},
    }
    alloc_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
    }

    buffer:= &universal.set_buffer
    vk_check(vma.CreateBuffer(self.vma_allocator, buffer_info, alloc_info, &buffer.buffer, &buffer.allocation, &buffer.info), "Failed to create VMA Texture heap buffer") or_return

    device_address_info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.buffer,
    }
    buffer.gpu_address = vk.GetBufferDeviceAddress(self.vk_device, &device_address_info)
    buffer.cpu_write_ptr = buffer.info.pMappedData
    buffer.allocator = self.vma_allocator
    universal.bind_info = vk.DescriptorBufferBindingInfoEXT {
        sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
        address = buffer.gpu_address,
        usage = {
            .RESOURCE_DESCRIPTOR_BUFFER_EXT,
        }
    }
    buffer.size = set.total_set_size

    for i in 0..< binding_count {
        offset := set.binding_layouts[i].offset
        universal.heaps[i].buffer = {
            parent_buffer = buffer,
            
            size = vk.DeviceSize(universal.heaps[i].max_size) * universal.heaps[i].descriptor_size,
            cpu_write_ptr = ptr_offset(buffer.cpu_write_ptr, offset),
            gpu_address = ptr_offset(buffer.gpu_address, offset),
        }
    }

    deletion_queue_push(&engine.main_deletion_queue, set.vk_layout)
    deletion_queue_push(&engine.main_deletion_queue, buffer^)

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

    buffer.cpu_write_ptr = buffer.info.pMappedData

    shadow_buffer, err:= mem.alloc(int(self.uniform.frame_buffer_size), int(self.MIN_UNIFORM_ALIGNMENT), context.allocator)
    if err != mem.Allocator_Error.None {
        log.errorf("Failed to allocate shadow buffer.")
        return false
    }
    self.uniform.shadow_buffer_ptr = shadow_buffer
    self.uniform.frame_ptr = buffer.cpu_write_ptr

    buffer.allocator = self.vma_allocator
    buffer.size = self.uniform.total_buffer_size

    address_info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.buffer,
    }
    buffer.gpu_address = vk.GetBufferDeviceAddress(self.vk_device, &address_info)

    deletion_queue_push(&engine.main_deletion_queue, Raw_Memory{ptr = shadow_buffer, allocator = context.allocator, size = u32(self.uniform.frame_buffer_size)})
    deletion_queue_push(&engine.main_deletion_queue, buffer^)    
    return true
}

@(private="file")
add_heap:: proc(self:^Memory_Manager, type: vk.DescriptorType, heap_size: u32,) ->(ok:bool,) {
     
    append(&self.universal_heap.heaps, Heap{})
    index := len(self.universal_heap.heaps) - 1
    heap := &self.universal_heap.heaps[index]

    heap.max_size = heap_size
    heap.type = type
    heap.layout_binding = vk.DescriptorSetLayoutBinding {
        binding = u32(index),
        descriptorType = type,
        descriptorCount = heap_size,
        stageFlags = {.COMPUTE, .VERTEX, .FRAGMENT},
        pImmutableSamplers = nil,
    }

    heap.freed_indexes = make([dynamic]u32)
    heap.descriptor_size = get_descriptor_size(type)
    return true
}

heap_get_cpu_ptr :: proc(heap:^Heap, index: u32) -> rawptr {
    return ptr_offset(heap.buffer.cpu_write_ptr, vk.DeviceSize(index) * heap.descriptor_size)
}
heap_get_gpu_ptr :: proc(heap:^Heap, index: u32) -> vk.DeviceAddress {
    return ptr_offset(heap.buffer.gpu_address, vk.DeviceSize(index) * heap.descriptor_size)
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
    buffer.gpu_address = vk.GetBufferDeviceAddress(self.vk_device, &address_info)
    buffer.cpu_write_ptr = buffer.info.pMappedData
    buffer.allocator = self.vma_allocator

    self.descriptor_arena.bind_info = vk.DescriptorBufferBindingInfoEXT {
        sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
        address = buffer.gpu_address,
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

    self.uniform.frame_ptr = ptr_offset(self.uniform.ring_buffer.cpu_write_ptr, self.uniform.frame_buffer_size * vk.DeviceSize(self.write_frame))


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
get_aligned_arena_start :: proc() -> vk.DeviceSize {
    return (GLOBALS.memory_manager.descriptor_arena.bump_offset + GLOBALS.memory_manager.descriptor_arena.alignment - 1) & ~(GLOBALS.memory_manager.descriptor_arena.alignment - 1)
}

ptr_offset :: proc {
    ptr_offset_vk,
    ptr_offset_raw,
    ptr_offset_address,
}
ptr_offset_address :: proc(ptr:vk.DeviceAddress, offset:vk.DeviceSize) -> vk.DeviceAddress{
    return vk.DeviceAddress(uintptr(ptr) + uintptr(offset))
}
ptr_offset_vk :: proc(ptr:rawptr, offset:vk.DeviceSize) -> rawptr {
    return rawptr(uintptr(ptr) + uintptr(offset))
}

ptr_offset_raw :: proc(ptr:rawptr, offset:uint) -> rawptr {
    return rawptr(uintptr(ptr) + uintptr(offset))
}

memory_manager_register_texture :: proc(image: ^Allocated_Image) ->(texture_reference: Texture_Reference, ok:bool,) {
    memory_manager:= GLOBALS.memory_manager
    heap := &memory_manager.universal_heap.heaps[0] 
    universal := &memory_manager.universal_heap
    if len(heap.freed_indexes) > 0 {
        texture_reference.index = pop(&heap.freed_indexes)
    } 
    else if heap.next_index >= heap.max_size {
        log.errorf("No more room in heap")
        return texture_reference, false
    }
    else {
        texture_reference.index = heap.next_index
    }
    texture_reference.image = image
    descriptor_image_info := vk.DescriptorImageInfo {
        imageView = texture_reference.image.image_view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    } 
    get_info := vk.DescriptorGetInfoEXT {
        sType = .DESCRIPTOR_GET_INFO_EXT,
        type = heap.type,
        data = {pSampledImage = &descriptor_image_info},
    }
    texture_reference.gpu_address = heap_get_gpu_ptr(heap, texture_reference.index)
    dst := heap_get_cpu_ptr(heap, texture_reference.index)

    vk.GetDescriptorEXT(GLOBALS.vk_device, &get_info, int(heap.descriptor_size), dst)

    if texture_reference.index == heap.next_index{
        heap.next_index += 1
    }

    return texture_reference, true
}

memory_manager_register_descriptor :: proc(size:vk.DeviceSize, frames_buffered: vk.DeviceSize = 1, loc:=#caller_location) -> (ref:Arena_Reference){
    
    start := get_aligned_arena_start() 
    size_full:= size * frames_buffered
    assert(start + size_full <= GLOBALS.memory_manager.descriptor_arena.size, "Descriptor Arena full, sucks to suck") 
    GLOBALS.memory_manager.descriptor_arena.bump_offset = start + size_full

    ref.frames_buffered = frames_buffered
    ref.arena_address = GLOBALS.memory_manager.descriptor_arena.buffer.gpu_address
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

get_descriptor_size :: proc(descriptor: vk.DescriptorType) ->(vk.DeviceSize) {
    
    #partial switch descriptor {
        case .UNIFORM_BUFFER:
            return vk.DeviceSize(GLOBALS.vk_context.physical_device.properties_buffer.uniformBufferDescriptorSize)
        case .STORAGE_BUFFER:
            return vk.DeviceSize(GLOBALS.vk_context.physical_device.properties_buffer.storageBufferDescriptorSize)
        case .STORAGE_IMAGE:
            return vk.DeviceSize(GLOBALS.vk_context.physical_device.properties_buffer.storageImageDescriptorSize)
        case .SAMPLED_IMAGE:
            return vk.DeviceSize(GLOBALS.vk_context.physical_device.properties_buffer.sampledImageDescriptorSize)
        case .SAMPLER:
            return vk.DeviceSize(GLOBALS.vk_context.physical_device.properties_buffer.samplerDescriptorSize)
    }
    log.errorf("Dont have size info for: %v", descriptor)
    runtime.panic("Shouldn't have made it here, it means we don't have the size for the type")
    // return 0

}

memory_manager_deinit :: proc(self: ^ Memory_Manager) {
    for heap in self.universal_heap.heaps {
        delete(heap.freed_indexes)
    }
    delete(self.universal_heap.heaps)
}
