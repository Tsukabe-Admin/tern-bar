.pragma library

// A notification body as plain text. The bar tells apps it understands body
// markup, so a compliant app escapes a literal "<" as "&lt;" and may send a
// few tags (<b>, <i>, <u>, <a>, <img>, <br>). Tags are dropped, <br> becomes a
// line break, and the entities are decoded in one pass, so "&amp;lt;" stays
// the text "&lt;". Everything that shows the result is Text.PlainText.
function plain(text) {
    const named = { lt: "<", gt: ">", amp: "&", quot: "\"", apos: "'" };
    return String(text || "")
        .replace(/<br\s*\/?>/gi, "\n")
        .replace(/<\/?[A-Za-z][^>]*>/g, "")
        .replace(/&(lt|gt|amp|quot|apos|#\d+|#x[0-9A-Fa-f]+);/g, (match, name) => {
            if (name[0] !== "#")
                return named[name];
            const code = name[1] === "x" ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
            return (code > 0 && code <= 0x10FFFF) ? String.fromCodePoint(code) : match;
        });
}
