// GLSL translation of app/native/Welcome.metal; keep constants and motion in sync.
uniform vec2 size;
uniform float time;
uniform float lightMix;
uniform vec2 lightDirection;
uniform float lightStrength;
uniform vec3 lightHighlight;
uniform vec3 lightShadow;

vec3 desktopLight() {
    // Wallpaper world y points up; theme coordinates point down.
    return normalize(vec3(lightDirection.x, -lightDirection.y,
        sqrt(max(0.0, 1.0 - dot(lightDirection, lightDirection))) + 0.001));
}
uniform int ribbonId;
uniform int particleLayers;
uniform float particleMotionDetail;

float hash(vec2 p) {
    vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
    vec2 cell = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x),
               mix(hash(cell + vec2(0, 1)), hash(cell + 1.0), f.x), f.y);
}
vec2 turbulence(vec2 p, float t) {
    vec2 curlMotion = vec2(0);
    // Uniform branching skips four noise samples at the lowest motion detail.
    if (particleMotionDetail > 0.0) {
        vec2 q = p * 0.63 + vec2(t * 0.11, -t * 0.07);
        const float e = 0.12;
        float dx = noise(q + vec2(e, 0)) - noise(q - vec2(e, 0));
        float dy = noise(q + vec2(0, e)) - noise(q - vec2(0, e));
        vec2 curl = vec2(dy, -dx) / (2.0 * e);
        curlMotion = tanh(curl) * 0.46 * particleMotionDetail;
    }
    vec2 fine = vec2(noise(p * 1.7 + vec2(t * 0.19, 7.3)),
                     noise(p.yx * 1.9 + vec2(-t * 0.16, 29.1))) * 2.0 - 1.0;
    return curlMotion + fine * 0.24;
}
float ribbonDepth(int id) {
    const float depths[3] = float[3](-6.0, 0.0, 1.8);
    return depths[id];
}
vec3 ribbonCenter(float s, float t, float id) {
    float phase = id * 2.1;
    float x = (s - 0.5) * 13.0;
    float y = -0.78 + (0.30 + id * 0.13) * sin(s * (4.1 + id * 1.7) + t * 0.14 + phase)
              + 0.22 * sin(s * 3.7 - t * 0.1 + phase);
    y += 0.65 * (noise(vec2(s * 3.5 + phase, t * 0.065)) - 0.5);
    y += 0.12 * (noise(vec2(s * 9.0 + id * 17.0, t * 0.09)) - 0.5);
    float baseZ = ribbonDepth(int(id));
    float z = baseZ + 0.12 * sin(s * (4.3 + id) - t * 0.13 + phase);
    z += 0.12 * (noise(vec2(s * 3.1 + id * 11.0, t * 0.07)) - 0.5);
    float depthScale = (4.5 - baseZ) / 4.5;
    return vec3(x * depthScale, y * depthScale, z);
}
vec3 ribbonPoint(float s, float v, float t, int id, out vec3 across) {
    float f = float(id);
    vec3 center = ribbonCenter(s, t, f);
    vec3 tangent = normalize(ribbonCenter(s + 0.001, t, f) - center);
    vec3 up = normalize(cross(vec3(0, 0, 1), tangent));
    vec3 front = normalize(cross(tangent, up));
    float roll = s * (3.0 + f * 2.3) - t * (0.12 + f * 0.035) + f * 1.7;
    roll += 2.8 * (noise(vec2(s * 4.0 + f * 13.0, t * 0.08)) - 0.5);
    vec3 side = up * cos(roll) + front * sin(roll);
    const float widths[3] = float[3](1.40, 0.52, 0.27);
    float width = widths[id] * (0.28 + 1.25 * noise(vec2(s * 5.0 + f * 23.0, t * 0.055)));
    width *= (4.5 - ribbonDepth(id)) / 4.5;
    vec3 offset = side * v * width + cross(tangent, side) * (1.0 - v * v) * width * 0.22;
    // The cross-section is quadratic in v. Its derivative replaces two full
    // shape samples when calculating the normal, including the flattened fold.
    across = side * width - cross(tangent, side) * (2.0 * v) * width * 0.22;
    if (id == 0) {
        offset.z *= 0.30;
        across.z *= 0.30;
    }
    return center + offset;
}
vec3 ribbonPoint(float s, float v, float t, int id) {
    vec3 across;
    return ribbonPoint(s, v, t, id, across);
}
