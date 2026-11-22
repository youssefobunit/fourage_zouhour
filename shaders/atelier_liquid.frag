#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform vec2 uSceneSize;
uniform vec3 uTint;
uniform float uRadius;
uniform float uDepth;
uniform float uPress;
uniform float uOpacity;
uniform float uDark;
uniform sampler2D uScene;

out vec4 fragColor;

vec3 sampleScene(vec2 position) {
    return texture(uScene, clamp(position / uSceneSize, vec2(0.001), vec2(0.999))).rgb;
}

void main() {
    vec2 pixel = FlutterFragCoord().xy;
    vec2 halfSize = uSize * 0.5;
    vec2 p = pixel - halfSize;
    float radius = min(uRadius, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + radius;
    float signedDistance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float inside = -signedDistance;
    float coverage = smoothstep(-0.65, 0.65, inside);

    vec2 farEdge = q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
    vec2 corner = max(q, 0.0) * sign(p);
    vec2 normal = dot(corner, corner) > 0.00001 ? normalize(corner) : farEdge;
    float bevel = clamp(min(halfSize.x, halfSize.y) * 0.76, 10.0, 34.0);
    float edge = 1.0 - smoothstep(0.0, bevel, inside);
    float depth = uDepth * (1.0 + 0.43 * uPress);

    // Move samples inwards along the curved surface normal. A weak cross-wave
    // bends reflected bands through the centre of larger lenses.
    vec2 wave = vec2(sin(p.y * 0.045 + p.x * 0.025), cos(p.x * 0.036 - p.y * 0.043));
    vec2 displacement = (-normal * pow(edge, 1.7) * 25.0 + wave * (1.2 + edge * 2.6)) * depth;
    vec2 scene = uOrigin + pixel + displacement;

    float dispersion = pow(edge, 2.0) * 2.0 * depth;
    vec3 refracted;
    refracted.r = sampleScene(scene + normal * dispersion).r;
    refracted.g = sampleScene(scene).g;
    refracted.b = sampleScene(scene - normal * dispersion).b;

    // Grazing light blooms across the curved edge and falls off into the panel.
    float topLight = max(0.0, dot(normal, normalize(vec2(0.63 - 0.49 * uPress, -0.83))));
    float lowerLight = max(0.0, dot(normal, normalize(vec2(-0.70, 0.85))));
    vec2 uv = pixel / uSize;
    float glints = max(
        topLight * (0.32 + 0.68 * uv.x),
        lowerLight * (0.30 + 0.70 * (1.0 - uv.x))
    );
    float rim = 1.0 - smoothstep(0.15, 1.8, inside);
    float bloom = exp(-max(inside, 0.0) / max(3.0, 0.25 * bevel));
    vec3 lightBase = vec3(0.88, 0.96, 1.0);
    vec3 nightBase = vec3(0.22, 0.035, 0.32);
    vec3 glassBase = mix(lightBase, nightBase, uDark);
    vec3 tint = mix(glassBase, uTint, 0.06 + 0.24 * uPress);
    vec3 color = mix(refracted, tint, mix(0.48, 0.14, edge));
    vec3 reflection = mix(
        mix(vec3(0.94, 0.99, 1.0), vec3(0.98, 0.72, 1.0), uDark),
        uTint,
        0.28
    );
    color += reflection * bloom * (0.11 + (0.62 + 0.10 * uPress) * pow(glints, 1.95));
    color += mix(vec3(0.94, 0.99, 1.0), vec3(1.0, 0.72, 1.0), uDark) * rim * (0.12 + 0.31 * glints);
    float caustic = exp(-abs(inside - (2.2 + 2.9 * glints)) * 0.53);
    color += mix(vec3(0.28, 0.68, 1.0), vec3(0.86, 0.18, 1.0), uDark) * caustic * pow(glints, 3.5) * 0.18;
    float alpha = coverage * uOpacity;
    fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
}
