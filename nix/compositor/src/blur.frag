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
uniform float alpha;
uniform vec2 axis;
uniform vec2 pixel_size;
uniform float reduction;
uniform vec4 sample_bounds;
varying vec2 v_coords;
vec4 sample_at(vec2 offset) {
    return texture2D(tex, clamp(v_coords + offset, sample_bounds.xy, sample_bounds.zw));
}
void main() {
    vec4 color = vec4(0.0);
    if (axis == vec2(0.0)) {
        // Average every source texel before reducing. A single linear sample
        // while shrinking would alias patterns back into a large-radius blur.
        if (reduction < 1.5) color = sample_at(vec2(0.0));
        else if (reduction < 2.5) {
            for (int y = 0; y < 2; y++)
                for (int x = 0; x < 2; x++)
                    color += sample_at((vec2(float(x), float(y)) - 0.5) * pixel_size) * 0.25;
        } else {
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++)
                    color += sample_at((vec2(float(x), float(y)) - 1.5) * pixel_size) / 16.0;
        }
    } else {
        float total = 0.0;
        for (int i = -16; i <= 16; i++) {
            float distance = float(i) * 3.0 / 16.0;
            float weight = exp(-0.5 * distance * distance);
            color += sample_at(axis * float(i)) * weight;
            total += weight;
        }
        color /= total;
    }
    gl_FragColor = color * alpha;
}
