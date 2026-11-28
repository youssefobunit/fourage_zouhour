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

    float sideMix = smoothstep(-3.0, 3.0, q.x - q.y);
    vec2 faceNormal = vec2(sign(p.x) * sideMix, sign(p.y) * (1.0 - sideMix));
    vec2 corner = max(q, 0.0) * sign(p);
    float cornerLength = length(corner);
    vec2 normal = mix(faceNormal, corner / max(cornerLength, 0.001), smoothstep(0.0, 2.5, cornerLength));
    float bevel = min(min(halfSize.x, halfSize.y) * 0.86, 42.0);
    float edge = 1.0 - smoothstep(0.0, bevel, inside);
    float depth = uDepth * (1.0 + 0.43 * uPress);

    // Limit the slope of the bevel to keep the projected background from
    // folding back on itself as a line crosses the glass.
    float lift = bevel * min(depth * 0.53, 0.66);
    float lensEdge = 1.0 - clamp(inside / bevel, 0.0, 1.0);
    vec2 displacement = -normal * pow(lensEdge, 1.34) * lift;
    vec2 scene = uOrigin + pixel + displacement;

    float dispersion = pow(lensEdge, 2.6) * 0.25 * depth;
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
    vec3 nightBase = vec3(0.15, 0.025, 0.23);
    vec3 glassBase = mix(lightBase, nightBase, uDark);
    vec3 tint = mix(glassBase, uTint, 0.06 + 0.24 * uPress);
    vec3 color = mix(refracted, tint, mix(0.35, 0.06, edge));
    vec3 reflection = mix(
        mix(vec3(0.94, 0.99, 1.0), vec3(0.98, 0.72, 1.0), uDark),
        uTint,
        0.28
    );
    float polish = clamp(0.65 + depth * 0.25, 0.65, 1.10);
    color = mix(color, vec3(0.32, 0.65, 0.87), (1.0 - uDark) * rim * (0.14 + 0.15 * (1.0 - glints)));
    color += reflection * polish * bloom * (0.05 + (0.41 + 0.16 * uPress) * pow(glints, 2.25));
    color += mix(vec3(0.94, 0.99, 1.0), vec3(1.0, 0.72, 1.0), uDark) * rim * (0.13 + 0.37 * glints);
    float caustic = exp(-abs(inside - (2.2 + 2.9 * glints)) * 0.53);
    color += mix(vec3(0.28, 0.68, 1.0), vec3(0.86, 0.18, 1.0), uDark) * caustic * pow(glints, 3.5) * 0.13;
    float alpha = coverage * uOpacity;
    fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
}
