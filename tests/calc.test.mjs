// The launcher's calculator (singletons/calc.js). Run with: node --test tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// calc.js is a QML script library: a ".pragma library" line and two plain
// functions, no exports. Drop that line and it is ordinary JavaScript.
const source = readFileSync(new URL("../singletons/calc.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const { evaluate, format } = new Function(`${source}\nreturn { evaluate, format };`)();

// What the launcher row shows, and what Enter copies.
function shown(text) {
    const answer = evaluate(text);
    return answer === null ? null : format(answer);
}

test("whole-number arithmetic is shown digit for digit", () => {
    assert.equal(shown("2^40"), "1099511627776");
    assert.equal(shown("123456*987654"), "121931812224");
    assert.equal(shown("12345678901+1"), "12345678902");
    assert.equal(shown("94906265*94906265"), "9007199136250225");
    assert.equal(shown("9007199254740990+1"), "9007199254740991");
    assert.equal(shown("1000000000000000/8"), "125000000000000");
    assert.equal(shown("0*-1"), "0");
});

test("an answer that floating point only approximates never shows the rounding as digits", () => {
    assert.equal(shown("6.022*10^23"), "6.022e+23");
    assert.equal(shown("16.458*10^18"), "16458000000000000000");
    assert.equal(shown("(0.1+0.2)*2*10^16"), "6000000000000000");
    assert.equal(shown("(0.7+0.1)*9*10^15"), "7200000000000000");
    assert.equal(shown("64.74*80.47*10^12"), "5209627800000000");
    assert.equal(shown("(42.3-38.2)*10^12"), "4100000000000");
});

test("whole-number arithmetic past 2^53 is not passed off as exact", () => {
    // 2^53 + 1 is not a number a double can hold; the double next to it is 2^53.
    assert.notEqual(shown("2^53+1"), "9007199254740992");
    assert.notEqual(shown("9007199254740991+2"), "9007199254740992");
});

test("float noise is hidden", () => {
    assert.equal(shown("0.1+0.2"), "0.3");
    assert.equal(shown("1.15*100"), "115");
    assert.equal(shown("(0.1+0.2)*10^15"), "300000000000000");
    assert.equal(shown("1/3"), "0.3333333333");
});

test("operators bind as in arithmetic", () => {
    assert.equal(shown("2+3*4"), "14");
    assert.equal(shown("(2+3)*4"), "20");
    assert.equal(shown("-2^2"), "-4");
    assert.equal(shown("2^3^2"), "512");
    assert.equal(shown("7%4"), "3");
});

test("text that is not a finite expression gives no answer", () => {
    for (const text of ["", "abc", "2+", "2^^2", "(2+3", "2)", "1/0"])
        assert.equal(shown(text), null, JSON.stringify(text));
});
