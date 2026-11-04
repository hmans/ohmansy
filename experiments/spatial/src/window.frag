precision highp float;
uniform sampler2D image;
uniform float selected;
uniform float aspect;
in vec2 uv;
out vec4 color;

void main() {
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    float radius = 0.018;
    vec2 q = abs(p) - vec2(aspect * 0.5, 0.5) + radius;
    float edge = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float aa = max(fwidth(edge), 0.0001);
    float coverage = 1.0 - smoothstep(-aa, aa, edge);
    vec4 pixel = texture(image, uv);
    float rim = smoothstep(-0.004 - aa, -0.004 + aa, edge);
    vec3 border = mix(vec3(0.31, 0.33, 0.40), vec3(0.68, 0.57, 0.80), selected);
    color = vec4(mix(pixel.rgb, border, rim), pixel.a * coverage);
    color.rgb *= color.a;
}
