precision highp float;
uniform vec2 size;
uniform float alpha;
uniform float radius;
uniform float thickness;
uniform float feather;
uniform vec4 ring_color;
uniform vec2 full_size;
uniform vec2 piece_offset;
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
    vec2 p = v_coords * size + piece_offset - full_size * 0.5;
    float outer = rounded_distance(p, full_size * 0.5, radius + thickness);
    float inner = rounded_distance(p, max(full_size * 0.5 - thickness, vec2(0.0)), radius);
    float coverage = (1.0 - smoothstep(-feather, feather, outer)) * smoothstep(-feather, feather, inner);
    gl_FragColor = vec4(ring_color.rgb * ring_color.a, ring_color.a) * alpha * coverage;
}
