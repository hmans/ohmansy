uniform vec2 bevel_widths;
uniform vec2 bevel_strength;
uniform vec2 light_direction;
uniform vec3 light_highlight;
uniform vec3 light_shadow;

// Analytic rounded-rectangle normals keep the light continuous at corners.
vec2 frame_normal(vec2 p, vec2 half_size, float r) {
    r = min(r, min(half_size.x, half_size.y));
    vec2 q = abs(p) - half_size + r;
    vec2 corner = max(q, 0.0);
    if (dot(corner, corner) > 0.000001) return normalize(corner) * sign(p);
    return q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
}
vec3 bevel_light(vec3 color, float facing, float weight) {
    color = mix(color, light_highlight, clamp(max(facing, 0.0) * bevel_strength.x * weight, 0.0, 1.0));
    return mix(color, light_shadow, clamp(max(-facing, 0.0) * bevel_strength.y * weight, 0.0, 1.0));
}
vec3 frame_lighting(vec3 color, vec2 outer_p, vec2 outer_half, float outer_r,
    vec2 inner_p, vec2 inner_half, float inner_r, float pixel_size) {
    vec2 light = light_direction;
    if (bevel_widths.x > 0.0) {
        float d = -rounded_distance(outer_p, outer_half, min(outer_r, min(outer_half.x, outer_half.y)));
        float weight = 1.0 - smoothstep(0.0, bevel_widths.x, max(d, 0.0));
        color = bevel_light(color, dot(frame_normal(outer_p, outer_half, outer_r), light), weight);
    }
    if (bevel_widths.y > 0.0) {
        float d = rounded_distance(inner_p, inner_half, min(inner_r, min(inner_half.x, inner_half.y)));
        float weight = 1.0 - smoothstep(0.0, bevel_widths.y, max(d, 0.0));
        color = bevel_light(color, dot(-frame_normal(inner_p, inner_half, inner_r), light), weight);
    }
    return color;
}
