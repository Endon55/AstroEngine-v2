package astro

import "core:log"
import vk "vendor:vulkan"

MAX_LAYOUT_BINDINGS :: #config(MAX_LAYOUT_BINDINGS, 16)
MAX_POOL_SIZES :: #config(MAX_POOL_SIZES, 12)

Pool_Size_Ratio :: struct {
    type: vk.DescriptorType,
    ratio: f32,
}

Binding_Info :: struct {
    binding: u32,
    type: vk.DescriptorType,
    stages: vk.ShaderStageFlags,
    count: u32,
}

// Single source of truth for one descriptor set: the binding table and the Vulkan layout built from it.
// Writers, allocators and shader validation all read from this table.
Descriptor_Layout :: struct {
    name: string,
    device: vk.Device,
    handle: vk.DescriptorSetLayout,
    bindings: [dynamic; MAX_LAYOUT_BINDINGS]Binding_Info,
}

descriptor_layout_init :: proc(self: ^Descriptor_Layout, device: vk.Device, name := "") {
    self^ = {
        device = device,
        name = name,
    }
}

descriptor_layout_add :: proc(
    self: ^Descriptor_Layout,
    binding: u32,
    type: vk.DescriptorType,
    stages: vk.ShaderStageFlags,
    count: u32 = 1,
    loc := #caller_location,
) {
    if self.handle != 0 {
        log.panicf("Descriptor layout '%v': can't add binding %v after the layout was built", self.name, binding, location = loc)
    }
    if stages == {} || count == 0 {
        log.panicf("Descriptor layout '%v': binding %v needs at least one stage and a non-zero count", self.name, binding, location = loc)
    }
    if len(self.bindings) == cap(self.bindings) {
        log.panicf("Descriptor layout '%v': out of binding slots (MAX_LAYOUT_BINDINGS = %v)", self.name, MAX_LAYOUT_BINDINGS, location = loc)
    }
    if _, found := descriptor_layout_find(self, binding); found {
        log.panicf("Descriptor layout '%v': binding %v is declared twice", self.name, binding, location = loc)
    }

    append(&self.bindings, Binding_Info{binding = binding, type = type, stages = stages, count = count})
}

descriptor_layout_find :: proc(self: ^Descriptor_Layout, binding: u32) -> (info: ^Binding_Info, found: bool) {
    for &b in self.bindings {
        if b.binding == binding {
            return &b, true
        }
    }
    return nil, false
}

descriptor_layout_build :: proc(
    self: ^Descriptor_Layout,
    pNext: rawptr = nil,
    flags: vk.DescriptorSetLayoutCreateFlags = {},
    loc := #caller_location,
) -> (ok: bool) {
    assert(self.device != nil, "Descriptor layout has no device, call descriptor_layout_init first", loc)
    assert(self.handle == 0, "Descriptor layout was already built", loc)
    assert(len(self.bindings) > 0, "No bindings added to descriptor layout", loc)

    vk_bindings: [MAX_LAYOUT_BINDINGS]vk.DescriptorSetLayoutBinding
    for b, i in self.bindings {
        vk_bindings[i] = {
            binding = b.binding,
            descriptorType = b.type,
            descriptorCount = b.count,
            stageFlags = b.stages,
        }
    }

    info := vk.DescriptorSetLayoutCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        pNext = pNext,
        flags = flags,
        bindingCount = u32(len(self.bindings)),
        pBindings = &vk_bindings[0],
    }

    vk_check(vk.CreateDescriptorSetLayout(self.device, &info, nil, &self.handle), "Failed to create descriptor set layout") or_return
    return true
}

descriptor_layout_destroy :: proc(self: Descriptor_Layout) {
    if self.handle != 0 {
        vk.DestroyDescriptorSetLayout(self.device, self.handle, nil)
    }
}

// Descriptor counts of one layout, merged by type.
descriptor_layout_pool_sizes :: proc(self: ^Descriptor_Layout) -> (sizes: Ratios) {
    for b in self.bindings {
        ratios_add(&sizes, b.type, f32(b.count))
    }
    return
}

@(private = "file")
ratios_add :: proc(ratios: ^Ratios, type: vk.DescriptorType, amount: f32) {
    for &r in ratios {
        if r.type == type {
            r.ratio += amount
            return
        }
    }
    assert(len(ratios) < cap(ratios), "Too many distinct descriptor types, raise MAX_POOL_SIZES")
    append(ratios, Pool_Size_Ratio{type = type, ratio = amount})
}

// Merges a layout into the pool ratios, keeping the largest per set count of each type.
// Returns true when the ratios changed.
descriptor_ratios_track_layout :: proc(ratios: ^Ratios, layout: ^Descriptor_Layout) -> (changed: bool) {
    needed := descriptor_layout_pool_sizes(layout)
    for n in needed {
        found := false
        for &r in ratios {
            if r.type == n.type {
                found = true
                if n.ratio > r.ratio {
                    r.ratio = n.ratio
                    changed = true
                }
                break
            }
        }
        if !found {
            assert(len(ratios) < cap(ratios), "Too many distinct descriptor types, raise MAX_POOL_SIZES")
            append(ratios, n)
            changed = true
        }
    }
    return
}
