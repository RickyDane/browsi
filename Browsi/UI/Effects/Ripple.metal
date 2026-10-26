#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float pgHash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

static float pgFade(float t, float release, float duration) {
    return 1.0 - smoothstep(0.0, duration, t - release);
}

/// White 3×3 cipher dots and a 5pt grid; stationary after entry, with a simple fade on dismissal.
[[ stitchable ]] half4 browsiPasskeyGrid(float2 position, half4 color, float2 size, float2 origin,
                                        float time, float release, float fadeOut, float dotOpacity, float darkening) {
    float arrival = length(position - origin) * 2.0 / max(size.y, 1.0) / 1.15;
    float t = max(0.0, time - 0.4);
    float reveal = smoothstep(0.0, 0.4, t - arrival);
    float env = smoothstep(0.4, 0.8, time) * pgFade(time, release, fadeOut);
    if (env * reveal <= 0.0) { return half4(0.0); }

    float2 id = floor(position / 12.0);
    float2 lp = fract(position / 12.0) * 3.0;
    float2 sub = floor(lp);
    // Freeze each cell's pattern after the front passes: no continuous flickering while waiting.
    float tick = floor(min(t, arrival + 0.9) * 3.0 + pgHash(id) * 10.0);
    float bit = step(0.45, pgHash(id * 1.31 + sub * 7.17 + tick));
    float dotMask = 1.0 - smoothstep(0.26, 0.36, length(fract(lp) - 0.5));
    float2 fine = abs(fract(position / 5.0) - 0.5) * 5.0;
    float edge = 1.0 - smoothstep(0.0, 0.9, 2.5 - max(fine.x, fine.y));
    float front = exp(-pow((t - arrival - 0.2) / 0.26, 2.0));
    float ink = min(1.0, bit * dotMask * (0.55 + 0.4 * front) + edge * 0.10);
    float dots = ink * reveal * env * dotOpacity;
    float dim = reveal * env * darkening;
    float alpha = dim + dots * (1.0 - dim);
    float3 rgb = float3(0.045, 0.055, 0.085) * dim * (1.0 - dots) + float3(dots);
    return half4(half3(rgb), half(alpha));
}

/// A single local impulse. The source recovers after 1.1 age units, independently of the front.
static float3 pgSurface(float2 position, float2 size, float2 origin, float time, float depth) {
    float height = max(size.y, 1.0);
    float2 p = (position - size * 0.5) * float2(2.0, -2.0) / height;
    float2 q = (position - origin) * float2(2.0, -2.0) / height;
    float local = time - length(q) / 1.15;
    float pulse = smoothstep(0.0, 0.19, local) * (1.0 - smoothstep(0.34, 1.10, local));
    float x = (local - 0.12) / 0.13;
    float crest = exp(-x*x) * (1.0 - smoothstep(2.0, 3.0, abs(x)))
        * smoothstep(0.0, 0.055, local) * smoothstep(0.0, 0.18, time);
    float basin = exp(-dot(q, q) * 0.64);
    float amount = depth / 0.75;
    p -= q * (0.13 * amount * pulse * basin);
    float z = amount * (-0.98 * pulse * basin + 0.14 * crest);
    p /= 1.0 - z * 0.38;
    p.y += z * 0.17;
    return float3(size * 0.5 + p * float2(height * 0.5, -height * 0.5), z);
}

/// Warp only SwiftUI snapshot/grid pixels, never a live WKWebView or an authentication dialog.
[[ stitchable ]] half4 browsiPasskeyWarp(float2 position, SwiftUI::Layer layer, float2 size, float2 origin,
                                        float time, float release, float fadeOut, float depth) {
    float amount = depth * pgFade(time, release, fadeOut);
    float2 source = position;
    // Invert the shallow perspective projection; at 10% depth this converges rapidly.
    for (int i = 0; i < 4; ++i) {
        source += position - pgSurface(source, size, origin, time, amount).xy;
    }
    half4 color = layer.sample(source);
    float h = max(size.y, 1.0);
    float z = pgSurface(source, size, origin, time, amount).z;
    float dx = (pgSurface(source + float2(h*0.0005, 0), size, origin, time, amount).z - z) / 0.001;
    float dy = (pgSurface(source - float2(0, h*0.0005), size, origin, time, amount).z - z) / 0.001;
    float3 normal = normalize(float3(-dx, -dy, 1.0));
    float3 light = normalize(float3(-0.4, 0.6, 1.0));
    color.rgb *= half(clamp(1.0 + 0.3 * (dot(normal, light) - light.z), 0.5, 1.16));
    return color;
}
