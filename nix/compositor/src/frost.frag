#version 100
//_DEFINES_
#if defined(EXTERNAL)
#extension GL_OES_EGL_image_external : require
#endif
precision highp float;
#if defined(EXTERNAL)
uniform samplerExternalOES tex;
#else
uniform sampler2D tex;
#endif
uniform mat3 tex_matrix;
uniform float alpha;
uniform vec4 source_rect;
uniform vec4 sample_bounds;
uniform vec2 texture_size;
uniform vec2 frame_size;
uniform float radius;
uniform float inner_radius;
uniform float thickness;
uniform float titlebar_height;
uniform float blur_radius;
uniform float opacity;
uniform float noise_strength;
uniform vec4 frame_color;
uniform float density;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif
//_COVERAGE_
void main() {
    vec2 p = (v_coords - source_rect.xy) / source_rect.zw * frame_size;
    float outer = rounded_coverage(p - frame_size * 0.5, frame_size * 0.5, radius, 1.0 / density);
    vec2 inner_size = max(frame_size - vec2(thickness * 2.0, titlebar_height + thickness), vec2(0.0));
    vec2 inner_center = vec2(frame_size.x * 0.5, titlebar_height + inner_size.y * 0.5);
    float inner = rounded_coverage(p - inner_center, inner_size * 0.5, inner_radius, 1.0 / density);
    float coverage = max(outer - inner, 0.0);
    if (coverage <= 0.0) { gl_FragColor = vec4(0.0); return; }
    vec3 backdrop = vec3(0.0);
    float total = 0.0;
    // Gaussian kernel on the actual scene behind this window. No CPU readback.
    for (int y = -3; y <= 3; y++) {
        for (int x = -3; x <= 3; x++) {
            vec2 offset = vec2(float(x), float(y));
            float weight = exp(-dot(offset, offset) / 4.0);
            vec2 uv = clamp(v_coords + offset * blur_radius * density / (3.0 * texture_size), sample_bounds.xy, sample_bounds.zw);
            backdrop += texture2D(tex, uv).rgb * weight;
            total += weight;
        }
    }
    vec3 color = mix(backdrop / total, frame_color.rgb, frame_color.a);
    // Grain is anchored to the frame, so it does not shimmer while idle.
    float grain = fract(sin(dot(floor(p * density), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    color = clamp(color + grain * noise_strength, 0.0, 1.0);
    float a = opacity * alpha * coverage;
    gl_FragColor = vec4(color * a, a);
}
