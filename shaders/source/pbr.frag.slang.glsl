struct PSInput
{
    [vk_location(0)]
    float3 inNormal : NORMAL;
    [vk_location(1)]
    float3 inColor : COLOR;
    [vk_location(2)]
    float2 inUV : TEXCOORD0;
};

struct PSOutput
{
    [vk_location(0)]
    float4 out_frag_color : SV_Target0;
};

struct Material {
    uint albedo_index;
    uint roughness_index;
    uint metallic_index;
    float base_reflectance;
}

// Material properties
uniform float ao;

// Lights
uniform vec3 lightPosition;
uniform vec3 lightColor;
uniform vec3 camPos;

const static float PI = 3.14159265359;

// 1. Normal Distribution Function (Trowbridge-Reitz GGX)
// Approximates the relative area of microfacets aligned to the halfway vector.
float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

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

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// 3. Fresnel Equation (Schlick's Approximation)
// Calculates the ratio of surface reflection over refraction.
vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
    vec3 N = normalize(Normal);
    vec3 V = normalize(camPos - FragPos);

    // Calculate base reflectance (F0); non-metals use 0.04, metals use the albedo
    vec3 F0 = vec3(0.04); 
    F0 = mix(F0, albedo, metallic);

    // Lighting pipeline (Single Directional Light for simplicity)
    vec3 L = normalize(lightPosition - FragPos);
    vec3 H = normalize(V + L);
    
    // Radiance
    vec3 radiance = lightColor;

    // Cook-Torrance BRDF components
    float NDF = DistributionGGX(N, H, roughness);   
    float G   = GeometrySmith(N, V, L, roughness);    
    vec3 F    = fresnelSchlick(max(dot(H, V), 0.0), F0);   
    
    // Specular vs Diffuse ratio (Energy Conservation)
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metallic;	  

    // Compute Specular (Cook-Torrance)
    vec3 numerator    = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001; // +0.0001 prevents divide by zero
    vec3 specular = numerator / denominator;

    // Combine Diffuse and Specular into total radiance
    float NdotL = max(dot(N, L), 0.0);                
    vec3 Lo = (kD * albedo / PI + specular) * radiance * NdotL;

    // Ambient lighting (rudimentary substitute for IBL/Global Illumination)
    vec3 ambient = vec3(0.03) * albedo * ao;
    vec3 color = ambient + Lo;

    // HDR tonemapping (Reinhard) and Gamma Correction
    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));  

    FragColor = vec4(color, 1.0);
}
