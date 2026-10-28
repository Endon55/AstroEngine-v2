package astro


import "core:mem"
import "core:log"
import vk "vendor:vulkan"
import "base:runtime"

import vma "libs:vma"

//just defining a layout for a function pointer, Resource_Proc is a function pointer for a function that takes no arguments and has no return values.
Raw_Memory :: struct {
    allocator: runtime.Allocator,
    ptr:rawptr,
    size: u32,
}

Resource_Proc :: #type proc();

Resource :: union {
    Resource_Proc,

    vk.Pipeline,
    vk.PipelineLayout,

    vk.DescriptorPool,
    vk.DescriptorSetLayout,
    Descriptor_Layout,
    Pipeline_Layout,

    vk.ImageView,
    vk.Sampler,

    vk.CommandPool,

    vk.Fence,
    vk.Semaphore,

    vk.Buffer,
    vk.DeviceMemory,
    vk.ShaderModule,

    vma.Allocator,
    Allocated_Image,
    Allocated_Buffer,
    Shader_Pipeline,
    Engine_Samplers,

    ^Heap,

    Metallic_Roughness,
    Material_Shader,
    Raw_Memory,

}
Resource_Loc :: struct {
    resource: Resource,
    allocator: runtime.Allocator,
    loc: runtime.Source_Code_Location,

} 
Deletion_Queue :: struct {
    device: vk.Device,
    resources: [dynamic]Resource_Loc,
    allocator: mem.Allocator,
}

deletion_queue_init :: proc(self:^Deletion_Queue, device: vk.Device, allocator := context.allocator,){
    assert(self != nil, "Invalid 'Deletion_Queue'")
    assert(device != nil, "Invalid 'Device'")

    self.allocator = allocator
    self.device = device
    self.resources = make([dynamic]Resource_Loc, self.allocator)
}

deletion_queue_destroy :: proc(self: ^Deletion_Queue) {
    assert(self != nil)
    context.allocator = self.allocator

    deletion_queue_flush(self, false)

    delete(self.resources)
}

deletion_queue_push :: proc(self: ^Deletion_Queue, resource: Resource, loc:= #caller_location) {
    append(&self.resources, Resource_Loc{resource, context.allocator, loc})
}
@(private="file")
delete_resource ::proc(device:vk.Device, resource:^Resource_Loc) {

    switch &res in resource.resource{

    case Resource_Proc:
        res()

    case vk.Pipeline:
        vk.DestroyPipeline(device, res, nil)
    case vk.PipelineLayout:
        vk.DestroyPipelineLayout(device, res, nil)

    case vk.DescriptorPool:
        vk.DestroyDescriptorPool(device, res, nil)
    case vk.DescriptorSetLayout:
        vk.DestroyDescriptorSetLayout(device, res, nil)

    case vk.ImageView:
        vk.DestroyImageView(device, res, nil)
    case vk.Sampler:
        vk.DestroySampler(device, res, nil)

    case vk.CommandPool:
        vk.DestroyCommandPool(device, res, nil) 
    case vk.Fence:
        vk.DestroyFence(device, res, nil)
    case vk.Semaphore:
        vk.DestroySemaphore(device, res, nil)

    case vk.Buffer:
        vk.DestroyBuffer(device, res, nil)
    case vk.DeviceMemory:
        vk.FreeMemory(device, res, nil)
    case vk.ShaderModule:
        vk.DestroyShaderModule(device, res, nil)
    case Allocated_Image:
        destroy_image(res)
    case Allocated_Buffer:
        destroy_buffer(res)
    case vma.Allocator:
        vma.DestroyAllocator(res)
    case Descriptor_Layout:
        descriptor_layout_destroy(res)
    case Pipeline_Layout:
        pipeline_layout_destroy(res)
    case Metallic_Roughness:
        metallic_roughness_clear_resources(res)
    case Material_Shader:
        material_shader_clear_resources(res)
    case Raw_Memory:
        free(res.ptr, res.allocator)
    case Shader_Pipeline:
        shader_pipeline_destroy(&res)
    case Engine_Samplers:
        samplers_deinit(&res)
    case ^Heap:
        delete(res.freed_indexes)
    }


}

// Destroys and removes every entry that was pushed while `allocator` was the context allocator.
// Call it before that allocator goes away, with the GPU idle.
deletion_queue_flush_by_allocator :: proc(self:^Deletion_Queue, allocator: runtime.Allocator, log_lines: bool = false) {
    assert(self != nil)
    if len(self.resources) == 0 {
        return
    }

    if self.device != nil {
        vk.DeviceWaitIdle(self.device)
    }

    current_allocator := context.allocator
    defer context.allocator = current_allocator

    #reverse for &resource_loc, i in self.resources {
        if resource_loc.allocator != allocator {
            continue
        }
        if log_lines {
            log.debugf("Destroying resource from: %v", resource_loc.loc)
        }
        context.allocator = resource_loc.allocator
        delete_resource(self.device, &resource_loc)
        ordered_remove(&self.resources, i)
    }
}

deletion_queue_flush :: proc(self: ^Deletion_Queue, log_lines:bool = false) {
    assert(self != nil)
    if len(self.resources) == 0 {
        return
    }
    current_allocator := context.allocator
    defer context.allocator = current_allocator

    #reverse for &resource_loc in self.resources {
        if log_lines {
            log.debugf("Destroying resource from: %v", resource_loc.loc)
        }
        context.allocator = resource_loc.allocator
        delete_resource(self.device, &resource_loc)
    }
    clear(&self.resources)
}
