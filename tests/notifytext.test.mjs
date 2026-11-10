// Notification bodies as plain text (singletons/notifytext.js). Run with: node --test tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// notifytext.js is a QML script library: a ".pragma library" line and a plain
// function, no exports. Drop that line and it is ordinary JavaScript.
const source = readFileSync(new URL("../singletons/notifytext.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const { plain } = new Function(`${source}\nreturn { plain };`)();

test("tags are dropped and their text kept", () => {
    assert.equal(plain("<b>Build</b> finished"), "Build finished");
    assert.equal(plain('<a href="https://x">Open</a> now'), "Open now");
});

test("an image tag leaves nothing behind, so nothing is fetched or shown", () => {
    assert.equal(plain('<img src="https://t/p.png" alt="x"/>Hi'), "Hi");
});

test("entities are decoded once, so escaped markup stays text", () => {
    assert.equal(plain("1 &lt; 2 &amp;&amp; 3 &gt; 2"), "1 < 2 && 3 > 2");
    assert.equal(plain("&amp;lt;b&amp;gt;"), "&lt;b&gt;");
    assert.equal(plain("&#39;q&#x27;"), "'q'");
});

test("a lone < or > that is not a tag is kept", () => {
    assert.equal(plain("a < b and c > d"), "a < b and c > d");
});

test("<br> becomes a line break", () => {
    assert.equal(plain("line1<br>line2"), "line1\nline2");
    assert.equal(plain("line1<br/>line2<BR />line3"), "line1\nline2\nline3");
});

test("a numeric entity outside Unicode is left as written", () => {
    assert.equal(plain("&#99999999;"), "&#99999999;");
});
