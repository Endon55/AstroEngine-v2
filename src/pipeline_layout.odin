package astro

import "base:runtime"
import "core:log"
import "core:mem"

import vk "vendor:vulkan"

MAX_PIPELINE_SETS :: #config(MAX_PIPELINE_SETS, 4)
MAX_PUSH_CONSTANT_RANGES :: #config(MAX_PUSH_CONSTANT_RANGES, 2)

Set_Source :: enum u8 {
    None,
    Owned,  // bindings declared on this pipeline layout
    Shared, // borrowed from somewhere else (e.g. the engine's scene data set)
}

// One structure for everything a pipeline binds: the descriptor set layouts, their bindings and the push constants.
// Adding a descriptor is a single pipeline_layout_add_binding line, and every shader handed to
// pipeline_layout_validate_shader is checked against what is declared here.
Pipeline_Layout :: struct {
    name: string,
    device: vk.Device,
    handle: vk.PipelineLayout,
    owned: [MAX_PIPELINE_SETS]Descriptor_Layout,
    shared: [MAX_PIPELINE_SETS]^Descriptor_Layout,
    sources: [MAX_PIPELINE_SETS]Set_Source,
    set_count: u32,
    push_constants: [dynamic; MAX_PUSH_CONSTANT_RANGES]vk.PushConstantRange,
}

pipeline_layout_init :: proc(self: ^Pipeline_Layout, device: vk.Device, name := "") {
    self^ = {
        device = device,
        name = name,
    }
}

// Declares `binding` of `set`. These numbers must match the shader's [[vk::binding(binding, set)]].
pipeline_layout_add_binding :: proc(
    self: ^Pipeline_Layout,
    set: u32,
    binding: u32,
    type: vk.DescriptorType,
    stages: vk.ShaderStageFlags,
    count: u32 = 1,
    loc := #caller_location,
) {
    pipeline_layout_check_set(self, set, loc)
    switch self.sources[set] {
    case .None:
        self.sources[set] = .Owned
        descriptor_layout_init(&self.owned[set], self.device, self.name)
    case .Shared:
        log.panicf("Pipeline layout '%v': set %v is shared, bindings can't be added to it", self.name, set, location = loc)
    case .Owned:
    }
    self.set_count = max(self.set_count, set + 1)
    descriptor_layout_add(&self.owned[set], binding, type, stages, count, loc)
}

// Uses a descriptor layout that lives elsewhere for `set`.
pipeline_layout_use_set :: proc(self: ^Pipeline_Layout, set: u32, layout: ^Descriptor_Layout, loc := #caller_location) {
    pipeline_layout_check_set(self, set, loc)
    if self.sources[set] != .None {
        log.panicf("Pipeline layout '%v': set %v is already defined", self.name, set, location = loc)
    }
    self.sources[set] = .Shared
    self.shared[set] = layout
    self.set_count = max(self.set_count, set + 1)
}

pipeline_layout_add_push_constant :: proc(
    self: ^Pipeline_Layout,
    $T: typeid,
    stages: vk.ShaderStageFlags,
    offset: u32 = 0,
    loc := #caller_location,
) {
    if len(self.push_constants) == cap(self.push_constants) {
        log.panicf("Pipeline layout '%v': out of push constant ranges (MAX_PUSH_CONSTANT_RANGES = %v)", self.name, MAX_PUSH_CONSTANT_RANGES, location = loc)
    }
    append(&self.push_constants, vk.PushConstantRange {
        stageFlags = stages,
        offset = offset,
        size = size_of(T),
    })
}

pipeline_layout_set :: proc(self: ^Pipeline_Layout, set: u32, loc := #caller_location) -> ^Descriptor_Layout {
    pipeline_layout_check_set(self, set, loc)
    switch self.sources[set] {
    case .Owned:
        return &self.owned[set]
    case .Shared:
        return self.shared[set]
    case .None:
    }
    log.panicf("Pipeline layout '%v' has no set %v", self.name, set, location = loc)
}

@(private = "file")
pipeline_layout_check_set :: proc(self: ^Pipeline_Layout, set: u32, loc: runtime.Source_Code_Location) {
    if self.device == nil {
        log.panicf("Pipeline layout used before pipeline_layout_init", location = loc)
    }
    if set >= MAX_PIPELINE_SETS {
        log.panicf("Pipeline layout '%v': set %v is out of range (MAX_PIPELINE_SETS = %v)", self.name, set, MAX_PIPELINE_SETS, location = loc)
    }
}

// Builds the owned descriptor set layouts, then the VkPipelineLayout.
pipeline_layout_build :: proc(self: ^Pipeline_Layout, loc := #caller_location) -> (ok: bool) {
    assert(self.handle == 0, "Pipeline layout was already built", loc)

    set_layouts: [MAX_PIPELINE_SETS]vk.DescriptorSetLayout
    for set in 0 ..< self.set_count {
        if self.sources[set] == .None {
            log.panicf("Pipeline layout '%v': set %v has no bindings but a higher set is used", self.name, set, location = loc)
        }
    }

    for set in 0 ..< self.set_count {
        if self.sources[set] == .Owned {
            if !descriptor_layout_build(&self.owned[set], loc = loc) {
                pipeline_layout_release(self)
                return false
            }
        }
        layout := pipeline_layout_set(self, set, loc)
        assert(layout.handle != 0, "Shared descriptor layout was never built", loc)
        set_layouts[set] = layout.handle
    }

    info := vk.PipelineLayoutCreateInfo {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = self.set_count,
        pSetLayouts = self.set_count > 0 ? &set_layouts[0] : nil,
        pushConstantRangeCount = u32(len(self.push_constants)),
        pPushConstantRanges = len(self.push_constants) > 0 ? &self.push_constants[0] : nil,
    }

    if !vk_check(vk.CreatePipelineLayout(self.device, &info, nil, &self.handle), "Failed to create pipeline layout") {
        pipeline_layout_release(self)
        return false
    }
    return true
}

// Destroys the pipeline layout and the descriptor layouts it owns. Takes a copy so it can be used from a deletion queue.
pipeline_layout_destroy :: proc(self: Pipeline_Layout) {
    if self.handle != 0 {
        vk.DestroyPipelineLayout(self.device, self.handle, nil)
    }
    for set in 0 ..< self.set_count {
        if self.sources[set] == .Owned {
            descriptor_layout_destroy(self.owned[set])
        }
    }
}

// Destroys the built Vulkan objects but keeps the declared bindings, so the layout can be built again.
pipeline_layout_release :: proc(self: ^Pipeline_Layout) {
    pipeline_layout_destroy(self^)
    self.handle = 0
    for set in 0 ..< self.set_count {
        if self.sources[set] == .Owned {
            self.owned[set].handle = 0
        }
    }
}

// Checks every descriptor the shader uses against this layout and logs one error per mismatch.
// Descriptors the layout declares but the shader doesn't use are fine.
pipeline_layout_validate_shader :: proc(self: ^Pipeline_Layout, spirv: []byte, shader_name: string) -> (ok: bool) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    reflection, reflected := spirv_reflect(spirv, context.temp_allocator)
    if !reflected {
        log.errorf("Shader '%v': not valid SPIR-V, can't validate against pipeline layout '%v'", shader_name, self.name)
        return false
    }

    ok = true
    for used in reflection.bindings {
        if used.set >= self.set_count {
            log.errorf(
                "Shader '%v' uses set %v binding %v (%v), but pipeline layout '%v' only has %v set(s)",
                shader_name, used.set, used.binding, used.type, self.name, self.set_count,
            )
            ok = false
            continue
        }

        info, found := descriptor_layout_find(pipeline_layout_set(self, used.set), used.binding)
        if !found {
            log.errorf(
                "Shader '%v' uses set %v binding %v (%v), but pipeline layout '%v' doesn't declare it. Add: pipeline_layout_add_binding(&layout, %v, %v, .%v, %v)",
                shader_name, used.set, used.binding, used.type, self.name, used.set, used.binding, used.type, reflection.stages,
            )
            ok = false
            continue
        }

        if !descriptor_types_compatible(info.type, used.type) {
            log.errorf(
                "Shader '%v' set %v binding %v is a %v, but pipeline layout '%v' declares it as %v",
                shader_name, used.set, used.binding, used.type, self.name, info.type,
            )
            ok = false
        }
        if reflection.stages != {} && !(reflection.stages <= info.stages) {
            log.errorf(
                "Shader '%v' (%v) uses set %v binding %v, but pipeline layout '%v' only exposes it to %v",
                shader_name, reflection.stages, used.set, used.binding, self.name, info.stages,
            )
            ok = false
        }
        if used.count != 0 && used.count > info.count {
            log.errorf(
                "Shader '%v' set %v binding %v is an array of %v, but pipeline layout '%v' declares a count of %v",
                shader_name, used.set, used.binding, used.count, self.name, info.count,
            )
            ok = false
        }
    }
    return
}

@(private = "file")
descriptor_types_compatible :: proc(layout_type, shader_type: vk.DescriptorType) -> bool {
    if layout_type == shader_type {
        return true
    }
    #partial switch layout_type {
    case .UNIFORM_BUFFER_DYNAMIC:
        return shader_type == .UNIFORM_BUFFER
    case .STORAGE_BUFFER_DYNAMIC:
        return shader_type == .STORAGE_BUFFER
    }
    return false
}


/* ************************************************

                SPIR-V reflection

  ************************************************* */

Spirv_Binding :: struct {
    set: u32,
    binding: u32,
    type: vk.DescriptorType,
    count: u32, // 0 means unsized
}

Spirv_Reflection :: struct {
    bindings: [dynamic]Spirv_Binding,
    stages: vk.ShaderStageFlags,
}

// Reads the descriptor bindings straight out of compiled SPIR-V, so it checks exactly what will be loaded.
spirv_reflect :: proc(code: []byte, allocator: runtime.Allocator) -> (result: Spirv_Reflection, ok: bool) {
    SPIRV_MAGIC :: 0x07230203
    SPIRV_HEADER_WORDS :: 5

    Op :: enum u32 {
        Entry_Point = 15,
        Type_Image = 25,
        Type_Sampler = 26,
        Type_Sampled_Image = 27,
        Type_Array = 28,
        Type_Runtime_Array = 29,
        Type_Struct = 30,
        Type_Pointer = 32,
        Constant = 43,
        Variable = 59,
        Decorate = 71,
    }
    Decoration :: enum u32 {
        Block = 2,
        Buffer_Block = 3,
        Binding = 33,
        Descriptor_Set = 34,
    }
    Storage_Class :: enum u32 {
        Uniform_Constant = 0,
        Uniform = 2,
        Storage_Buffer = 12,
    }
    Decorations :: struct {
        set, binding: u32,
        has_set, has_binding: bool,
        buffer_block: bool,
    }
    Variable :: struct {
        id, pointer_type, storage: u32,
    }

    if len(code) < SPIRV_HEADER_WORDS * 4 || len(code) % 4 != 0 {
        return {}, false
    }
    words := mem.slice_data_cast([]u32, code)
    if words[0] != SPIRV_MAGIC {
        return {}, false
    }

    decorations := make(map[u32]Decorations, allocator)
    types := make(map[u32][]u32, allocator)
    constants := make(map[u32]u32, allocator)
    variables := make([dynamic]Variable, allocator)
    result.bindings = make([dynamic]Spirv_Binding, allocator)

    for i := SPIRV_HEADER_WORDS; i < len(words); {
        word_count := int(words[i] >> 16)
        if word_count == 0 || i + word_count > len(words) {
            return {}, false
        }
        instruction := words[i:i + word_count]
        i += word_count

        #partial switch Op(instruction[0] & 0xFFFF) {
        case .Entry_Point:
            switch instruction[1] {
            case 0: result.stages += {.VERTEX}
            case 1: result.stages += {.TESSELLATION_CONTROL}
            case 2: result.stages += {.TESSELLATION_EVALUATION}
            case 3: result.stages += {.GEOMETRY}
            case 4: result.stages += {.FRAGMENT}
            case 5: result.stages += {.COMPUTE}
            }
        case .Decorate:
            entry := decorations[instruction[1]]
            #partial switch Decoration(instruction[2]) {
            case .Buffer_Block:
                entry.buffer_block = true
            case .Binding:
                entry.binding, entry.has_binding = instruction[3], true
            case .Descriptor_Set:
                entry.set, entry.has_set = instruction[3], true
            }
            decorations[instruction[1]] = entry
        case .Type_Image, .Type_Sampler, .Type_Sampled_Image, .Type_Array, .Type_Runtime_Array, .Type_Struct, .Type_Pointer:
            types[instruction[1]] = instruction
        case .Constant:
            constants[instruction[2]] = instruction[3]
        case .Variable:
            append(&variables, Variable{id = instruction[2], pointer_type = instruction[1], storage = instruction[3]})
        }
    }

    for variable in variables {
        storage := Storage_Class(variable.storage)
        if storage != .Uniform_Constant && storage != .Uniform && storage != .Storage_Buffer {
            continue
        }
        decoration := decorations[variable.id] or_continue
        if !decoration.has_set || !decoration.has_binding {
            continue
        }
        pointer := types[variable.pointer_type] or_continue
        if Op(pointer[0] & 0xFFFF) != .Type_Pointer {
            continue
        }

        type_id := pointer[3]
        count := u32(1)
        for {
            type := types[type_id] or_break
            #partial switch Op(type[0] & 0xFFFF) {
            case .Type_Array:
                count *= constants[type[3]] or_else 1
                type_id = type[2]
                continue
            case .Type_Runtime_Array:
                count = 0
                type_id = type[2]
                continue
            }
            break
        }

        resource := types[type_id] or_continue
        descriptor_type: vk.DescriptorType
        switch storage {
        case .Uniform_Constant:
            #partial switch Op(resource[0] & 0xFFFF) {
            case .Type_Sampled_Image:
                descriptor_type = .COMBINED_IMAGE_SAMPLER
            case .Type_Sampler:
                descriptor_type = .SAMPLER
            case .Type_Image:
                DIM_BUFFER :: 5
                DIM_SUBPASS_DATA :: 6
                dim, sampled := resource[3], resource[7]
                if dim == DIM_SUBPASS_DATA {
                    descriptor_type = .INPUT_ATTACHMENT
                } else if sampled == 2 {
                    descriptor_type = dim == DIM_BUFFER ? .STORAGE_TEXEL_BUFFER : .STORAGE_IMAGE
                } else {
                    descriptor_type = dim == DIM_BUFFER ? .UNIFORM_TEXEL_BUFFER : .SAMPLED_IMAGE
                }
            case:
                continue
            }
        case .Uniform:
            descriptor_type = decorations[type_id].buffer_block ? .STORAGE_BUFFER : .UNIFORM_BUFFER
        case .Storage_Buffer:
            descriptor_type = .STORAGE_BUFFER
        }

        append(&result.bindings, Spirv_Binding {
            set = decoration.set,
            binding = decoration.binding,
            type = descriptor_type,
            count = count,
        })
    }

    return result, true
}
