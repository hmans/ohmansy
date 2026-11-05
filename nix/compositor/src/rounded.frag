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
uniform mat3 tex_matrix;
uniform float alpha;
uniform vec2 draw_origin;
uniform vec4 mask_rect;
uniform float radius;
varying vec2 v_coords;
#if defined(DEBUG_FLAGS)
uniform float tint;
#endif

//_COVERAGE_
void main() {
    // Recover destination pixel coordinates from the renderer's texture matrix.
    // This includes viewport crops, buffer transforms and inverted textures.
    vec2 uv = v_coords - tex_matrix[2].xy;
    float det = tex_matrix[0].x * tex_matrix[1].y - tex_matrix[1].x * tex_matrix[0].y;
    vec2 p = vec2(tex_matrix[1].y * uv.x - tex_matrix[1].x * uv.y,
                  -tex_matrix[0].y * uv.x + tex_matrix[0].x * uv.y) / det;
    p += draw_origin - mask_rect.xy;
    vec2 half_size = mask_rect.zw * 0.5;
    float coverage = rounded_coverage(p - half_size, half_size, radius, 1.0);
    vec4 color = texture2D(tex, v_coords);
#if defined(NO_ALPHA)
    color.a = 1.0;
#endif
    color *= alpha * coverage;
#if defined(DEBUG_FLAGS)
    if (tint == 1.0) color = vec4(0.0, 0.2, 0.0, 0.2) * coverage + color * 0.8;
#endif
    gl_FragColor = color;
}
