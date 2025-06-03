#version 450

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 1) uniform sampler2D particleTexture;

void main() {
    // Sample the texture
    vec4 texColor = texture(particleTexture, fragTexCoord);
    
    // Apply instance color and texture alpha
    outColor = vec4(fragColor.rgb, fragColor.a * texColor.a);
    
    // Discard almost transparent fragments
    if (outColor.a < 0.01)
        discard;
        
    // Pre-multiply alpha for better blending
    outColor.rgb *= outColor.a;
}