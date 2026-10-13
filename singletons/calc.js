.pragma library

// Evaluates + - * / % ^ and parentheses on decimal numbers, with unary minus
// binding looser than ^ (so -2^2 is -4). Returns a finite number, or null when
// the text is not such an expression. No eval: typing can never run code.
function evaluate(text) {
    const src = String(text).replace(/\s+/g, "");
    if (src === "" || !/^[0-9.+\-*/%^()]+$/.test(src))
        return null;
    let pos = 0;

    function peek() {
        return src[pos];
    }

    function number() {
        const m = /^(\d+\.?\d*|\.\d+)/.exec(src.slice(pos));
        if (!m)
            throw new Error("number expected");
        pos += m[0].length;
        return parseFloat(m[0]);
    }

    function primary() {
        if (peek() === "(") {
            pos++;
            const v = sum();
            if (peek() !== ")")
                throw new Error(") expected");
            pos++;
            return v;
        }
        return number();
    }

    function power() {
        const base = primary();
        if (peek() === "^") {
            pos++;
            return Math.pow(base, unary());   // right-associative: 2^3^2 = 2^9
        }
        return base;
    }

    function unary() {
        if (peek() === "-") {
            pos++;
            return -unary();
        }
        if (peek() === "+") {
            pos++;
            return unary();
        }
        return power();
    }

    function product() {
        let v = unary();
        while (peek() === "*" || peek() === "/" || peek() === "%") {
            const op = src[pos++];
            const r = unary();
            v = (op === "*") ? v * r : (op === "/") ? v / r : v % r;
        }
        return v;
    }

    function sum() {
        let v = product();
        while (peek() === "+" || peek() === "-") {
            const op = src[pos++];
            const r = product();
            v = (op === "+") ? v + r : v - r;
        }
        return v;
    }

    try {
        const v = sum();
        return (pos === src.length && isFinite(v)) ? v : null;
    } catch (e) {
        return null;
    }
}

// 10 significant digits without trailing zeros: 0.1+0.2 shows 0.3.
function format(v) {
    return String(parseFloat(v.toPrecision(10)));
}
