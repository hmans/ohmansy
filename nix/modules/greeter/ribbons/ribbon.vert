invariant gl_Position;
out vec3 world;
out vec3 normal;
out vec2 uv;
flat out int ribbon;
void main() {
    int quad = gl_VertexID / 6;
    const vec2 corner[6] = vec2[6](vec2(0, 0), vec2(1, 0), vec2(0, 1),
                                 vec2(1, 0), vec2(1, 1), vec2(0, 1));
    vec2 grid = vec2(quad / 12, quad % 12) + corner[gl_VertexID % 6];
    float s = grid.x / 256.0, v = grid.y / 12.0 * 2.0 - 1.0;
    vec3 point = ribbonPoint(s, v, time, ribbonId);
    vec3 tangent = ribbonPoint(s + 0.0005, v, time, ribbonId) - ribbonPoint(s - 0.0005, v, time, ribbonId);
    vec3 side = ribbonPoint(s, v + 0.001, time, ribbonId) - ribbonPoint(s, v - 0.001, time, ribbonId);
    float depth = 4.5 - point.z;
    float aspect = size.x / size.y;
    // Convert Metal's [0,w] clip depth to OpenGL's [-w,w].
    gl_Position = vec4(point.x * 2.3 / aspect, point.y * 2.3,
                       2.0 * (depth * (20.0 / 19.9) - 2.0 / 19.9) - depth, depth);
    world = point;
    normal = normalize(cross(tangent, side));
    uv = vec2(s, v);
    ribbon = ribbonId;
}
