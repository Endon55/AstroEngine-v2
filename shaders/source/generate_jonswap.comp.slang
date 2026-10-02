#include "oceanography.slang"

struct PushConstants
{
    float4 data1; // windSpeed, fetch, peaking, scale
    float4 data2; // shortWavesFade, alignment, extraAlignment, (unused)
    float4 data3; // patchSize, ...
    float4 data4;
};

RWTexture2D<float4> image;



[[vk_push_constant]]
PushConstants push_constants;

[shader("compute")]
[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadID: SV_DispatchThreadID)
{
    SpectrumParams params = {};
        params.energySpectrum = int(push_constants.data1.x);
        params.windSpeed = push_constants.data1.y;
        params.fetch = push_constants.data1.z;
        params.peaking = push_constants.data1.a;
        params.scale = push_constants.data2.x;
        params.shortWavesFade = push_constants.data2.y;
        params.alignment = push_constants.data2.z;
        params.extraAlignment = push_constants.data2.a;
    let texelCoord = uint2(dispatchThreadID.xy);


    uint2 size;
    image.GetDimensions(size.x, size.y);

    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        // physical side length of the simulated patch, in meters (guard against 0 -> inf deltaK)
        float patchSize = max(push_constants.data3.x, 1.0);
        float deltaK = 2.0 * OCEANOGRAPHY_PI / patchSize;

        // texel coords index a centered wavevector, not omega/theta directly
        float2 halfSize = float2(size) * 0.5;
        float2 K = (float2(texelCoord) - halfSize) * deltaK;
        float kLength = length(K);

        float value = 0.0;
        if (kLength > 0.0001)
        {
            float theta = atan2(K.y, K.x);
            float omega = Frequency(kLength, 1.0);
            value = FullSpectrum(omega, theta, params)
                * ShortWavesFade(kLength, params.shortWavesFade)
                * params.scale;
        }

        image[texelCoord] = float4(value, 0.0, 0.0, 1.0);
    }
}

