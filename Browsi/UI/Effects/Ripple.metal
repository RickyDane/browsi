#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Water-impact ripple with chromatic split and lit crests.
/// A ring travels outward from `origin` at `speed` px/s; each pixel oscillates once the ring reaches it
/// and decays exponentially.
[[ stitchable ]] half4 browsiRipple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
                                   float amplitude, float frequency, float decay, float speed) {
    float2 delta = position - origin;
    float dist = length(delta);
    float t = max(0.0, time - dist / speed);
    float wave = sin(frequency * t) * exp(-decay * t);
    // Nothing moves before the front arrives.
    wave *= step(0.0001, time - dist / speed);
    float offset = amplitude * wave;
    float2 n = dist > 0.001 ? delta / dist : float2(0.0);
    float2 p = position + n * offset;

    float split = offset * 0.35;
    half4 c = layer.sample(p);
    c.r = layer.sample(p + n * split).r;
    c.b = layer.sample(p - n * split).b;
    // Brighten crests, darken troughs.
    c.rgb = clamp(c.rgb + half3(0.22 * wave) * c.a, half3(0.0), half3(1.0));
    return c;
}

/// Calm water ripple: slow, long waves roll outward from `origin` across the whole window.
/// Several crests follow the front, each softer than the last; everything settles by ~2.8 s.
[[ stitchable ]] half4 browsiCalmRipple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
                                       float amplitude, float wavelength, float speed) {
    float2 delta = position - origin;
    float dist = length(delta);
    float behind = time * speed - dist;                 // how long the wave has been at this pixel (px)
    if (behind <= 0.0) { return layer.sample(position); }
    float k = 6.2831853 / wavelength;
    float envelope = smoothstep(0.0, wavelength * 0.6, behind)   // soft leading edge
                   * exp(-behind / (wavelength * 3.2))           // trailing crests fade
                   * (1.0 - smoothstep(1.9, 2.9, time))          // whole effect settles
                   * (1.0 / (1.0 + dist / 900.0));               // weaker far away
    float wave = sin(k * behind) * envelope;
    float2 n = dist > 0.001 ? delta / dist : float2(0.0);
    float2 p = position + n * (amplitude * wave);
    half4 c = layer.sample(p);
    // A faint sheen on the crests only (no shading, so pages don't get grey bands).
    c.rgb = clamp(c.rgb + half3(0.035 * max(wave, 0.0)) * c.a, half3(0.0), half3(1.0));
    return c;
}
