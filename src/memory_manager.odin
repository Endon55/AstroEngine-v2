package astro


import "base:intrinsics"
import "core:mem"
import "core:log"


import vk "vendor:vulkan"
import "libs:vma"

FRAME_UNIFORM_SIZE :: mem.Kilobyte 
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

Memory_Manager :: struct {

    MIN_UNIFORM_ALIGNMENT: vk.DeviceSize,
    vma_allocator: vma.Allocator,
    device_limits: vk.PhysicalDeviceLimits,
    uniform : Uniform_Buffer,
}



memory_manager_init :: proc(self:^ Memory_Manager, engine: ^Engine)->(ok:bool) {

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
    deletion_queue_push(&engine.main_deletion_queue, engine.vma_allocator)
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


    self.uniform.ring_buffer_ptr = self.uniform.ring_info.pMappedData

    shadow_buffer, err:= mem.alloc(int(self.uniform.frame_buffer_size), int(self.MIN_UNIFORM_ALIGNMENT), context.allocator)
    if err != mem.Allocator_Error.None {
        log.errorf("Failed to allocate shadow buffer.")
        return false
    }
    self.uniform.shadow_buffer_ptr = shadow_buffer
    self.uniform.frame_ptr = self.uniform.ring_buffer_ptr
    return true
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

