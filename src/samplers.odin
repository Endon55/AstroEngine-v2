package astro

import vk "vendor:vulkan"

Default_Sampler :: enum u32 {
    LINEAR= 0,
    NEAREST,
}
Engine_Samplers :: struct {
    samplers: [len(Default_Sampler)]vk.Sampler 
}

create_engine_samplers :: proc(self: ^Engine_Samplers) ->(ok:bool,) {

    sampler_info := vk.SamplerCreateInfo {
        sType = .SAMPLER_CREATE_INFO,
        magFilter = .LINEAR,
        minFilter = .LINEAR,
        mipmapMode = .LINEAR,
        addressModeU = .CLAMP_TO_EDGE,
        addressModeV = .CLAMP_TO_EDGE,
        addressModeW = .CLAMP_TO_EDGE,
        maxLod = vk.LOD_CLAMP_NONE,
    }

    vk_check(vk.CreateSampler(GLOBALS.vk_device, &sampler_info, nil, &self.samplers[Default_Sampler.LINEAR])) or_return  

    sampler_info.magFilter = .NEAREST
    sampler_info.minFilter = .NEAREST
    sampler_info.mipmapMode = .NEAREST

    vk_check(vk.CreateSampler(GLOBALS.vk_device, &sampler_info, nil, &self.samplers[Default_Sampler.NEAREST])) or_return


    deletion_queue_push(GLOBALS.main_deletion_queue, self^)
    return true
}



samplers_deinit :: proc(self: ^ Engine_Samplers) {
    for sampler in self.samplers {
        vk.DestroySampler(GLOBALS.vk_device, sampler, nil)
    }
}
