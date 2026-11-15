#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 u_patchRect;   // (x, y, w, h) in FrameHost coordinates
    vec4 u_innerBox;    // (left, top, right, bottom) of inner viewport cutout
    vec4 u_shadow;      // (keyOpacity, aoOpacity, sigma, aoSigma)
    vec4 u_geom;        // (innerR, offsetY, extent, 0.0)
    vec4 u_topCut;      // (active, cutLeft, cutRight, wingR)
    vec4 u_topAttach;   // (cardX, cardW, cardH, effR)
    vec4 u_botCut;      // (active, cutLeft, cutRight, 0.0)
};

// 0.5 * erfc(x), exact Gaussian step-edge blur integral (Abramowitz & Stegun 7.1.26).
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

float sdfCutout(vec2 p, vec4 box, float r, float omitTop, float omitBot) {
    vec4 eff = box;
    if (omitTop > 0.5) eff.y -= 256.0;
    if (omitBot > 0.5) eff.w += 256.0;
    vec2 center = 0.5 * (eff.xy + eff.zw);
    vec2 halfExt = 0.5 * (eff.zw - eff.xy);
    vec2 q = abs(p - center) - (halfExt - vec2(r));
    float sdBox = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    return -sdBox;
}

float sdfTopAttached(vec2 p, float barH, vec4 attach, float wingR) {
    float cx = attach.x + 0.5 * attach.y;
    float hx = 0.5 * attach.y;
    float effR = attach.w;
    float botY = barH + attach.z;
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
    float innerR = u_geom.x;
    float offsetY = u_geom.y;

    // Never draw inside the frame bezel strips or 4 inner concave corners.
    float dBase = sdfCutout(p, u_innerBox, innerR, 0.0, 0.0);
    if (dBase <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Never draw under an attached top drawer, launcher, or its concave wings.
    if (u_topCut.x > 0.5 && u_topAttach.y > 0.0 && u_topAttach.z >= 2.0) {
        if (sdfTopAttached(p, u_innerBox.y, u_topAttach, u_topCut.w) <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }
    }

    float omitTop = (u_topCut.x > 0.5 && p.x >= u_topCut.y && p.x <= u_topCut.z) ? 1.0 : 0.0;
    float omitBot = (u_botCut.x > 0.5 && p.x >= u_botCut.y && p.x <= u_botCut.z) ? 1.0 : 0.0;

    float d = sdfCutout(p, u_innerBox, innerR, omitTop, omitBot);
    float dShift = sdfCutout(p - vec2(0.0, offsetY), u_innerBox, innerR, omitTop, omitBot);
    float a = computeShadow(d, dShift);
    fragColor = vec4(0.0, 0.0, 0.0, a * qt_Opacity);
}
