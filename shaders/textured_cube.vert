#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 proj;
    mat4 normal_matrix;
    vec3 light_pos;
    vec3 view_pos;
    float time;
} ubo;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inTexCoord;
layout(location = 3) in vec3 inColor;

layout(location = 0) out vec3 fragPos;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec2 fragTexCoord;
layout(location = 3) out vec3 fragColor;
layout(location = 4) out vec3 lightPos;
layout(location = 5) out vec3 viewPos;

void main() {
    // Apply rotation animation
    float rotationY = ubo.time * 1.5;
    float rotationX = ubo.time * 0.8;
    
    mat4 rotY = mat4(
        cos(rotationY), 0.0, sin(rotationY), 0.0,
        0.0, 1.0, 0.0, 0.0,
        -sin(rotationY), 0.0, cos(rotationY), 0.0,
        0.0, 0.0, 0.0, 1.0
    );
    
    mat4 rotX = mat4(
        1.0, 0.0, 0.0, 0.0,
        0.0, cos(rotationX), -sin(rotationX), 0.0,
        0.0, sin(rotationX), cos(rotationX), 0.0,
        0.0, 0.0, 0.0, 1.0
    );
    
    mat4 animatedModel = ubo.model * rotY * rotX;
    
    vec4 worldPos = animatedModel * vec4(inPosition, 1.0);
    fragPos = worldPos.xyz;
    
    gl_Position = ubo.proj * ubo.view * worldPos;
    
    // Transform normal to world space
    fragNormal = normalize(mat3(ubo.normal_matrix) * inNormal);
    
    // Pass texture coordinates and color
    fragTexCoord = inTexCoord;
    fragColor = inColor;
    
    // Pass light and view positions
    lightPos = ubo.light_pos;
    viewPos = ubo.view_pos;
}