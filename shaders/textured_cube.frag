#version 450

layout(binding = 1) uniform sampler2D texSampler;

layout(binding = 2) uniform MaterialUBO {
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
    float shininess;
    float metallic;
    float roughness;
    vec3 emissive;
} material;

layout(location = 0) in vec3 fragPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragTexCoord;
layout(location = 3) in vec3 fragColor;
layout(location = 4) in vec3 lightPos;
layout(location = 5) in vec3 viewPos;

layout(location = 0) out vec4 outColor;

void main() {
    // Sample texture
    vec4 texColor = texture(texSampler, fragTexCoord);
    
    // Combine texture with vertex color
    vec3 baseColor = texColor.rgb * fragColor * material.diffuse;
    
    // Normalize vectors
    vec3 norm = normalize(fragNormal);
    vec3 lightDir = normalize(lightPos - fragPos);
    vec3 viewDir = normalize(viewPos - fragPos);
    vec3 reflectDir = reflect(-lightDir, norm);
    
    // Ambient lighting
    vec3 ambient = material.ambient * baseColor;
    
    // Diffuse lighting
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * baseColor;
    
    // Specular lighting (Blinn-Phong)
    vec3 halfwayDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(norm, halfwayDir), 0.0), material.shininess);
    vec3 specular = spec * material.specular;
    
    // PBR-style metallic workflow
    vec3 F0 = mix(vec3(0.04), baseColor, material.metallic);
    float roughness = material.roughness;
    
    // Simple fresnel approximation
    float cosTheta = max(dot(halfwayDir, viewDir), 0.0);
    vec3 fresnel = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
    
    // Apply roughness to specular
    specular = mix(specular, specular * fresnel, 0.5) * (1.0 - roughness);
    
    // Emissive contribution
    vec3 emissive = material.emissive;
    
    // Combine all lighting components
    vec3 result = ambient + diffuse + specular + emissive;
    
    // Apply simple tone mapping
    result = result / (result + vec3(1.0));
    
    // Gamma correction
    result = pow(result, vec3(1.0/2.2));
    
    outColor = vec4(result, texColor.a);
}