#include "inc_scene_data.slang"
#include "inc_gltf_data.slang"

struct PSInput
{
    [vk_location(2)]
    float4 color;
};

struct PSOutput
{
    [vk_location(0)]
    float4 out_frag_color: SV_Target0;
};

[shader("fragment")]
PSOutput main(PSInput input)
{
    PSOutput output;
    output.out_frag_color = input.color;
    return output;
}
