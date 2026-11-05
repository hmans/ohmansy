// Integrate a rounded edge over a physical pixel, rather than sharpening a
// single distance sample. Only edge pixels need the extra samples.
float rounded_distance(vec2 p, vec2 half_size, float r) {
    vec2 q = abs(p) - half_size + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float rounded_coverage(vec2 p, vec2 half_size, float r, float pixel_size) {
    r = min(r, min(half_size.x, half_size.y));
    float distance = rounded_distance(p, half_size, r);
    if (abs(distance) >= pixel_size * 0.75)
        return step(distance, 0.0);
    // Straight edges have exact box coverage without supersampling.
    vec2 corner = abs(p) - half_size + r;
    if (min(corner.x, corner.y) <= -pixel_size * 0.5)
        return clamp(0.5 - distance / pixel_size, 0.0, 1.0);
    float coverage = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec2 offset = (vec2(float(x), float(y)) * 0.25 - 0.375) * pixel_size;
            float d = rounded_distance(p + offset, half_size, r);
            coverage += clamp(0.5 - d / (pixel_size * 0.25), 0.0, 1.0);
        }
    }
    return coverage / 16.0;
}
