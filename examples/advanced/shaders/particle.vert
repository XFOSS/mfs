#version 450

// Input: Quad vertices
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

// Input: Per-instance data
layout(location = 2) in vec4 instancePositionSize; // xyz = position, w = size
layout(location = 3) in vec4 instanceColor;

// Output to fragment shader
layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec4 fragColor;

// Uniform camera data
layout(set = 0, binding = 0) uniform CameraData {
    mat4 viewMatrix;
    mat4 projectionMatrix;
    vec3 cameraPosition;
} camera;

void main() {
    // Extract instance data
    vec3 particlePosition = instancePositionSize.xyz;
    float particleSize = instancePositionSize.w;
    
    // Billboard calculation - always face camera
    vec3 cameraRight = normalize(cross(vec3(0.0, 1.0, 0.0), normalize(particlePosition - camera.cameraPosition)));
    vec3 cameraUp = normalize(cross(normalize(particlePosition - camera.cameraPosition), cameraRight));
    
    // If we're too close to vertical, use a different up vector
    if (length(cameraRight) < 0.001) {
        cameraRight = vec3(1.0, 0.0, 0.0);
        cameraUp = vec3(0.0, 0.0, 1.0);
    }
    
    // Scale the quad by particle size
    vec3 vertPosition = particlePosition 
                      + cameraRight * inPosition.x * particleSize
                      + cameraUp * inPosition.y * particleSize;
    
    // Transform to clip space
    gl_Position = camera.projectionMatrix * camera.viewMatrix * vec4(vertPosition, 1.0);
    
    // Pass data to fragment shader
    fragTexCoord = inTexCoord;
    fragColor = instanceColor;
}