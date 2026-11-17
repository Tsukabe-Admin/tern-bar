//! What a clipboard entry is: which of the types an app offers to take, how
//! much of it to accept, and the short description the launcher shows.

use serde::{Deserialize, Serialize};

/// Plain-text types, best first. Apps offer the same text under several
/// names: the first is today's, the others are older X11 names that Xwayland
/// apps and some toolkits still use. Copying an entry back offers all of them,
/// so every app finds one it asks for.
pub const TEXT_TYPES: [&str; 5] = [
    "text/plain;charset=utf-8",
    "UTF8_STRING",
    "text/plain",
    "TEXT",
    "STRING",
];

/// Image types, best first.
pub const IMAGE_TYPES: [&str; 4] = ["image/png", "image/jpeg", "image/webp", "image/gif"];

/// Password managers (KeePassXC, for one) offer this type, with the content
/// `secret`, next to a copied password, and `wl-copy --sensitive` does the
/// same: a clipboard history must not keep it.
pub const SECRET_HINT: &str = "x-kde-passwordManagerHint";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Text,
    Image,
}

impl Kind {
    /// The most one entry may hold: 1 MB of text, 20 MB for an image. Larger
    /// ones are not kept, so a few screenshots cannot fill the disk unnoticed.
    pub fn limit(self) -> usize {
        match self {
            Kind::Text => 1 << 20,
            Kind::Image => 20 << 20,
        }
    }
}

/// The type to read from an offer: plain text if the app has it, else an
/// image, else nothing. The name returned is the app's own spelling, which is
/// what has to be asked for.
pub fn choose(offered: &[String]) -> Option<(Kind, &str)> {
    let find = |wanted: &str| {
        offered
            .iter()
            .find(|name| name.eq_ignore_ascii_case(wanted))
            .map(String::as_str)
    };
    if let Some(name) = TEXT_TYPES.into_iter().find_map(find) {
        return Some((Kind::Text, name));
    }
    IMAGE_TYPES
        .into_iter()
        .find_map(find)
        .map(|name| (Kind::Image, name))
}

/// Whether the content of the password hint asks for the entry to be left
/// out of the history.
pub fn is_secret(hint: &[u8]) -> bool {
    hint.trim_ascii() == b"secret"
}

/// The image type of `data` from its first bytes, for content whose type is
/// not known (an imported cliphist entry).
pub fn sniff_image(data: &[u8]) -> Option<&'static str> {
    if data.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if data.starts_with(b"\xff\xd8\xff") {
        Some("image/jpeg")
    } else if data.len() >= 12 && data.starts_with(b"RIFF") && &data[8..12] == b"WEBP" {
        Some("image/webp")
    } else if data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a") {
        Some("image/gif")
    } else {
        None
    }
}

/// An image's width and height when they sit in its first bytes: PNG and GIF
/// say them in their header. JPEG and WebP hide them deeper, and are left
/// without.
pub fn dimensions(data: &[u8]) -> Option<(u32, u32)> {
    if data.len() >= 24 && data.starts_with(b"\x89PNG\r\n\x1a\n") && &data[12..16] == b"IHDR" {
        let width = u32::from_be_bytes(data[16..20].try_into().ok()?);
        let height = u32::from_be_bytes(data[20..24].try_into().ok()?);
        return Some((width, height));
    }
    if data.len() >= 10 && (data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a")) {
        let width = u16::from_le_bytes([data[6], data[7]]);
        let height = u16::from_le_bytes([data[8], data[9]]);
        return Some((width.into(), height.into()));
    }
    None
}

/// How many characters of text the launcher gets to show and search.
const PREVIEW_CHARS: usize = 200;

/// One line for the launcher: the start of a text with every run of spaces,
/// tabs and line breaks made one space; for an image its format and size
/// ("PNG 1920×1080"), which a search for "png" finds.
pub fn preview(kind: Kind, mime: &str, data: &[u8], size: Option<(u32, u32)>) -> String {
    match kind {
        Kind::Text => {
            // Enough bytes for the preview even after a long run of spaces,
            // without decoding a whole megabyte of text.
            let head = &data[..data.len().min(64 * 1024)];
            let mut out = String::new();
            let mut count = 0;
            for word in String::from_utf8_lossy(head).split_whitespace() {
                if count > 0 {
                    // A space only when a character can still follow it.
                    if count + 1 >= PREVIEW_CHARS {
                        break;
                    }
                    out.push(' ');
                    count += 1;
                }
                for c in word.chars() {
                    if count == PREVIEW_CHARS {
                        return out;
                    }
                    out.push(c);
                    count += 1;
                }
            }
            out
        }
        Kind::Image => {
            let format = match mime {
                "image/png" => "PNG",
                "image/jpeg" => "JPEG",
                "image/webp" => "WebP",
                "image/gif" => "GIF",
                other => other,
            };
            match size {
                Some((width, height)) => format!("{format} {width}×{height}"),
                None => format.to_owned(),
            }
        }
    }
}

/// A 64-bit FNV-1a hash of the content. It lets the store find a duplicate
/// without reading every file; a match is then compared byte for byte.
pub fn hash(data: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in data {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0100_0000_01b3);
    }
    hash
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// A real 3×2 PNG.
    pub const PNG: [u8; 74] = [
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44,
        0x52, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x02, 0x08, 0x02, 0x00, 0x00, 0x00, 0x12,
        0x16, 0xf1, 0x4d, 0x00, 0x00, 0x00, 0x11, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8,
        0xcf, 0xc0, 0x00, 0x41, 0x0c, 0x30, 0xc6, 0x7f, 0x00, 0x3b, 0xd8, 0x05, 0xfb, 0x39, 0x4d,
        0x96, 0xa5, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ];

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|name| name.to_string()).collect()
    }

    #[test]
    fn text_is_chosen_before_an_image() {
        let offered = names(&["image/png", "text/html", "STRING", "UTF8_STRING"]);
        assert_eq!(choose(&offered), Some((Kind::Text, "UTF8_STRING")));
    }

    #[test]
    fn the_apps_own_spelling_is_asked_for() {
        let offered = names(&["text/plain;charset=UTF-8"]);
        assert_eq!(
            choose(&offered),
            Some((Kind::Text, "text/plain;charset=UTF-8"))
        );
    }

    #[test]
    fn an_image_when_there_is_no_text() {
        let offered = names(&["image/gif", "image/jpeg", "text/uri-list"]);
        assert_eq!(choose(&offered), Some((Kind::Image, "image/jpeg")));
    }

    #[test]
    fn nothing_for_other_types() {
        let offered = names(&["text/html", "application/x-qt-image", "image/bmp"]);
        assert_eq!(choose(&offered), None);
        assert_eq!(choose(&[]), None);
    }

    #[test]
    fn the_secret_hint() {
        assert!(is_secret(b"secret"));
        assert!(is_secret(b"secret\n"));
        assert!(!is_secret(b""));
        assert!(!is_secret(b"public"));
    }

    #[test]
    fn limits() {
        assert_eq!(Kind::Text.limit(), 1024 * 1024);
        assert_eq!(Kind::Image.limit(), 20 * 1024 * 1024);
    }

    #[test]
    fn images_by_their_first_bytes() {
        assert_eq!(sniff_image(&PNG), Some("image/png"));
        assert_eq!(
            sniff_image(b"\xff\xd8\xff\xe0\x00\x10JFIF"),
            Some("image/jpeg")
        );
        assert_eq!(
            sniff_image(b"RIFF\x24\x00\x00\x00WEBPVP8 "),
            Some("image/webp")
        );
        assert_eq!(sniff_image(b"GIF89a\x01\x00\x01\x00"), Some("image/gif"));
        assert_eq!(sniff_image(b"RIFF\x24\x00\x00\x00WAVE"), None);
        assert_eq!(sniff_image(b"hello"), None);
    }

    #[test]
    fn sizes_from_png_and_gif_headers() {
        assert_eq!(dimensions(&PNG), Some((3, 2)));
        assert_eq!(dimensions(b"GIF89a\x40\x01\xf0\x00"), Some((320, 240)));
        assert_eq!(dimensions(b"\xff\xd8\xff\xe0"), None);
        assert_eq!(dimensions(&PNG[..20]), None);
    }

    #[test]
    fn text_previews() {
        let text = b"  first line\n\tsecond   line\r\n";
        assert_eq!(
            preview(Kind::Text, "UTF8_STRING", text, None),
            "first line second line"
        );
        let long = "word ".repeat(100);
        let shown = preview(Kind::Text, "text/plain", long.as_bytes(), None);
        // 40 words and the 39 spaces between them: no space hangs at the end.
        assert_eq!(shown.chars().count(), PREVIEW_CHARS - 1);
        assert!(shown.starts_with("word word") && shown.ends_with("word"));
        let wide = "é".repeat(500);
        assert_eq!(
            preview(Kind::Text, "text/plain", wide.as_bytes(), None),
            "é".repeat(PREVIEW_CHARS)
        );
        assert_eq!(
            preview(Kind::Text, "text/plain", b"a\xffb", None),
            "a\u{fffd}b"
        );
    }

    #[test]
    fn image_previews() {
        assert_eq!(
            preview(Kind::Image, "image/png", &PNG, Some((3, 2))),
            "PNG 3×2"
        );
        assert_eq!(preview(Kind::Image, "image/jpeg", b"", None), "JPEG");
    }

    #[test]
    fn hashes_differ() {
        assert_eq!(hash(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(hash(b"a"), 0xaf63_dc4c_8601_ec8c);
        assert_ne!(hash(b"ab"), hash(b"ba"));
    }
}
