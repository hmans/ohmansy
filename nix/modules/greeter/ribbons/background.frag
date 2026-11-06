out vec4 fragColor;
void main() {
    vec2 pixel = vec2(gl_FragCoord.x, size.y - gl_FragCoord.y);
    vec2 uv = pixel / size;
    float aspect = size.x / size.y;
    float t = time;
    vec2 p = (uv - 0.5) * vec2(aspect, 1);
    vec3 top = mix(vec3(0.065, 0.077, 0.12), vec3(0.80, 0.83, 0.89), lightMix);
    vec3 bottom = mix(vec3(0.12, 0.15, 0.20), vec3(0.70, 0.76, 0.85), lightMix);
    vec3 color = mix(top, bottom, uv.y);
    vec2 lamp = vec2(0.5) + lightDirection * 0.45;
    float glow = exp(-dot((uv - lamp) * vec2(aspect, 1.0), (uv - lamp) * vec2(aspect, 1.0)) * 2.0);
    color += lightHighlight * glow * lightStrength * mix(0.035, 0.05, lightMix);
    color = mix(color, lightShadow, (1.0 - glow) * min(lightStrength * 0.06, 0.3));
    float haze = noise(vec2(uv.x * 2.3 + t * 0.018, uv.y * 1.7 - t * 0.012));
    color += haze * mix(vec3(0.025, 0.035, 0.06), vec3(0.02, 0.015, 0.025), lightMix);
    float quiet = 1.0 - 0.55 * exp(-dot(p * vec2(3.2, 5), p * vec2(3.2, 5)));
    float proximity = 0.0;
    for (int ribbon = 0; ribbon < 3; ribbon++) {
        float depthScale = (4.5 - ribbonDepth(ribbon)) / 4.5;
        float s = 0.5 + p.x * 9.0 / (2.3 * 13.0);
        vec3 center = ribbonCenter(s, t, float(ribbon));
        s = 0.5 + p.x * 2.0 * (4.5 - center.z) / (2.3 * 13.0 * depthScale);
        center = ribbonCenter(s, t, float(ribbon));
        float screenY = 0.5 - center.y * 2.3 / (2.0 * (4.5 - center.z));
        float distance = (uv.y - screenY) / 0.085;
        proximity = max(proximity, exp(-distance * distance));
    }
    // Even summing all 27 particles at their maximum intensity, this cutoff
    // omits less than one 8-bit color step. Keep shading the haze/background.
    if (proximity >= 0.0001) {
        for (int layer = 0; layer < 3; ++layer) {
            // Drop the smallest, faintest particles first. Retained layers keep
            // their original sizes, positions, colors and animation phases.
            if (layer < 3 - particleLayers) continue;
            float depth = float(layer) / 2.0;
            float density = mix(9.0, 3.8, depth);
            vec2 field = p * density;
            vec2 cell = floor(field);
            for (int iy = -1; iy <= 1; ++iy) {
                for (int ix = -1; ix <= 1; ++ix) {
                    vec2 id = cell + vec2(ix, iy);
                    float seed = hash(id + float(layer) * 73.19);
                    vec2 offset = vec2(hash(id + 2.7 + float(layer) * 31.0), hash(id + 5.3 + float(layer) * 61.0));
                    offset += turbulence(id + float(layer) * 19.37, t * (0.8 + depth * 0.5) + seed * 3.0);
                    vec2 delta = (field - id - offset) / density;
                    float radius = mix(0.00065, 0.0038, depth) * (0.65 + seed);
                    float distance = length(delta);
                    float core = 1.0 - smoothstep(radius * 0.15, radius + 1.0 / size.y, distance);
                    float halo = exp(-distance / (radius * 2.5)) * (0.08 + depth * 0.12);
                    float shimmer = 0.55 + 0.45 * pow(0.5 + 0.5 * sin(t * (0.5 + seed) + seed * 59.0), 2.0);
                    vec3 tint = mix(vec3(0.35, 0.65, 0.84), vec3(0.72, 0.57, 0.91), seed);
                    color += tint * (core + halo) * (0.16 + depth * 0.28) * shimmer * quiet * proximity * mix(1.0, 0.35, lightMix);
                }
            }
        }
    }
    float vignette = 1.0 - mix(0.38, 0.055, lightMix) * smoothstep(0.30, 0.73, length(uv - 0.5));
    fragColor = vec4(color * vignette + (hash(pixel) - 0.5) / 255.0, 1);
}
