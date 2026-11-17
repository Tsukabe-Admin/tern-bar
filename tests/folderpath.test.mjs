// The folder picker's path handling (singletons/folderpath.js). Run with: node --test tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// folderpath.js is a QML script library: a ".pragma library" line and plain
// functions, no exports. Drop that line and it is ordinary JavaScript.
const source = readFileSync(new URL("../singletons/folderpath.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const { resolve, parent, join, toUrl, visibleFolders, startCandidates } = new Function(
    `${source}\nreturn { resolve, parent, join, toUrl, visibleFolders, startCandidates };`)();

const HOME = "/home/u";
const HERE = "/home/u/Pictures";

test("a typed absolute path is cleaned up: doubled slashes, a trailing slash, . and ..", () => {
    assert.equal(resolve("/home//u/Pictures/", HERE, HOME), "/home/u/Pictures");
    assert.equal(resolve("/home/u/./Pictures/../Videos", HERE, HOME), "/home/u/Videos");
    assert.equal(resolve("/..", HERE, HOME), "/");
    assert.equal(resolve("/", HERE, HOME), "/");
});

test("~ means the home folder", () => {
    assert.equal(resolve("~", HERE, HOME), "/home/u");
    assert.equal(resolve("~/Pictures/Walls", HERE, HOME), "/home/u/Pictures/Walls");
    // Not another user's home: taken as a name in the folder being shown.
    assert.equal(resolve("~bob", HERE, HOME), "/home/u/Pictures/~bob");
});

test("a name without a leading slash is looked for in the folder being shown", () => {
    assert.equal(resolve("Walls", HERE, HOME), "/home/u/Pictures/Walls");
    assert.equal(resolve("../Videos", HERE, HOME), "/home/u/Videos");
    assert.equal(resolve("sub", "/", HOME), "/sub");
});

test("a pasted path keeps the spaces inside it and loses the ones around it", () => {
    assert.equal(resolve("  /home/u/My Walls\n", HERE, HOME), "/home/u/My Walls");
});

test("a file:// address from a file manager becomes the path it names", () => {
    assert.equal(resolve("file:///home/u/My%20Walls/%231", HERE, HOME), "/home/u/My Walls/#1");
    assert.equal(resolve("file://localhost/srv/art", HERE, HOME), "/srv/art");
    // A broken escape is kept as typed instead of throwing or going elsewhere.
    assert.equal(resolve("file:///home/u/100%", HERE, HOME), "/home/u/100%");
});

test("nothing typed means nowhere to go", () => {
    assert.equal(resolve("", HERE, HOME), "");
    assert.equal(resolve("   \n", HERE, HOME), "");
});

test("up goes one level and stops at /", () => {
    assert.equal(parent("/home/u/Pictures"), "/home/u");
    assert.equal(parent("/home"), "/");
    assert.equal(parent("/"), "/");
});

test("a folder inside / has one slash, not two", () => {
    assert.equal(join("/", "srv"), "/srv");
    assert.equal(join("/home/u", "My Walls"), "/home/u/My Walls");
});

// What FolderListModel does with the URL it is given (Qt 6.12,
// QQuickFolderListModelPrivate::resolvePath): take the URL's local path, which
// decodes it once, read that path as a URL again, and use its decoded path.
function folderListModelPath(url) {
    const local = decodeURIComponent(url.slice("file://".length));
    return decodeURIComponent(new URL(local, "file:///").pathname);
}

test("a folder whose name has #, ?, % or spaces in it is the folder the model opens", () => {
    for (const name of ["100% #1", "what?", "a%41b", "My Walls", "ünï ✓", "[b]{c}"])
        assert.equal(folderListModelPath(toUrl("/home/u/" + name)), "/home/u/" + name);
    assert.equal(folderListModelPath(toUrl("/")), "/");
});

test("the list hides . .. and dot-folders and sorts names ignoring case", () => {
    assert.deepEqual(visibleFolders([".", "..", ".cache", "beta", "Alpha", "Zeta", "gamma"]),
        ["Alpha", "beta", "gamma", "Zeta"]);
    // Names that differ only in case keep a fixed order instead of swapping
    // places from one listing to the next.
    assert.deepEqual(visibleFolders(["b", "B", "a"]), ["a", "B", "b"]);
    assert.deepEqual(visibleFolders(["B", "b", "a"]), ["a", "B", "b"]);
});

test("the picker opens at the folder in use, else its nearest parent, else home", () => {
    assert.deepEqual(startCandidates("/home/u/Pictures/Gone", HOME),
        ["/home/u/Pictures/Gone", "/home/u/Pictures", "/home/u", "/home", "/"]);
    // An unplugged drive: home comes before "/".
    assert.deepEqual(startCandidates("/run/media/u/USB/Walls", HOME),
        ["/run/media/u/USB/Walls", "/run/media/u/USB", "/run/media/u", "/run/media", "/run", "/home/u", "/"]);
    // A setting that is not an absolute path is never tried.
    assert.deepEqual(startCandidates("", HOME), ["/home/u", "/"]);
    assert.deepEqual(startCandidates("-delete", HOME), ["/home/u", "/"]);
    // "/" itself can be the folder in use, and is then tried first.
    assert.deepEqual(startCandidates("/", HOME), ["/", "/home/u"]);
});
