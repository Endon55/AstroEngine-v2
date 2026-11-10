
static float LINE_LENGTH = 3.0;

struct VS_Format 
{
    float4 pos : SV_Position;
    [vk_location(0)]
    float4 worldPos;
    [vk_location(1)]
    float3 normal;
    [vk_location(2)]
    float4 color;
};

struct PushConstants
{
    float4x4 render_matrix;
};

[vk_push_constant]
PushConstants push_constants;


[shader("geometry")]
[maxvertexcount(6)]
void main(triangle VS_Format input[3], inout LineStream<VS_Format> lineStream) {

    for(uint i = 0; i < 3; i++) {
        VS_Format output;

        output.pos = input[i].pos;
        output.normal = input[i].normal;
        output.color = float4(0.0, 1.0, 0.0, 1.0);
        lineStream.Append(output);

        float3 extrusion = input[i].normal * LINE_LENGTH;
        output.pos = input[i].worldPos + float4(extrusion, 0.0);
        output.pos = mul(push_constants.render_matrix, output.pos);
        output.normal = input[i].normal;
        output.color = float4(0.0, 1.0, 0.0, 1.0);
        lineStream.Append(output);

        lineStream.RestartStrip();
    }
}
