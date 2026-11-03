in vec3 world;
in vec3 normal;
in vec2 uv;
flat in int ribbon;
out vec4 fragColor;
void main() {
    vec3 n = normalize(normal);
    vec3 view = normalize(vec3(0, 0, 4.5) - world);
    if (dot(n, view) < 0.0) n = -n;
    vec3 light = normalize(vec3(-0.4, 0.8, 1.4));
    float diffuse = max(dot(n, light), 0.0);
    float specular = pow(max(dot(n, normalize(light + view)), 0.0), 60.0);
    float fresnel = pow(1.0 - max(dot(n, view), 0.0), 3.0);
    const vec3 palette[3] = vec3[3](vec3(0.20, 0.50, 0.83), vec3(0.47, 0.26, 0.69), vec3(0.12, 0.57, 0.57));
    const vec3 dayPalette[3] = vec3[3](vec3(0.53, 0.73, 0.90), vec3(0.77, 0.64, 0.87), vec3(0.49, 0.76, 0.73));
    vec3 tint = mix(palette[ribbon], palette[(ribbon + 1) % 3], uv.x);
    vec3 dayTint = mix(dayPalette[ribbon], dayPalette[(ribbon + 1) % 3], uv.x);
    float silk = noise(vec2(uv.x * 12.0 + float(ribbon) * 7.0, uv.y * 0.7 + time * 0.06));
    tint = mix(tint, tint.brg, 0.22 * silk);
    dayTint = mix(dayTint, dayTint.brg, 0.10 * silk);
    float edge = smoothstep(0.91, 1.0, abs(uv.y));
    vec3 color = tint * (0.14 + diffuse * (0.30 + silk * 0.23) + fresnel * 0.18);
    color += vec3(0.56, 0.72, 0.86) * specular * 0.34 + tint * edge * 0.27;
    // Light silk keeps shaded folds and a pearl rim instead of lifting exposure.
    vec3 dayColor = dayTint * (0.69 + diffuse * (0.23 + silk * 0.08));
    dayColor += vec3(0.94, 0.96, 1.0) * (specular * 0.16 + fresnel * 0.09 + edge * 0.09);
    color = mix(color, dayColor, lightMix);
    vec2 screenUV = vec2(gl_FragCoord.x, size.y - gl_FragCoord.y) / size;
    color *= 1.0 - mix(0.38, 0.055, lightMix) * smoothstep(0.30, 0.73, length(screenUV - 0.5));
    float alpha = mix(0.63 + edge * 0.20 + fresnel * 0.12, 0.84 + edge * 0.08 + fresnel * 0.06, lightMix);
    fragColor = vec4(color, alpha);
}
