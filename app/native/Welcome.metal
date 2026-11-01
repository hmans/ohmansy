#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; };
struct Uniforms { float2 size; float time; float padding; };

vertex Vertex welcomeVertex(uint id [[vertex_id]]) {
    const float2 points[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    return {float4(points[id], 0, 1)};
}

float hash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise(float2 p) {
    float2 cell = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + float2(1, 0)), f.x),
               mix(hash(cell + float2(0, 1)), hash(cell + 1), f.x), f.y);
}

float2 turbulence(float2 p, float t) {
    // Curl of an evolving scalar noise field: neighbouring particles follow
    // eddies, while the finer octave breaks up any uniform directional drift.
    float2 q = p * 0.63 + float2(t * 0.11, -t * 0.07);
    const float e = 0.12;
    float dx = noise(q + float2(e, 0)) - noise(q - float2(e, 0));
    float dy = noise(q + float2(0, e)) - noise(q - float2(0, e));
    float2 curl = float2(dy, -dx) / (2 * e);
    float2 fine = float2(noise(p * 1.7 + float2(t * 0.19, 7.3)),
                         noise(p.yx * 1.9 + float2(-t * 0.16, 29.1))) * 2 - 1;
    return tanh(curl) * 0.46 + fine * 0.24;
}

float3 ribbonCenter(float s, float t, float id);
float ribbonDepth(uint id) {
    const float depths[] = {-6.0, 0.0, 1.8};
    return depths[id];
}

fragment float4 welcomeFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.position.xy / u.size;
    float aspect = u.size.x / u.size.y;
    float t = u.time;
    float2 p = (uv - 0.5) * float2(aspect, 1);
    float3 color = mix(float3(0.065, 0.077, 0.12), float3(0.12, 0.15, 0.20), uv.y);
    // Broad atmospheric light, without isolated hot spots.
    float haze = noise(float2(uv.x * 2.3 + t * 0.018, uv.y * 1.7 - t * 0.012));
    color += haze * float3(0.025, 0.035, 0.06);
    float quiet = 1.0 - 0.55 * exp(-dot(p * float2(3.2, 5), p * float2(3.2, 5)));
    // Locate the projected ribbon paths, refining x for their perspective depth.
    float proximity = 0;
    for (int ribbon = 0; ribbon < 3; ribbon++) {
        float depthScale = (4.5 - ribbonDepth(uint(ribbon))) / 4.5;
        float s = 0.5 + p.x * 9.0 / (2.3 * 13.0);
        float3 center = ribbonCenter(s, t, float(ribbon));
        s = 0.5 + p.x * 2.0 * (4.5 - center.z) / (2.3 * 13.0 * depthScale);
        center = ribbonCenter(s, t, float(ribbon));
        float screenY = 0.5 - center.y * 2.3 / (2.0 * (4.5 - center.z));
        float distance = (uv.y - screenY) / 0.085;
        proximity = max(proximity, exp(-distance * distance));
    }
    // Spatial cells give us hundreds of sparks at a fixed 27 local checks per
    // pixel, rather than testing every particle across the entire framebuffer.
    for (int layer = 0; layer < 3; ++layer) {
        float depth = float(layer) / 2.0;
        float density = mix(9.0, 3.8, depth);
        float2 field = p * density;
        float2 cell = floor(field);
        for (int iy = -1; iy <= 1; ++iy) {
            for (int ix = -1; ix <= 1; ++ix) {
                float2 id = cell + float2(ix, iy);
                float seed = hash(id + float(layer) * 73.19);
                float2 offset = float2(hash(id + 2.7 + layer * 31.0), hash(id + 5.3 + layer * 61.0));
                offset += turbulence(id + float(layer) * 19.37, t * (0.8 + depth * 0.5) + seed * 3);
                float2 delta = (field - id - offset) / density;
                float radius = mix(0.00065, 0.0038, depth) * (0.65 + seed);
                float distance = length(delta);
                float core = 1.0 - smoothstep(radius * 0.15, radius + 1.0 / u.size.y, distance);
                float halo = exp(-distance / (radius * 2.5)) * (0.08 + depth * 0.12);
                float shimmer = 0.55 + 0.45 * pow(0.5 + 0.5 * sin(t * (0.5 + seed) + seed * 59), 2.0);
                float3 tint = mix(float3(0.35, 0.65, 0.84), float3(0.72, 0.57, 0.91), seed);
                color += tint * (core + halo) * (0.16 + depth * 0.28) * shimmer * quiet * proximity;
            }
        }
    }
    float vignette = 1.0 - 0.38 * smoothstep(0.30, 0.73, length(uv - 0.5));
    return float4(color * vignette + (hash(in.position.xy) - 0.5) / 255.0, 1);
}

struct RibbonVertex {
    float4 position [[position, invariant]];
    float3 world;
    float3 normal;
    float2 uv;
    uint ribbon [[flat]];
};

float3 ribbonCenter(float s, float t, float id) {
    float phase = id * 2.1;
    float x = (s - 0.5) * 13.0;
    float y = -0.78 + (0.30 + id * 0.13) * sin(s * (4.1 + id * 1.7) + t * 0.14 + phase)
              + 0.22 * sin(s * 3.7 - t * 0.1 + phase);
    y += 0.65 * (noise(float2(s * 3.5 + phase, t * 0.065)) - 0.5);
    y += 0.12 * (noise(float2(s * 9.0 + id * 17, t * 0.09)) - 0.5);
    // Separate depth envelopes, including the full width of each twisted mesh.
    // Keep motion within its envelope so transparency has a stable draw order.
    float baseZ = ribbonDepth(uint(id));
    float z = baseZ + 0.12 * sin(s * (4.3 + id) - t * 0.13 + phase);
    z += 0.12 * (noise(float2(s * 3.1 + id * 11, t * 0.07)) - 0.5);
    float depthScale = (4.5 - baseZ) / 4.5;
    return float3(x * depthScale, y * depthScale, z);
}
float3 ribbonPoint(float s, float v, float t, uint id) {
    float3 center = ribbonCenter(s, t, float(id));
    float3 tangent = normalize(ribbonCenter(s + 0.001, t, float(id)) - center);
    float3 up = normalize(cross(float3(0, 0, 1), tangent));
    float3 front = normalize(cross(tangent, up));
    float roll = s * (3.0 + id * 2.3) - t * (0.12 + id * 0.035) + float(id) * 1.7;
    roll += 2.8 * (noise(float2(s * 4.0 + id * 13, t * 0.08)) - 0.5);
    float3 side = up * cos(roll) + front * sin(roll);
    const float widths[] = {1.40, 0.52, 0.27};
    float width = widths[id] * (0.28 + 1.25 * noise(float2(s * 5.0 + id * 23, t * 0.055)));
    width *= (4.5 - ribbonDepth(id)) / 4.5;
    // A shallow curved cross-section catches light across the fabric.
    float3 offset = side * v * width + cross(tangent, side) * (1 - v * v) * width * 0.22;
    // The broad rear ribbon spans the scene without entering the nearer layers.
    if (id == 0) offset.z *= 0.30;
    return center + offset;
}
vertex RibbonVertex ribbonVertex(uint vertexID [[vertex_id]],
                                 constant Uniforms &u [[buffer(0)]],
                                 constant uint &id [[buffer(1)]]) {
    const uint across = 12;
    uint quad = vertexID / 6;
    const float2 corner[] = {float2(0, 0), float2(1, 0), float2(0, 1),
                             float2(1, 0), float2(1, 1), float2(0, 1)};
    float2 grid = float2(quad / across, quad % across) + corner[vertexID % 6];
    float s = grid.x / 256.0, v = grid.y / float(across) * 2 - 1;
    float3 point = ribbonPoint(s, v, u.time, id);
    float3 tangent = ribbonPoint(s + 0.0005, v, u.time, id) - ribbonPoint(s - 0.0005, v, u.time, id);
    float3 side = ribbonPoint(s, v + 0.001, u.time, id) - ribbonPoint(s, v - 0.001, u.time, id);
    float depth = 4.5 - point.z;
    float aspect = u.size.x / u.size.y;
    float4 clip = float4(point.x * 2.3 / aspect, point.y * 2.3,
                         depth * (20.0 / 19.9) - 2.0 / 19.9, depth);
    return {clip, point, normalize(cross(tangent, side)), float2(s, v), id};
}
fragment float4 ribbonFragment(RibbonVertex in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float3 n = normalize(in.normal);
    float3 view = normalize(float3(0, 0, 4.5) - in.world);
    if (dot(n, view) < 0) n = -n;
    float3 light = normalize(float3(-0.4, 0.8, 1.4));
    float diffuse = max(dot(n, light), 0.0);
    float specular = pow(max(dot(n, normalize(light + view)), 0.0), 60.0);
    float fresnel = pow(1.0 - max(dot(n, view), 0.0), 3.0);
    const float3 palette[] = {float3(0.20, 0.50, 0.83), float3(0.47, 0.26, 0.69), float3(0.12, 0.57, 0.57)};
    float3 tint = mix(palette[in.ribbon], palette[(in.ribbon + 1) % 3], in.uv.x);
    float silk = noise(float2(in.uv.x * 12.0 + in.ribbon * 7, in.uv.y * 0.7 + u.time * 0.06));
    tint = mix(tint, tint.brg, 0.22 * silk);
    float edge = smoothstep(0.91, 1.0, abs(in.uv.y));
    float3 color = tint * (0.14 + diffuse * (0.30 + silk * 0.23) + fresnel * 0.18);
    color += float3(0.56, 0.72, 0.86) * specular * 0.34 + tint * edge * 0.27;
    float2 screenUV = in.position.xy / u.size;
    color *= 1.0 - 0.38 * smoothstep(0.30, 0.73, length(screenUV - 0.5));
    float alpha = 0.63 + edge * 0.20 + fresnel * 0.12;
    return float4(color, alpha);
}
