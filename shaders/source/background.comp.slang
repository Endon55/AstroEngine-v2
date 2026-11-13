


struct PushConstants
{
    float4 fov_extent;
    float camera_pitch;
    float h_fov;
};

[[vk_binding(0,1)]]
RWTexture2D<float4> background;

[[vk_push_constant]]
PushConstants push_constants;

// Return random noise in the range [0.0, 1.0], as a function of x.
float Noise2d(in float2 x)
{
    float xhash = cos(x.x * 37.0);
    float yhash = cos(x.y * 57.0);
    return frac(415.92653 * (xhash + yhash));
}

// Convert Noise2d() into a "star field" by stomping everthing below fThreshhold
// to zero.
float NoisyStarField(in float2 vSamplePos, float fThreshhold)
{
    float StarVal = Noise2d(vSamplePos);
    if (StarVal >= fThreshhold)
        StarVal = pow((StarVal - fThreshhold) / (1.0 - fThreshhold), 6.0);
    else
        StarVal = 0.0;
    return StarVal;
}

// Stabilize NoisyStarField() by only sampling at integer values.
float StableStarField(in float2 vSamplePos, float fThreshhold)
{
    // Linear interpolation between four samples.
    // Note: This approach has some visual artifacts.
    // There must be a better way to "anti alias" the star field.
    float fractX = frac(vSamplePos.x);
    float fractY = frac(vSamplePos.y);
    float2 floorSample = floor(vSamplePos);
    float v1 = NoisyStarField(floorSample, fThreshhold);
    float v2 = NoisyStarField(floorSample + float2(0.0, 1.0), fThreshhold);
    float v3 = NoisyStarField(floorSample + float2(1.0, 0.0), fThreshhold);
    float v4 = NoisyStarField(floorSample + float2(1.0, 1.0), fThreshhold);

    float StarVal = v1 * (1.0 - fractX) * (1.0 - fractY) +
                    v2 * (1.0 - fractX) * fractY + v3 * fractX * (1.0 - fractY) +
                    v4 * fractX * fractY;
    return StarVal;
}

void mainImage(out float4 fragColor, in float2 fragCoord)
{
    float2 iResolution;
    background.GetDimensions(iResolution.x, iResolution.y);

    // Sky Background Color
    float3 vColor = float3( 0.1, 0.2, 0.4 ) * fragCoord.y / iResolution.y;

    

    float StarFieldThreshhold =  0.97;

    // Stars with a slow crawl.
    float xRate = 0.2;
    float yRate = -0.06;
    float2 vSamplePos = fragCoord.xy + float2(xRate * float(1), yRate * float(1));
    float StarVal = StableStarField(vSamplePos, StarFieldThreshhold);
    vColor += float3(StarVal, StarVal, StarVal);

    fragColor = float4(vColor, 1.0);
}
static float DEG_TO_RAD = (3.1415 / 180);
[shader("compute")]
[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadID: SV_DispatchThreadID)
{
    let value = float4(0.0, 0.0, 0.0, 1.0);

    let texelCoord = uint2(dispatchThreadID.xy);

    uint2 size;
    float2 draw_extent = push_constants.fov_extent.za;
    float2 fov = push_constants.fov_extent.xy;
    background.GetDimensions(size.x, size.y);
    float half_height = draw_extent.y * 0.5;
    uint horizon_y = uint(half_height * (1.0 + tan(push_constants.camera_pitch) / tan(fov.y * 0.5)));

    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        if(texelCoord.y <= horizon_y) {
            float4 color;
            mainImage(color, texelCoord);
            background[texelCoord] = color;

        } else {
            background[texelCoord] = float4(0.0, 0.03, 0.4, 1.0);
        }
    }
}
