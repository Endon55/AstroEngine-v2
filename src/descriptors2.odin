package astro

import "base:runtime"
import "core:log"
import vk "vendor:vulkan"

MAX_POOLS :: #config(MAX_POOLS, 32)

Ratios :: [dynamic; MAX_POOL_SIZES]Pool_Size_Ratio
Full_Pools :: [dynamic; MAX_POOLS]vk.DescriptorPool
Ready_Pools :: [dynamic; MAX_POOLS]vk.DescriptorPool

// Grows by adding pools. Pool sizes are derived from the layouts it has been asked to allocate,
// so a new layout never needs a hand written ratio table.
Descriptor_Allocator :: struct {
    device: vk.Device,
    ratios: Ratios,
    full_pools: Full_Pools,
    ready_pools: Ready_Pools,
    sets_per_pool: u32,
}

descriptor_allocator_init :: proc(
    self: ^Descriptor_Allocator,
    device: vk.Device,
    max_sets: u32,
    layouts: []^Descriptor_Layout = nil,
) {
    self.device = device
    self.sets_per_pool = max_sets
    clear(&self.ratios)
    clear(&self.full_pools)
    clear(&self.ready_pools)

    for layout in layouts {
        descriptor_ratios_track_layout(&self.ratios, layout)
    }
}

descriptor_allocator_allocate :: proc(
    self: ^Descriptor_Allocator,
    layout: ^Descriptor_Layout,
    pNext: rawptr = nil,
    loc := #caller_location,
) -> (ds: vk.DescriptorSet, ok: bool) {
    assert(layout != nil && layout.handle != 0, "Allocating from a descriptor layout that was never built", loc)

    if descriptor_ratios_track_layout(&self.ratios, layout) {
        // Existing pools were sized without this layout, stop handing them out.
        for pool in self.ready_pools {
            append(&self.full_pools, pool)
        }
        clear(&self.ready_pools)
    }

    set_layout := layout.handle
    for _ in 0 ..= MAX_POOLS {
        pool, fresh := descriptor_allocator_get_pool(self) or_return

        alloc_info := vk.DescriptorSetAllocateInfo {
            sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
            pNext = pNext,
            descriptorPool = pool,
            descriptorSetCount = 1,
            pSetLayouts = &set_layout,
        }

        result := vk.AllocateDescriptorSets(self.device, &alloc_info, &ds)
        if result == .SUCCESS {
            append(&self.ready_pools, pool)
            return ds, true
        }

        append(&self.full_pools, pool)
        if fresh || (result != .ERROR_OUT_OF_POOL_MEMORY && result != .ERROR_FRAGMENTED_POOL) {
            _ = vk_check(result, "Failed to allocate descriptor set")
            return {}, false
        }
    }

    log.errorf("Descriptor allocator ran out of pools while allocating layout '%v'", layout.name)
    return {}, false
}

descriptor_allocator_get_pool :: proc(self: ^Descriptor_Allocator) -> (pool: vk.DescriptorPool, fresh: bool, ok: bool) {
    if len(self.ready_pools) > 0 {
        return pop(&self.ready_pools), false, true
    }

    if len(self.full_pools) + len(self.ready_pools) >= MAX_POOLS {
        log.errorf("Descriptor allocator hit MAX_POOLS (%v)", MAX_POOLS)
        return {}, false, false
    }

    pool = descriptor_allocator_create_pool(self, self.sets_per_pool) or_return
    self.sets_per_pool = min(u32(f32(self.sets_per_pool) * 1.5), 4092)
    return pool, true, true
}

descriptor_allocator_create_pool :: proc(self: ^Descriptor_Allocator, set_count: u32) -> (pool: vk.DescriptorPool, ok: bool) {
    assert(len(self.ratios) > 0, "Descriptor allocator has no layouts to size a pool from")

    pool_sizes: [MAX_POOL_SIZES]vk.DescriptorPoolSize
    for ratio, i in self.ratios {
        pool_sizes[i] = vk.DescriptorPoolSize {
            type = ratio.type,
            descriptorCount = u32(ratio.ratio) * set_count,
        }
    }

    pool_info := vk.DescriptorPoolCreateInfo {
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets = set_count,
        poolSizeCount = u32(len(self.ratios)),
        pPoolSizes = &pool_sizes[0],
    }

    vk_check(vk.CreateDescriptorPool(self.device, &pool_info, nil, &pool), "Failed to create descriptor pool") or_return
    return pool, true
}

// Frees every set handed out so far, pools are kept for reuse.
descriptor_allocator_clear :: proc(self: ^Descriptor_Allocator) -> (ok: bool) {
    for pool in self.ready_pools {
        vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
    }

    for pool in self.full_pools {
        vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
        append(&self.ready_pools, pool)
    }
    clear(&self.full_pools)

    return true
}

descriptor_allocator_destroy :: proc(self: ^Descriptor_Allocator) {
    for pool in self.ready_pools {
        vk.DestroyDescriptorPool(self.device, pool, nil)
    }
    for pool in self.full_pools {
        vk.DestroyDescriptorPool(self.device, pool, nil)
    }
    clear(&self.ready_pools)
    clear(&self.full_pools)
}


/* ************************************************

                Descriptor Writer

  ************************************************* */

MAX_IMAGE_INFOS :: #config(MAX_IMAGE_INFOS, 64)
MAX_BUFFER_INFOS :: #config(MAX_BUFFER_INFOS, 64)
MAX_WRITES :: #config(MAX_WRITES, 128)

Image_Infos :: [dynamic; MAX_IMAGE_INFOS] vk.DescriptorImageInfo
Buffer_Infos :: [dynamic; MAX_BUFFER_INFOS] vk.DescriptorBufferInfo
Writes :: [dynamic; MAX_WRITES] vk.WriteDescriptorSet

// Writes resources by binding number. The descriptor type comes from the layout, so a write only
// names the binding and the resource, and a binding that doesn't exist or has the wrong kind fails loudly.
// The writer holds pointers into itself, don't copy it between a write and update_set.
Descriptor_Writer :: struct {
    device: vk.Device,
    layout: ^Descriptor_Layout,
    image_infos: Image_Infos,
    buffer_infos: Buffer_Infos,
    writes: Writes,
}

descriptor_writer_init :: proc(self: ^Descriptor_Writer, device: vk.Device, layout: ^Descriptor_Layout) {
    assert(layout != nil, "Descriptor writer needs a layout")
    self.device = device
    self.layout = layout
    descriptor_writer_clear(self)
}

descriptor_writer_write_buffer :: proc(
    self: ^Descriptor_Writer,
    binding: u32,
    buffer: vk.Buffer,
    size: vk.DeviceSize,
    offset: vk.DeviceSize = 0,
    loc := #caller_location,
) -> bool {
    info := descriptor_writer_find_binding(self, binding, loc) or_return
    #partial switch info.type {
    case .UNIFORM_BUFFER, .STORAGE_BUFFER, .UNIFORM_BUFFER_DYNAMIC, .STORAGE_BUFFER_DYNAMIC:
    case:
        log.errorf("Descriptor layout '%v' binding %v is %v, can't write a buffer to it (%v)", self.layout.name, binding, info.type, loc)
        return false
    }
    if len(self.buffer_infos) == cap(self.buffer_infos) || len(self.writes) == cap(self.writes) {
        log.errorf("Descriptor writer is full (%v)", loc)
        return false
    }

    append(&self.buffer_infos, vk.DescriptorBufferInfo {
        buffer = buffer,
        offset = offset,
        range = size,
    })

    append(&self.writes, vk.WriteDescriptorSet {
        sType = .WRITE_DESCRIPTOR_SET,
        dstBinding = binding,
        descriptorCount = 1,
        descriptorType = info.type,
        pBufferInfo = &self.buffer_infos[len(self.buffer_infos) - 1],
    })
    return true
}

// `image_layout` defaults to GENERAL for storage images and SHADER_READ_ONLY_OPTIMAL for everything else.
descriptor_writer_write_image :: proc(
    self: ^Descriptor_Writer,
    binding: u32,
    image: vk.ImageView,
    sampler: vk.Sampler = 0,
    image_layout: vk.ImageLayout = .UNDEFINED,
    loc := #caller_location,
) -> bool {
    info := descriptor_writer_find_binding(self, binding, loc) or_return
    layout := image_layout
    #partial switch info.type {
    case .STORAGE_IMAGE:
        if layout == .UNDEFINED { layout = .GENERAL }
    case .COMBINED_IMAGE_SAMPLER, .SAMPLED_IMAGE, .SAMPLER, .INPUT_ATTACHMENT:
        if layout == .UNDEFINED { layout = .SHADER_READ_ONLY_OPTIMAL }
    case:
        log.errorf("Descriptor layout '%v' binding %v is %v, can't write an image to it (%v)", self.layout.name, binding, info.type, loc)
        return false
    }
    if len(self.image_infos) == cap(self.image_infos) || len(self.writes) == cap(self.writes) {
        log.errorf("Descriptor writer is full (%v)", loc)
        return false
    }

    append(&self.image_infos, vk.DescriptorImageInfo {
        sampler = sampler,
        imageView = image,
        imageLayout = layout,
    })

    append(&self.writes, vk.WriteDescriptorSet {
        sType = .WRITE_DESCRIPTOR_SET,
        dstBinding = binding,
        descriptorCount = 1,
        descriptorType = info.type,
        pImageInfo = &self.image_infos[len(self.image_infos) - 1],
    })
    return true
}

@(private = "file")
descriptor_writer_find_binding :: proc(self: ^Descriptor_Writer, binding: u32, loc: runtime.Source_Code_Location) -> (info: ^Binding_Info, ok: bool) {
    assert(self.layout != nil, "Descriptor writer used before descriptor_writer_init", loc)
    info, ok = descriptor_layout_find(self.layout, binding)
    if !ok {
        log.errorf("Descriptor layout '%v' has no binding %v (%v)", self.layout.name, binding, loc)
    }
    return
}

descriptor_writer_clear :: proc(self: ^Descriptor_Writer,) {
    clear(&self.image_infos)
    clear(&self.buffer_infos)
    clear(&self.writes)
}

descriptor_writer_update_set :: proc(self: ^Descriptor_Writer, set: vk.DescriptorSet, loc:= #caller_location) {
    assert(self.device != nil, "Invalid 'Device'", loc)

    for &write in self.writes {
        write.dstSet = set
    }

    if len(self.writes) > 0 {
        vk.UpdateDescriptorSets(self.device, u32(len(self.writes)), raw_data(self.writes[:]), 0, nil)
    }

}
