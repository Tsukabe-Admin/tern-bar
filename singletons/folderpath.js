.pragma library

// Path work for the folder picker (components/FolderPicker.qml). Plain string
// handling of absolute paths: nothing here looks at the disk, so whether a
// folder really exists is the picker's question, not this file's.

// "/a//b/./c/../d/" → "/a/b/d". Lexical, like `cd` in a shell: ".." drops the
// name before it rather than following a symlink back out, so going up from a
// linked folder returns to the folder the link is in.
function normalize(path) {
    const parts = [];
    for (const part of String(path).split("/")) {
        if (part === "" || part === ".")
            continue;
        if (part === "..")
            parts.pop();
        else
            parts.push(part);
    }
    return "/" + parts.join("/");
}

// What a typed or pasted text means as an absolute path, or "" when nothing
// was typed. Spaces and line breaks around it are dropped (a pasted path often
// carries a newline), "~" is the home folder, a file:// address (what a file
// manager's Copy can hand over) is decoded, and anything else that does not
// start with "/" is taken as relative to `base`, the folder being shown.
function resolve(text, base, home) {
    let path = String(text).trim();
    if (path === "")
        return "";
    const address = /^file:\/\/(?:localhost)?(\/.*)$/i.exec(path);
    if (address) {
        try {
            path = decodeURIComponent(address[1]);
        } catch (e) {
            // A broken %-escape: kept as typed, so the picker says there is no
            // folder there instead of quietly going somewhere else.
            path = address[1];
        }
    }
    if (path === "~" || path.indexOf("~/") === 0)
        path = home + path.slice(1);
    else if (path.indexOf("/") !== 0)
        path = base + "/" + path;
    return normalize(path);
}

// The folder one level up. "/" is its own parent.
function parent(path) {
    const clean = normalize(path);
    const cut = clean.lastIndexOf("/");
    return cut <= 0 ? "/" : clean.slice(0, cut);
}

function join(dir, name) {
    return (dir === "/" ? "" : dir) + "/" + name;
}

// The URL to hand FolderListModel's `folder` for a path. Each name is encoded
// on its own, and "%", "#" and "?" twice: the model turns the URL into a path
// and then reads that path as a URL once more, so encoded only once a "#"
// would start a fragment there, a "?" a query, and "%41" would become "A"
// (measured on Qt 6.12: a folder named "100% #1" was "not a folder"). Not for
// anything else: an Image source wants Wallpaper.fileUrl's single encoding.
function toUrl(path) {
    return "file://" + String(path).split("/")
        .map((name) => encodeURIComponent(name.replace(/[%#?]/g, encodeURIComponent)))
        .join("/");
}

// The names a folder listing shows: no "." or "..", no hidden dot-folders,
// sorted by name with upper and lower case mixed together.
function visibleFolders(names) {
    return names.filter((name) => name !== "" && name.charAt(0) !== ".")
        .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()) || (a < b ? -1 : a > b ? 1 : 0));
}

// The folders to try, in order, when the picker opens at `start` (the folder
// in use, which may have been deleted or unmounted since): the folder itself,
// then each parent up to but not including "/", then home, then "/". The first
// one that exists is where the picker opens.
function startCandidates(start, home) {
    const out = [];
    const add = (path) => {
        if (out.indexOf(path) === -1)
            out.push(path);
    };
    if (typeof start === "string" && start.indexOf("/") === 0) {
        let path = normalize(start);
        add(path);
        while ((path = parent(path)) !== "/")
            add(path);
    }
    if (typeof home === "string" && home.indexOf("/") === 0)
        add(normalize(home));
    add("/");
    return out;
}
