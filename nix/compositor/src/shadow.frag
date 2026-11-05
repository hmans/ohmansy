precision highp float;
uniform vec2 size;
uniform float alpha;
uniform float radius;
uniform float softness;
uniform float spread;
uniform vec2 offset;
uniform vec4 shadow_color;
uniform vec2 window_size;
uniform vec2 piece_offset;
uniform float feather;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif
float rounded_distance(vec2 p, vec2 half_size, float r) {
    r = min(r, min(half_size.x, half_size.y));
    vec2 q = abs(p) - half_size + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
void main() {
    vec2 p = v_coords * size + piece_offset - window_size * 0.5;
    float outside = smoothstep(-feather, feather, rounded_distance(p, window_size * 0.5, radius));
    float distance = max(rounded_distance(p - offset, window_size * 0.5, radius) - spread, 0.0);
    float falloff = exp(-0.5 * distance * distance / (softness * softness));
    // Fade the truncated Gaussian tail to zero before the element boundary.
    falloff *= 1.0 - smoothstep(2.5 * softness, 3.0 * softness, distance);
    gl_FragColor = vec4(shadow_color.rgb * shadow_color.a, shadow_color.a) * alpha * outside * falloff;
}
