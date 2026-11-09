in vec3 world;
in vec3 normal;
in vec2 uv;
flat in int ribbon;
out vec4 fragColor;
void main() {
    vec3 n = normalize(normal);
    vec3 view = normalize(vec3(0, 0, 4.5) - world);
    if (dot(n, view) < 0.0) n = -n;
    vec3 light = desktopLight();
    float diffuse = max(dot(n, light), 0.0) * lightStrength;
    float specular = pow(max(dot(n, normalize(light + view)), 0.0), 60.0) * lightStrength;
    float fresnel = pow(1.0 - max(dot(n, view), 0.0), 3.0);
    vec3 palette[3] = vec3[3](ribbon_atmosphere, ribbon_accent, ribbon_companion);
    vec3 dayPalette[3] = vec3[3](ribbon_atmosphere_light, ribbon_accent_light, ribbon_companion_light);
    vec3 tint = palette[ribbon];
    vec3 dayTint = dayPalette[ribbon];
    float silk = noise(vec2(uv.x * 12.0 + float(ribbon) * 7.0, uv.y * 0.7 + time * 0.06));
    float edge = smoothstep(0.91, 1.0, abs(uv.y));
    vec3 color = tint * (0.14 + diffuse * (0.30 + silk * 0.23) + fresnel * 0.18);
    color += sheen * specular * 0.34 + tint * edge * 0.27;
    // Light silk keeps shaded folds and a pearl rim instead of lifting exposure.
    vec3 dayColor = dayTint * (0.69 + diffuse * (0.23 + silk * 0.08));
    dayColor += sheen * (specular * 0.16 + fresnel * 0.09 + edge * 0.09);
    color = mix(color, dayColor, lightMix);
    color *= mix(vec3(1.0), lightHighlight, clamp(diffuse * 0.55, 0.0, 1.0));
    color = mix(color, lightShadow, clamp(max(-dot(n, light), 0.0) * lightStrength * 0.35, 0.0, 1.0));
    vec2 screenUV = vec2(gl_FragCoord.x, size.y - gl_FragCoord.y) / size;
    color *= 1.0 - mix(0.38, 0.055, lightMix) * smoothstep(0.30, 0.73, length(screenUV - 0.5));
    float alpha = mix(0.63 + edge * 0.20 + fresnel * 0.12, 0.84 + edge * 0.08 + fresnel * 0.06, lightMix);
    fragColor = vec4(color, alpha);
}
