#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float pgHash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

/// Wave band brightness at radius `r`: the arrival wave, plus (after release) the clearing wave.
static float pgBand(float r, float t, float release, float speed) {
    float x = (r - t * speed) / 105.0;
    float a = exp(-x * x) * 0.85;
    if (t > release) { float y = (r - (t - release) * speed * 1.4) / 105.0; a += exp(-y * y) * 0.55; }
    return a;
}

/// Passkey sign-in "cipher grid" overlay (drawn over the live window; returns premultiplied colour).
/// - A calm wave travels out from `origin`; cells inside it show tiny flickering 3×3 cipher dots.
/// - Behind the wave a fine, softly breathing grid stays until `release` (seconds after start).
/// - From `release`, a softer wave clears the grid outward; everything is gone `fadeOut` s later.
[[ stitchable ]] half4 browsiPasskeyGrid(float2 position, half4 color, float2 origin, float time, float release,
                                        float speed, float fadeOut, float3 tint) {
    float t = time;
    float r = length(position - origin);
    float env = (1.0 - smoothstep(release + fadeOut - 1.2, release + fadeOut, t)) * smoothstep(0.0, 0.3, t);
    if (env <= 0.0) { return half4(0.0); }

    // Cipher cells inside the wave.
    float s = 12.0;
    float2 id = floor(position / s);
    float2 c = (id + 0.5) * s;
    float a = clamp(pgBand(length(c - origin), t, release, speed), 0.0, 1.0) * env;
    float m = smoothstep(0.15, 0.6, a);
    float2 lp = fract(position / s) * 3.0;
    float2 sub = floor(lp);
    float tick = floor(t * (1.5 + 3.0 * a) + pgHash(id) * 10.0);
    float bit = step(0.45, pgHash(id * 1.31 + sub * 7.17 + tick));
    float dotMask = 1.0 - smoothstep(0.26, 0.36, length(fract(lp) - 0.5));
    float cipher = bit * dotMask * m * 0.6 + m * 0.03;

    // Calm holding grid: laid down by the arrival wave, removed by the release wave.
    float on = smoothstep(0.0, 160.0, t * speed - r);
    float off = t > release ? smoothstep(0.0, 160.0, (t - release) * speed * 1.4 - r) : 0.0;
    float h = on * (1.0 - off) * env;
    float g = 5.0;
    float2 f = abs(fract(position / g) - 0.5) * g;
    float edge = 1.0 - smoothstep(0.0, 0.9, g * 0.5 - max(f.x, f.y));
    float breathe = 0.5 + 0.5 * sin(t * 1.3 + pgHash(floor(position / 20.0)) * 6.2831853);
    float hold = h * (edge * 0.16 + 0.02 + 0.03 * breathe);

    // Compose: a tinted glow only (no dimming: the overlay can't see whether the page below is light or dark).
    float3 cipherColor = mix(tint, float3(1.0), 0.2);
    float glow = clamp(cipher + hold, 0.0, 1.0);
    float3 glowColor = (cipherColor * cipher + tint * hold) / max(cipher + hold, 1e-4);
    return half4(half3(glowColor * glow), half(glow));
}
