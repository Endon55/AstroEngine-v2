#define PBR_PI 3.14159265359


interface IMaxSubvalue {
    float maxSubvalue();
}
extension float : IMaxSubvalue {
    float maxSubvalue() { return this;}
}
extension float2 : IMaxSubvalue {
    float maxSubvalue() { return max(this.x, this.y);}
}
extension float3 : IMaxSubvalue {
    float maxSubvalue() { return max(this.x, max(this.y, this.z));}
}
extension float4 : IMaxSubvalue {
    float maxSubvalue() { return max(this.x, max(this.y, max(this.z, this.a)));}
}

enum Material_Type {
    Water = 0,
    Plastic_Low,
    Plastic_High,
    Glass_High,
    Diamond,
    Iron,
    Copper,
    Gold,
    Aluminum,
    Silver,
    Glass_Low = Plastic_Low,
    Ruby = Glass_High,
}

struct PBR_Data {
    float4 albedo;
    float3 emission;
    float3 subsurface_scattering;
    float3 f0;
    float fresnel_factor;
    float3 F;
    float f;

    float metallic;
    float roughness;
    float ambient_occlusion;

}

struct Light {
    float3 color;
    float3 intensity;
    float3 position;
}

static Light Lights[] = {
    {
        float3(1.0, 1.0, 1.0),
        float3(22.0, 22.0, 22.0),
        float3(0.0, 0.0, 50)
    },
    {
        float3(1.0, 1.0, 1.0),
        float3(22.0, 22.0, 22.0),
        float3(50, 50, 50)
    },   
    {
        float3(1.0, 1.0, 1.0),
        float3(22.0, 22.0, 22.0),
        float3(-50, 50, 50)
    },
    {
        float3(1.0, 1.0, 1.0),
        float3(22.0, 22.0, 22.0),
        float3(50, -50, 50)
    },
    {
        float3(1.0, 1.0, 1.0),
        float3(22.0, 22.0, 22.0),
        float3(-50, -50, 50)
    },
   };

static uint Light_Count = sizeof(Lights) / sizeof(Lights[0]);


float3 getF0(Material_Type material) {
    switch(material) {
        case Material_Type.Water:
            return float3(0.02);
        case Material_Type.Plastic_Low:
            return float3(0.03);
        case Material_Type.Plastic_High:
            return float3(0.05);
        case Material_Type.Glass_High:
            return float3(0.08);
        case Material_Type.Diamond:
            return float3(0.17);
        case Material_Type.Iron:
            return float3(0.56, 0.57, 0.58);
        case Material_Type.Copper:
            return float3(0.95, 0.64, 0.54);
        case Material_Type.Gold:
            return float3(1.0, 0.71, 0.29);
        case Material_Type.Aluminum:
            return float3(0.91, 0.92, 0.92);
        case Material_Type.Silver:
            return float3(0.95, 0.93, 0.88);
    }
    return float3(1.0);
}


float DistributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PBR_PI * denom * denom;

    return num / denom;
}

// 2. Geometry Function (Schlick-GGX)
// Approximates the self-shadowing/masking of microfacets.
float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// 3. Fresnel Equation (Schlick's Approximation)
// Calculates the ratio of surface reflection over refraction.
float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (float3(1.0) - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

float maxMAX<T : IMaxSubvalue>(T val) {
   return val.maxSubvalue(); 
}


float3 sRGB_to_RGB(float3 sRGB) {
    return pow(sRGB, 2.2);
}
float4 sRGBA_to_RGBA(float4 sRGBA) {
    return float4(pow(sRGBA.rgb, 2.2), sRGBA.a);
}


float4 calculate_pbr(PBR_Data data, float3 normal, float3 fragment_pos, float3 camera_pos) {

    float3 N = normalize(normal);
    float3 V = normalize(camera_pos - fragment_pos);
    //if albedo is in sRGB not regular RGB then it needs to be converted to regular RGB first. which is just sR^2.2, sG^2.2, and sB^2.2, or pow(sRGB, 2.2);
    float3 F0 = data.f0;

    float fresnel_factor = dot(N, V);
    float3 F = fresnelSchlick(fresnel_factor, F0);
    float f = maxMAX(F);

    F0 = lerp(F0, data.albedo.xyz, data.metallic);
    float3 Lo = float3(0.0);
    float3 sss = float3(0.0);
    for (int i = 0; i < Light_Count; i++ ){
        Light light = Lights[i];

        float3 L = normalize(light.position - fragment_pos);
        float3 H = normalize(V + L);

        float sssGlow = pow(saturate(dot(-L, V)), 4.0);
        float mask = saturate(dot(N, -L)); 

        float distance = length(light.position - fragment_pos);
        float attenuation = 1.0 / (distance * distance);
        float3 radiance = light.color * light.intensity * attenuation;

        float NDF = DistributionGGX(N, H, data.roughness);
        float G = GeometrySmith(N, V, L, data.roughness);

        float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);
        float3 kS = F;
        float3 kD = float3(1.0) - kS;
        kD *= 1.0 - data.metallic;

        float3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) *  max(dot(N, L), 0.0) + 0.0001;
        float3 specular = numerator / denominator;

        float NdotL = max(dot(N, L), 0.0);
        Lo += (kD * data.albedo.xyz / PBR_PI + specular) * radiance * NdotL;
        sss += data.subsurface_scattering * sssGlow * mask * radiance * 2.0;
    }
    float3 volumeColor = data.emission + sss; 

    float3 ambient = float3(0.03) * data.albedo.xyz * data.ambient_occlusion;
    float3 color = (volumeColor * (float3(1.0) - F)) + ambient + Lo;
    color = color / (color + float3(1.0));
    color = pow(color, float3(1.0/2.2));
    
    return float4(color, f);
}
