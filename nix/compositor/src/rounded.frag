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
uniform vec4 outer_rect;
uniform float outer_radius;
uniform float saturation;
uniform float fog;
uniform vec3 fog_color;
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
    vec2 outer_p = p + mask_rect.xy - outer_rect.xy;
    coverage = min(coverage, rounded_coverage(outer_p - outer_rect.zw * 0.5, outer_rect.zw * 0.5, outer_radius, 1.0));
    vec4 color = texture2D(tex, v_coords);
#if defined(NO_ALPHA)
    color.a = 1.0;
#endif
    float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(vec3(luma), color.rgb, saturation);
    // Textures use premultiplied alpha: preserve translucent client content.
    color.rgb = mix(color.rgb, fog_color * color.a, fog);
    color *= alpha * coverage;
#if defined(DEBUG_FLAGS)
    if (tint == 1.0) color = vec4(0.0, 0.2, 0.0, 0.2) * coverage + color * 0.8;
#endif
    gl_FragColor = color;
}
