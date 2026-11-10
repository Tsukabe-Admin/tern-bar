.pragma library

// Evaluates + - * / % ^ and parentheses on decimal numbers, with unary minus
// binding looser than ^ (so -2^2 is -4). Returns { value, exact }, or null when
// the text is not such an expression or its value is not finite. No eval:
// typing can never run code.
//
// `exact` is true when every number typed and every step was a whole number a
// double holds exactly (up to 2^53 - 1): the value is then the true answer,
// digit for digit. One fraction, or one step past that range, and the value is
// only as good as floating point, which format() takes into account.
function evaluate(text) {
    const src = String(text).replace(/\s+/g, "");
    if (src === "" || !/^[0-9.+\-*/%^()]+$/.test(src))
        return null;
    let pos = 0;
    let exact = true;

    function peek() {
        return src[pos];
    }

    // Every number and every result passes through here.
    function step(value) {
        if (!Number.isSafeInteger(value))
            exact = false;
        return value;
    }

    function number() {
        const m = /^(\d+\.?\d*|\.\d+)/.exec(src.slice(pos));
        if (!m)
            throw new Error("number expected");
        pos += m[0].length;
        // A number written with a decimal point may already be rounded on the
        // way in (17781783923801.9987 becomes a whole double), so it is never exact.
        if (m[0].indexOf(".") !== -1)
            exact = false;
        return step(parseFloat(m[0]));
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
            return step(Math.pow(base, unary()));   // right-associative: 2^3^2 = 2^9
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
            v = step((op === "*") ? v * r : (op === "/") ? v / r : v % r);
        }
        return v;
    }

    function sum() {
        let v = product();
        while (peek() === "+" || peek() === "-") {
            const op = src[pos++];
            const r = product();
            v = step((op === "+") ? v + r : v - r);
        }
        return v;
    }

    try {
        const v = sum();
        return (pos === src.length && isFinite(v)) ? { value: v, exact: exact } : null;
    } catch (e) {
        return null;
    }
}

// An answer from evaluate() as the launcher shows and copies it. An exact one
// is printed digit for digit. Any other is only as good as floating point, so
// it gets 10 significant digits without trailing zeros: enough to be useful,
// few enough to hide the noise (0.1+0.2 shows 0.3, and a difference of two
// close numbers does not grow a tail of 9s).
function format(answer) {
    if (answer.exact)
        return String(answer.value);
    return String(parseFloat(answer.value.toPrecision(10)));
}
