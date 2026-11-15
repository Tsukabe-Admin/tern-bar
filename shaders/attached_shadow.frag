#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 u_patchRect;   // (x, y, w, h) in target coordinate space
    vec4 u_attachRect;  // (cardX, cardTopY, cardW, cardH)
    vec4 u_attachRadii; // (effR, wingR, mode, 0.0) mode: 0=top, 1=bottom, 2=floating
    vec4 u_innerBox;    // (left, top, right, bottom) of inner frame cutout
    vec4 u_shadow;      // (keyOpacity, aoOpacity, sigma, aoSigma)
    vec4 u_geom;        // (innerR, offsetY, extent, 0.0)
    vec4 u_cut;         // (cutActive, cutLeft, cutRight, attachOpacity)
};

float gaussianEdge(float x) {
    if (x > 5.5) return 0.0;
    float ax = abs(x);
    float t = 1.0 / (1.0 + 0.3275911 * ax);
    float poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741
                 + t * (-1.453152027 + t * 1.061405429))));
    float erfcAbs = poly * exp(-ax * ax);
    float erfcVal = (x >= 0.0) ? erfcAbs : (2.0 - erfcAbs);
    return 0.5 * erfcVal;
}

float sdRoundedBox(vec2 p, vec4 box, float r) {
    vec2 center = 0.5 * (box.xy + box.zw);
    vec2 halfExt = 0.5 * (box.zw - box.xy);
    vec2 q = abs(p - center) - (halfExt - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdfCutout(vec2 p, vec4 box, float r, float omitTop) {
    vec4 eff = box;
    if (omitTop > 0.5) eff.y -= 256.0;
    return -sdRoundedBox(p, eff, r);
}

float sdfTopAttached(vec2 p, vec4 rect, float effR, float wingR) {
    float cx = rect.x + 0.5 * rect.z;
    float hx = 0.5 * rect.z;
    float barH = rect.y;
    float botY = rect.y + rect.w;
    float ax = abs(p.x - cx);
    float y = p.y;

    float dTop = y - barH;
    float bx = ax - (hx - effR);
    float by = y - (botY - effR);
    float dDrawer = (bx > 0.0 && by > 0.0)
        ? (length(vec2(bx, by)) - effR)
        : max(ax - hx, y - botY);

    if (wingR < 2.0) {
        return min(dTop, dDrawer);
    }
    if (ax >= hx + wingR || y >= barH + wingR) {
        return min(dTop, dDrawer);
    }
    vec2 c = vec2(hx + wingR, barH + wingR);
    float dArc = wingR - length(c - vec2(ax, y));
    if (ax < hx) {
        return max(dArc, y - botY);
    }
    return dArc;
}

float computeShadow(float d, float dShift) {
    if (d <= 0.0) return 0.0;
    float keyOp = u_shadow.x;
    float aoOp = u_shadow.y;
    float sigma = max(0.5, u_shadow.z);
    float aoSigma = max(0.5, u_shadow.w);
    float extent = max(1.0, u_geom.z);

    float aAo = aoOp * gaussianEdge(d / (1.41421356 * aoSigma));
    float aKey = keyOp * gaussianEdge(dShift / (1.41421356 * sigma));
    float a = 1.0 - (1.0 - aAo) * (1.0 - aKey);
    // Fades to nothing over the last 4px before the patch edge. Written with
    // the edges in rising order: smoothstep(a, b, x) with a > b is undefined.
    float tailFade = 1.0 - smoothstep(max(0.0, extent - 4.0), extent, d);
    return a * tailFade;
}

void main() {
    vec2 p = u_patchRect.xy + qt_TexCoord0 * u_patchRect.zw;
    float effR = u_attachRadii.x;
    float wingR = u_attachRadii.y;
    float mode = u_attachRadii.z;
    float innerR = u_geom.x;
    float offsetY = u_geom.y;
    float attachOp = clamp(u_cut.w, 0.0, 1.0);

    if (mode > 1.5) {
        // Floating rounded capsule (fullscreen OSD fallback in Frame Look).
        vec4 box = vec4(u_attachRect.xy, u_attachRect.xy + u_attachRect.zw);
        float d = sdRoundedBox(p, box, effR);
        if (d <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }
        float dShift = sdRoundedBox(p - vec2(0.0, offsetY), box, effR);
        float a = computeShadow(d, dShift);
        fragColor = vec4(0.0, 0.0, 0.0, a * attachOp * qt_Opacity);
        return;
    }

    if (mode > 0.5) {
        // Bottom-attached docked OSD tab: reflect around bottom hairline y = attachBottom.
        float attachBottom = u_attachRect.y + u_attachRect.w;
        if (p.y >= attachBottom) {
            fragColor = vec4(0.0);
            return;
        }
        float yFlip = attachBottom - p.y;
        vec4 flipRect = vec4(u_attachRect.x, 0.0, u_attachRect.z, u_attachRect.w);
        float dAtt = sdfTopAttached(vec2(p.x, yFlip), flipRect, effR, wingR);
        float aFrameFull = computeShadow(yFlip, yFlip + offsetY);
        bool inCut = (u_cut.x > 0.5 && p.x >= u_cut.y && p.x <= u_cut.z);
        float aFrame = inCut ? 0.0 : aFrameFull;

        if (dAtt <= 0.0) {
            float aTarget = aFrameFull * (1.0 - attachOp);
            float aOver = clamp((aTarget - aFrame) / max(0.001, 1.0 - aFrame), 0.0, 1.0);
            fragColor = vec4(0.0, 0.0, 0.0, aOver * qt_Opacity);
            return;
        }
        float dAttShift = sdfTopAttached(vec2(p.x, yFlip + offsetY), flipRect, effR, wingR);
        float dUnion = min(yFlip, dAtt);
        float dUnionShift = min(yFlip + offsetY, dAttShift);
        float aUnion = computeShadow(dUnion, dUnionShift);
        float aTarget = mix(aFrameFull, aUnion, attachOp);
        float aOver = clamp((aTarget - aFrame) / max(0.001, 1.0 - aFrame), 0.0, 1.0);
        fragColor = vec4(0.0, 0.0, 0.0, aOver * qt_Opacity);
        return;
    }

    // Mode 0: Top-attached morphing drawer or attached LauncherWindow.
    if (p.y <= u_attachRect.y) {
        fragColor = vec4(0.0);
        return;
    }

    float dFrameFull = sdfCutout(p, u_innerBox, innerR, 0.0);
    if (dFrameFull <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 q = p - vec2(0.0, offsetY);
    float dFrameFullShift = sdfCutout(q, u_innerBox, innerR, 0.0);
    float aFrameFull = computeShadow(dFrameFull, dFrameFullShift);

    float omitTop = (u_cut.x > 0.5 && p.x >= u_cut.y && p.x <= u_cut.z) ? 1.0 : 0.0;
    float dFrameDrawn = sdfCutout(p, u_innerBox, innerR, omitTop);
    float dFrameDrawnShift = sdfCutout(q, u_innerBox, innerR, omitTop);
    float aFrame = computeShadow(dFrameDrawn, dFrameDrawnShift);

    float dAtt = sdfTopAttached(p, u_attachRect, effR, wingR);
    if (dAtt <= 0.0) {
        if (u_cut.x <= 0.5) {
            fragColor = vec4(0.0);
            return;
        }
        float aTarget = aFrameFull * (1.0 - attachOp);
        float aOver = clamp(aTarget, 0.0, 1.0);
        fragColor = vec4(0.0, 0.0, 0.0, aOver * qt_Opacity);
        return;
    }

    float dAttShift = sdfTopAttached(q, u_attachRect, effR, wingR);
    float dUnion = min(dFrameFull, dAtt);
    float dUnionShift = min(dFrameFullShift, dAttShift);
    float aUnion = computeShadow(dUnion, dUnionShift);

    float aTarget = mix(aFrameFull, aUnion, attachOp);
    float aOver = clamp((aTarget - aFrame) / max(0.001, 1.0 - aFrame), 0.0, 1.0);
    fragColor = vec4(0.0, 0.0, 0.0, aOver * qt_Opacity);
}
