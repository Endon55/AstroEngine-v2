package astro

import intr "base:intrinsics"
import "base:runtime"
import "core:log"
import la "core:math/linalg"

import vma "libs:odin-vma"
import vk "vendor:vulkan"

Allocated_Image :: struct {
    device: vk.Device,
    image: vk.Image,
    image_view: vk.ImageView,
    image_extent: vk.Extent3D,
    image_format: vk.Format,
    allocator: vma.Allocator,
    allocation: vma.Allocation,
}
Allocated_Buffer :: struct {
    buffer: vk.Buffer,
    info: vma.AllocationInfo,
    allocation: vma.Allocation,
    allocator: vma.Allocator,
}

Vertex :: struct {
    position: la.Vector3f32,
    uv_x: f32,
    normal: la.Vector3f32,
    uv_y: f32,
    color: la.Vector4f32,
}

GPU_Mesh_Buffers :: struct {
    index_buffer: Allocated_Buffer,
    vertex_buffer: Allocated_Buffer,
    vertex_buffer_address: vk.DeviceAddress,
}

GPU_Draw_Push_Constants :: struct {
    world_matrix: la.Matrix4f32,
    vertex_buffer: vk.DeviceAddress,
}

upload_mesh :: proc(self: ^Engine, indices: []u32, vertices: []Vertex,) -> (
    new_surface: GPU_Mesh_Buffers, ok:bool,) {

    //We have to allocate memory on the gpu to hold the data
    //vk.DeviceSize is just a type of uint64_t, we're just casting our size type to the strict gpu type.
    vertex_buffer_size := vk.DeviceSize(len(vertices) * size_of(Vertex))
    index_buffer_size := vk.DeviceSize(len(indices) * size_of(u32))
    
    //Data is GPU only, which means we can't send it to the gpu the easy way.
    new_surface.vertex_buffer = create_buffer(self, vertex_buffer_size, {.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS}, .GPU_ONLY) or_return
    defer if !ok {
        destroy_buffer(new_surface.vertex_buffer)
    }

    device_address_info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = new_surface.vertex_buffer.buffer,
    }
    new_surface.vertex_buffer_address = vk.GetBufferDeviceAddress(self.vk_device, &device_address_info)
    
    new_surface.index_buffer = create_buffer(self, index_buffer_size, {.INDEX_BUFFER, .TRANSFER_DST}, .GPU_ONLY,) or_return
    defer if !ok {
        destroy_buffer(new_surface.index_buffer)
    }

    //Now we send the data the hard way.
    staging := create_buffer(self, vertex_buffer_size + index_buffer_size, {.TRANSFER_SRC}, .CPU_ONLY,) or_return
    defer destroy_buffer(staging)

    data := staging.info.pMappedData
    intr.mem_copy(data, raw_data(vertices), vertex_buffer_size)
    intr.mem_copy(rawptr(uintptr(data) + uintptr(vertex_buffer_size)), raw_data(indices), index_buffer_size)

    Copy_Data :: struct {
        staging_buffer: vk.Buffer,
        vertex_buffer: vk.Buffer,
        index_buffer: vk.Buffer,
        vertex_buffer_size: vk.DeviceSize,
        index_buffer_size: vk.DeviceSize,
    }

    copy_data := Copy_Data {
        staging_buffer = staging.buffer,
        vertex_buffer = new_surface.vertex_buffer.buffer,
        index_buffer = new_surface.index_buffer.buffer,
        vertex_buffer_size = vertex_buffer_size,
        index_buffer_size = index_buffer_size,
    }

    engine_immediate_submit(self, copy_data, proc(engine: ^Engine, cmd: vk.CommandBuffer, data: Copy_Data) {
        vertex_copy := vk.BufferCopy {
            srcOffset = 0,
            dstOffset = 0,
            size = data.vertex_buffer_size,
        }
        vk.CmdCopyBuffer(cmd, data.staging_buffer, data.vertex_buffer, 1, &vertex_copy)

        index_copy := vk.BufferCopy {
            srcOffset = data.vertex_buffer_size,
            dstOffset = 0,
            size = data.index_buffer_size,
        }
        vk.CmdCopyBuffer(cmd, data.staging_buffer, data.index_buffer, 1, &index_copy)
    })

    return new_surface, true
}

destroy_image :: proc(self: Allocated_Image) {
    vk.DestroyImageView(self.device, self.image_view, nil)
    vma.DestroyImage(self.allocator, self.image, self.allocation)
}

 @(require_results)
 vk_check::#force_inline proc(
     res: vk.Result,
     message:= "Detected Vulkan error",
     loc:= #caller_location) -> bool {
         if intr.expect(res, vk.Result.SUCCESS) == .SUCCESS {
             return true
         }

         log.errorf("[Vulkan Error] %s: %v", message, res)
         runtime.print_caller_location(loc)
         return false
}
 
create_buffer :: proc(self: ^Engine, alloc_size: vk.DeviceSize, usage: vk.BufferUsageFlags, memory_usage: vma.MemoryUsage,) -> (new_buffer: Allocated_Buffer, ok: bool,) {
    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = alloc_size,
        usage = usage,
    }

    vma_alloc_info := vma.AllocationCreateInfo {
        usage = memory_usage,
        flags = {.MAPPED},
    }
    new_buffer.allocator = self.vma_allocator

    vk_check(vma.CreateBuffer(self.vma_allocator, buffer_info, vma_alloc_info, &new_buffer.buffer, &new_buffer.allocation, &new_buffer.info),) or_return

    return new_buffer, true
}

destroy_buffer :: proc(self: Allocated_Buffer) {
    vma.DestroyBuffer(self.allocator, self.buffer, self.allocation)
}
