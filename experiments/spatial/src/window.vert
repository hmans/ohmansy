precision highp float;
uniform mat4 transform;
out vec2 uv;

void main() {
    const vec2 corners[6] = vec2[6](
        vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5),
        vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5)
    );
    vec2 p = corners[gl_VertexID];
    uv = vec2(p.x + 0.5, 0.5 - p.y);
    gl_Position = transform * vec4(p, 0.0, 1.0);
}
