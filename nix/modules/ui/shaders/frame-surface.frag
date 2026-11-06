#version 440
#extension GL_GOOGLE_include_directive : require
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surface_size;
    vec4 material_color;
    float radius;
    float density;
    float noise_strength;
    float material_opacity;
    float interaction;
    vec2 bevel_widths;
    vec2 bevel_strength;
    vec2 light_direction;
    vec3 light_highlight;
    vec3 light_shadow;
    float inner_radius;
};
// The build copies the native frame's functions here, without its standalone
// uniform declarations. This keeps bevel normals and shading identical.
#include "rounded-coverage.glsl"
#include "frame-lighting.glsl"
void main() {
    vec2 p = qt_TexCoord0 * surface_size - surface_size * 0.5;
    float coverage = rounded_coverage(p, surface_size * 0.5, radius, 1.0 / density);
    vec2 inner_half = max(surface_size * 0.5 - vec2(3.0), vec2(0.0));
    vec3 color = frame_lighting(material_color.rgb, p, surface_size * 0.5, radius,
        p, inner_half, inner_radius, 1.0 / density);
    // The caption well is filled, unlike a window's client cutout. Keep its
    // interior flat rather than extending the reversed bevel across the label.
    float well = rounded_coverage(p, inner_half, inner_radius, 1.0 / density);
    color = mix(color, material_color.rgb, well);
    float grain = fract(sin(dot(floor(qt_TexCoord0 * surface_size * density), vec2(12.9898,78.233))) * 43758.5453) - 0.5;
    color = clamp(color + grain * noise_strength + interaction, 0.0, 1.0);
    float a = material_color.a * material_opacity * coverage * qt_Opacity;
    fragColor = vec4(color * a, a);
}
