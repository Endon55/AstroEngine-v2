package astro


import "base:intrinsics"
import "core:mem"
import "core:log"


import vk "vendor:vulkan"
import "libs:vma"

FRAME_UNIFORM_SIZE :: mem.Kilobyte
TEXTURE_BUFFER_CAPACITY :: 1024
BUFFERING_DEPTH:: 3


/*
3 types of data based on how often the CPU has to touch it.

Large Amounts of Data, Set and forget, like textures and vertex data, the cpu doesn't need to modify or touch this data on the gpu ever again.

Medium Amounts of Data that need to be updated every frame.(Particle effects, GUI). Stage it in a cpu ring buffer and have the gpu copy it to its own ring buffer.

Small Amounts of Data that need to be updated frequently. Like uniform data and push constants. , ocean parameters. The cpu directly copies this to the gpu memory.



    Plan - 
    Ill make some kind of large global buffer to store images, and vertex data

*/
Memory_Reference :: struct {
    pointer: rawptr,
    size: vk.DeviceSize,
}

Texture_Reference :: struct {
    image: Allocated_Image,
    index: u32,
}
Ping_Pong_Reference :: struct {
    textures: [2]Texture_Reference,
    read_index: u32,
    write_index: u32,
}

Uniform_Buffer :: struct {

    total_allocation_offset: vk.DeviceSize,
    shadow_buffer_ptr: rawptr,
    ring_buffer_ptr: rawptr,
    frame_ptr: rawptr,
    frame_index: u32,
    ring_buffer: vk.Buffer,
    ring_allocation: vma.Allocation,
    ring_info: vma.AllocationInfo,

    frame_buffer_size: vk.DeviceSize,
    total_buffer_size: vk.DeviceSize,
}

Texture_Heap :: struct {
    size: u32,
    next_index: u32,
    freed_indexes: [dynamic] u32,
    pipeline_layout: vk.PipelineLayout,
    layout_size: vk.DeviceSize,
    layout_binding_offset: vk.DeviceSize,
    layout: vk.DescriptorSetLayout,
    descriptor_size: int,

    buffer: vk.Buffer,
    allocation: vma.Allocation,
    allocation_info: vma.AllocationInfo,
    device_address: vk.DeviceAddress,
    mapped_ptr: rawptr,
}

Memory_Manager :: struct {
    vk_device: vk.Device,
    MIN_UNIFORM_ALIGNMENT: vk.DeviceSize,
    vma_allocator: vma.Allocator,
    device_limits: vk.PhysicalDeviceLimits,
    uniform : Uniform_Buffer,
    texture_heap: Texture_Heap,
}

memory_manager_init :: proc(self:^ Memory_Manager, engine: ^Engine)->(ok:bool) {

    self.vk_device = engine.vk_device
    self.device_limits = engine.vk_context.physical_device.properties.limits
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

    init_uniform_buffers(self, engine) or_return
    init_texture_heap(self, engine) or_return

    return true
}

@(private="file")
init_uniform_buffers:: proc(self:^Memory_Manager, engine: ^Engine) ->(ok:bool,) {


    deletion_queue_push(&engine.main_deletion_queue, self.vma_allocator)
    self.uniform.frame_buffer_size = get_aligned_memory_size(self, FRAME_UNIFORM_SIZE) 
    self.uniform.total_buffer_size = self.uniform.frame_buffer_size * BUFFERING_DEPTH
    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = self.uniform.total_buffer_size,
        usage = {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
    }
    alloc_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
    }

    vk_check(vma.CreateBuffer(self.vma_allocator, buffer_info, alloc_info, &self.uniform.ring_buffer, &self.uniform.ring_allocation, &self.uniform.ring_info), "Failed to create VMA Ring Buffer") or_return
    deletion_queue_push(&engine.main_deletion_queue, Allocated_Buffer {
        buffer = self.uniform.ring_buffer,
        info = self.uniform.ring_info,
        allocation = self.uniform.ring_allocation,
        allocator = self.vma_allocator,
    })
    self.uniform.ring_buffer_ptr = self.uniform.ring_info.pMappedData

    shadow_buffer, err:= mem.alloc(int(self.uniform.frame_buffer_size), int(self.MIN_UNIFORM_ALIGNMENT), context.allocator)
    if err != mem.Allocator_Error.None {
        log.errorf("Failed to allocate shadow buffer.")
        return false
    }
    deletion_queue_push(&engine.main_deletion_queue, Raw_Memory{ptr = shadow_buffer, allocator = context.allocator, size = u32(self.uniform.frame_buffer_size)})
    self.uniform.shadow_buffer_ptr = shadow_buffer
    self.uniform.frame_ptr = self.uniform.ring_buffer_ptr

    return true
}


@(private="file")
init_texture_heap :: proc(self:^Memory_Manager, engine:^Engine) ->(ok:bool,) {

    //Create the Texture storage buffer
    self.texture_heap.size = TEXTURE_BUFFER_CAPACITY
    self.texture_heap.freed_indexes = make([dynamic]u32)
    binding:= vk.DescriptorSetLayoutBinding {
        binding = 0,
        descriptorType = .SAMPLED_IMAGE,
        descriptorCount = self.texture_heap.size,
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

    vk_check(vk.CreateDescriptorSetLayout(
            self.vk_device,
            &layout_info,
            nil,
            &self.texture_heap.layout), "Failed to create Texture[] descriptors") or_return
    deletion_queue_push(&engine.main_deletion_queue, self.texture_heap.layout)

    vk.GetDescriptorSetLayoutSizeEXT(self.vk_device, self.texture_heap.layout, &self.texture_heap.layout_size)
    vk.GetDescriptorSetLayoutBindingOffsetEXT(self.vk_device, self.texture_heap.layout, 0, &self.texture_heap.layout_binding_offset)


    push_constants_range := vk.PushConstantRange{
        stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
        offset = 0,
        size = 128,
    }
    pipeline_layout_info := vk.PipelineLayoutCreateInfo {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &self.texture_heap.layout,
        pushConstantRangeCount = 1, 
        pPushConstantRanges =  &push_constants_range,
    }

    vk_check(vk.CreatePipelineLayout(self.vk_device, &pipeline_layout_info, nil, &self.texture_heap.pipeline_layout), "Failed to create Master Pipeline Layout") or_return
    deletion_queue_push(&engine.main_deletion_queue, self.texture_heap.pipeline_layout)

    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = self.texture_heap.layout_size,
        usage = {.RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS},
    }
    alloc_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
    }


    vk_check(vma.CreateBuffer(self.vma_allocator, buffer_info, alloc_info, &self.texture_heap.buffer, &self.texture_heap.allocation, &self.texture_heap.allocation_info), "Failed to create VMA Texture heap buffer") or_return
    deletion_queue_push(&engine.main_deletion_queue, Allocated_Buffer {
        buffer = self.texture_heap.buffer,
        info = self.texture_heap.allocation_info,
        allocation = self.texture_heap.allocation,
        allocator = self.vma_allocator,
    })

    device_address_info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = self.texture_heap.buffer,
    }
    self.texture_heap.device_address = vk.GetBufferDeviceAddress(self.vk_device, &device_address_info)
    self.texture_heap.mapped_ptr = self.texture_heap.allocation_info.pMappedData
    self.texture_heap.descriptor_size = engine.vk_context.physical_device.properties_buffer.sampledImageDescriptorSize


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

    intrinsics.mem_copy_non_overlapping(self.uniform.shadow_buffer_ptr, self.uniform.frame_ptr, self.uniform.frame_buffer_size) 

    self.uniform.frame_index += 1
    self.uniform.frame_index = self.uniform.frame_index % BUFFERING_DEPTH 

    self.uniform.frame_ptr = ptr_offset(self.uniform.ring_buffer_ptr, self.uniform.frame_buffer_size)


}

memory_manager_bind_uniform :: proc(self: ^Memory_Manager, size: u32) -> (memref:Memory_Reference) {
    
    memref.size = get_aligned_memory_size(self, cast(vk.DeviceSize)size)
    memref.pointer = ptr_offset(self.uniform.shadow_buffer_ptr, self.uniform.total_allocation_offset) 
    self.uniform.total_allocation_offset += memref.size
    assert(memref.pointer != nil, "Bad pointer binding")
    return memref 
}

get_aligned_memory_size :: proc(self: ^Memory_Manager, data_size: vk.DeviceSize) -> vk.DeviceSize{
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


memory_manager_add_texture_to_heap :: proc(self:^ Memory_Manager, image: Allocated_Image) ->(texture_reference: Texture_Reference, ok:bool,) {
 
    if len(self.texture_heap.freed_indexes) > 0 {
        texture_reference.index = pop(&self.texture_heap.freed_indexes)
    } 
    else if self.texture_heap.next_index >= self.texture_heap.size {
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

    dst := ptr_offset(self.texture_heap.mapped_ptr, self.texture_heap.layout_binding_offset + vk.DeviceSize(texture_reference.index) * vk.DeviceSize(self.texture_heap.descriptor_size))
    vk.GetDescriptorEXT(self.vk_device, &get_info, self.texture_heap.descriptor_size, dst)

    if texture_reference.index == self.texture_heap.next_index{
        self.texture_heap.next_index += 1
    }

    return texture_reference, true

}
// create_ping_pong_images :: proc(self:^Memory_Manager,
//     extent: vk.Extent3D,
//     format:vk.Format,
//     usage:vk.ImageUsageFlags,) ->(texture_references: [2]Texture_Reference, ok:bool) {
//
//     texture_references[0] = create_texture(self, extent, format, usage) or_return
//     texture_references[1] = create_texture(self, extent, format, usage) or_retur
//
//      return texture_references, true
// }
//


