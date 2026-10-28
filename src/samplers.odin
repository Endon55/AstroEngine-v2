package astro

import vk "vendor:vulkan"

Default_Sampler :: enum {
    NEAREST = 0,
    LINEAR,
}
Engine_Samplers :: struct {
    samplers: [len(Default_Sampler)]vk.Sampler 
}
samplers_init :: proc(self: ^Engine_Samplers) ->(ok:bool,) {

    sampler_info := vk.SamplerCreateInfo {
        sType = .SAMPLER_CREATE_INFO,
        magFilter = .NEAREST,
        minFilter = .NEAREST,
    }

    vk_check(vk.CreateSampler(GLOBALS.vk_device, &sampler_info, nil, &self.samplers[Default_Sampler.NEAREST])) or_return  

    sampler_info.magFilter = .LINEAR
    sampler_info.minFilter = .LINEAR

    vk_check(vk.CreateSampler(GLOBALS.vk_device, &sampler_info, nil, &self.samplers[Default_Sampler.LINEAR])) or_return


    deletion_queue_push(GLOBALS.main_deletion_queue, self^)
    return true
}

samplers_deinit :: proc(self: ^ Engine_Samplers) {
    for sampler in self.samplers {
        vk.DestroySampler(GLOBALS.vk_device, sampler, nil)
    }
}
