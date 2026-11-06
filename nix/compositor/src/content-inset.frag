precision highp float;
uniform vec2 size;
uniform float alpha;
uniform vec2 client_size;
uniform vec2 piece_offset;
uniform float radius;
uniform vec4 outer_rect;
uniform float outer_radius;
uniform float feather;
uniform vec2 shadow_params;
uniform vec2 shadow_offset;
uniform vec4 shadow_color;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif
//_COVERAGE_
void main() {
    vec2 p = v_coords * size + piece_offset;
    vec2 half_size = client_size * 0.5;
    float r = min(radius, min(half_size.x, half_size.y));
    float coverage = rounded_coverage(p - half_size, half_size, r, 2.0 * feather);
    coverage = min(coverage, rounded_coverage(p - outer_rect.xy - outer_rect.zw * 0.5,
        outer_rect.zw * 0.5, outer_radius, 2.0 * feather));
    // The frame casts its shadow inward. Positive offset moves the apparent
    // opening southeast, leaving more shadow along the top and left app edges.
    float depth = max(-rounded_distance(p - half_size - shadow_offset, half_size, r), 0.0);
    float softness = max(shadow_params.y, 2.0 * feather);
    float strength = 1.0 - smoothstep(max(shadow_params.x - softness, 0.0), shadow_params.x + softness, depth);
    float a = shadow_color.a * strength * coverage * alpha;
    gl_FragColor = vec4(shadow_color.rgb * a, a);
}
