.pragma library

// A keyboard layout's short name for the keyboard pill: "English (US)" → "US",
// "German" → "DE", "English (Dvorak)" → "DV". Shared by every compositor.
function abbreviate(name) {
    const s = String(name || "").trim();
    if (s === "")
        return "";
    const paren = /\(([^)]+)\)/.exec(s);
    if (paren) {
        const inner = paren[1].trim();
        if (/^[A-Za-z]{2,3}$/.test(inner))
            return inner.toUpperCase();
        const codePrefix = /^([A-Z]{2,3})(?:[,;\s]|$)/.exec(inner);
        if (codePrefix)
            return codePrefix[1];
        const lowerInner = inner.toLowerCase();
        if (lowerInner.indexOf("dvorak") !== -1)
            return "DV";
        if (lowerInner.indexOf("colemak") !== -1)
            return "CM";
        if (lowerInner.indexOf("workman") !== -1)
            return "WM";
        if (lowerInner.indexOf("brazil") !== -1)
            return "BR";
        if (lowerInner.indexOf("canada") !== -1)
            return "CA";
        if (lowerInner.indexOf("austral") !== -1)
            return "AU";
        if (lowerInner.indexOf("latin") !== -1)
            return "LA";
    }
    const map = {
        english: "US", japanese: "JP", russian: "RU", german: "DE", french: "FR",
        spanish: "ES", italian: "IT", portuguese: "PT", korean: "KR", chinese: "CN",
        arabic: "AR", hebrew: "IL", ukrainian: "UA", polish: "PL", dutch: "NL",
        swedish: "SE", norwegian: "NO", danish: "DK", finnish: "FI", turkish: "TR",
        czech: "CZ", greek: "GR", vietnamese: "VN", thai: "TH", hindi: "IN"
    };
    const firstWord = s.split(/[\s(]+/)[0].toLowerCase();
    if (firstWord in map)
        return map[firstWord];
    return s.slice(0, 2).toUpperCase();
}
