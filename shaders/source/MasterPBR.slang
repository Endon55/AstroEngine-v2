#define PBR_PI 3.14159265359


struct PBR_Data {
    float3 albedo;
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
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}


float3 calculate_pbr(PBR_Data data, float3 normal, float3 fragment_pos, float3 camera_pos) {

    float3 N = normalize(normal);
    float3 V = normalize(camera_pos - fragment_pos);

    float3 F0 = float3(0.04);
    F0 = lerp(F0, data.albedo, data.metallic);
    float3 Lo = float3(0.0);
    for (int i = 0; i < Light_Count; i++ ){
        Light light = Lights[i];

        float3 L = normalize(light.position - fragment_pos);
        float3 H = normalize(V + L);
        float distance = length(light.position - fragment_pos);
        float attenuation = 1.0 / (distance * distance);
        float3 radiance = light.color * light.intensity * attenuation;

        float NDF = DistributionGGX(N, H, data.roughness);
        float G = GeometrySmith(N, V, L, data.roughness);

        float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);
        float3 kS = F;
        float3 kD = float3(1.0) -kS;
        kD *= 1.0 - data.metallic;

        float3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) *  max(dot(N, L), 0.0) + 0.0001;
        float3 specular = numerator / denominator;

        float NdotL = max(dot(N, L), 0.0);
        Lo += (kD * data.albedo / PBR_PI + specular) * radiance * NdotL;
    }

    float3 ambient = float3(0.03) * data.albedo * data.ambient_occlusion;
    float3 color = ambient + Lo;
    color = color / (color + float3(1.0));
    color = pow(color, float3(1.0/2.2));
    return color;
}
