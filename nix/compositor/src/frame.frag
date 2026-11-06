precision highp float;
uniform vec2 size;
uniform float alpha;
uniform float radius;
uniform float inner_radius;
uniform float thickness;
uniform float titlebar_height;
uniform float feather;
uniform vec4 frame_color;
uniform vec2 full_size;
uniform vec2 piece_offset;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif
//_COVERAGE_
//_LIGHTING_
void main() {
    vec2 p = v_coords * size + piece_offset - full_size * 0.5;
    float outer = rounded_coverage(p, full_size * 0.5, radius, 2.0 * feather);
    vec2 inner_size = max(full_size - vec2(thickness * 2.0, titlebar_height + thickness), vec2(0.0));
    vec2 inner_center = vec2(0.0, (titlebar_height - thickness) * 0.5);
    float inner = rounded_coverage(p - inner_center, inner_size * 0.5, inner_radius, 2.0 * feather);
    float coverage = max(outer - inner, 0.0);
    vec3 color = frame_lighting(frame_color.rgb, p, full_size * 0.5, radius,
        p - inner_center, inner_size * 0.5, inner_radius, 2.0 * feather);
    gl_FragColor = vec4(color * frame_color.a, frame_color.a) * alpha * coverage;
}
