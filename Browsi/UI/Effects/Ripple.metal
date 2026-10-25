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
