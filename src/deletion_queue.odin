package astro


import "core:mem"
import "core:log"
import vk "vendor:vulkan"
import "base:runtime"

import vma "libs:vma"

//just defining a layout for a function pointer, Resource_Proc is a function pointer for a function that takes no arguments and has no return values.
Resource_Proc :: #type proc()

Resource :: union {
    Resource_Proc,

    vk.Pipeline,
    vk.PipelineLayout,

    vk.DescriptorPool,
    vk.DescriptorSetLayout,

    vk.ImageView,
    vk.Sampler,

    vk.CommandPool,

    vk.Fence,
    vk.Semaphore,

    vk.Buffer,
    vk.DeviceMemory,

    vma.Allocator,
    Allocated_Image,
    Allocated_Buffer,

    Descriptor_Allocator_Growable,
    Metallic_Roughness,
    Material_Shader,

    }
    Resource_Loc :: struct {
        resource: Resource,
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
        append(&self.resources, Resource_Loc{resource, loc})
    }

    deletion_queue_flush :: proc(self: ^Deletion_Queue, log_lines:bool = false) {
        assert(self != nil)
        if len(self.resources) == 0 {
            return
        }

        #reverse for &resource_loc in self.resources {
            if log_lines {
                log.debugf("Destroying resource from: %v", resource_loc.loc)
            }
            switch &res in resource_loc.resource{
            case Resource_Proc:
                res()

            case vk.Pipeline:
                vk.DestroyPipeline(self.device, res, nil)
            case vk.PipelineLayout:
                vk.DestroyPipelineLayout(self.device, res, nil)

            case vk.DescriptorPool:
                vk.DestroyDescriptorPool(self.device, res, nil)
            case vk.DescriptorSetLayout:
                vk.DestroyDescriptorSetLayout(self.device, res, nil)

            case vk.ImageView:
                vk.DestroyImageView(self.device, res, nil)
            case vk.Sampler:
                vk.DestroySampler(self.device, res, nil)

            case vk.CommandPool:
                vk.DestroyCommandPool(self.device, res, nil) 
            case vk.Fence:
                vk.DestroyFence(self.device, res, nil)
            case vk.Semaphore:
                vk.DestroySemaphore(self.device, res, nil)

            case vk.Buffer:
                vk.DestroyBuffer(self.device, res, nil)
            case vk.DeviceMemory:
                vk.FreeMemory(self.device, res, nil)

            case Allocated_Image:
                destroy_image(res)
            case Allocated_Buffer:
                destroy_buffer(res)
            case vma.Allocator:
                vma.DestroyAllocator(res)
            case Descriptor_Allocator_Growable:
                descriptor_growable_destroy_pools(res)
            case Metallic_Roughness:
                metallic_roughness_clear_resources(res)
            case Material_Shader:
                material_shader_clear_resources(res)
            }
       }

        clear(&self.resources)
    }
