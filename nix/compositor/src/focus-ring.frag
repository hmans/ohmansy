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
//_COVERAGE_
void main() {
    vec2 p = v_coords * size + piece_offset - full_size * 0.5;
    float outer = rounded_coverage(p, full_size * 0.5, radius + thickness, 2.0 * feather);
    float inner = rounded_coverage(p, max(full_size * 0.5 - thickness, vec2(0.0)), radius, 2.0 * feather);
    float coverage = max(outer - inner, 0.0);
    gl_FragColor = vec4(ring_color.rgb * ring_color.a, ring_color.a) * alpha * coverage;
}
