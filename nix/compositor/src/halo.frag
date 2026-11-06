#version 100
//_DEFINES_
precision highp float;
uniform sampler2D tex;
uniform float alpha;
uniform vec2 blur_step;
uniform vec2 window_ratio;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif
void main() {
    // A small Gaussian kernel over a reduced image removes readable details.
    vec4 color = vec4(0.0);
    float total = 0.0;
    for (int y = -4; y <= 4; y++) {
        for (int x = -4; x <= 4; x++) {
            vec2 tap = vec2(float(x), float(y));
            float weight = exp(-dot(tap, tap) / 8.0);
            color += texture2D(tex, clamp(v_coords + tap * blur_step * 0.5, 0.0, 1.0)) * weight;
            total += weight;
        }
    }
    vec2 distance = max((abs(v_coords - 0.5) * 2.0 - window_ratio) / (1.0 - window_ratio), 0.0);
    float fade = 1.0 - smoothstep(0.0, 1.0, length(distance));
    gl_FragColor = color * (alpha * fade / total);
}
