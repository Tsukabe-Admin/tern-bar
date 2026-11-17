//! Colour temperature to gamma ramps, for the night-light job.
//!
//! A screen's gamma ramps say, for each of red, green and blue, how bright
//! every input level is shown. Night light scales each channel by the colour
//! of a warmer white: at 4000 K blue tops out at 60 % and green at 82 %.
//!
//! The numbers are wlsunset's, so night light looks exactly as it did when
//! Skua ran wlsunset 0.4.0 (git.sr.ht/~kennylevinsen/wlsunset, tag 0.4.0):
//! `whitepoint` is `calc_whitepoint` from its color_math.c and `ramps` is
//! `fill_gamma_table` from its main.c. They are ported line by line, in the
//! same order of operations, so they give the same bits; the tests below
//! compare them with numbers from wlsunset's own C code. (wlsunset's later,
//! unreleased sources drop the sRGB curve in `srgb_gamma`, which makes 4000 K
//! a little less warm; this follows the released version.)
//!
//! wlsunset is Copyright 2020 Kenny Levinsen, under the MIT licence (as Skua
//! is), whose notice asks to be kept with substantial portions of it:
//! "Permission is hereby granted, free of charge, to any person obtaining a
//! copy of this software and associated documentation files (the "Software"),
//! to deal in the Software without restriction, including without limitation
//! the rights to use, copy, modify, merge, publish, distribute, sublicense,
//! and/or sell copies of the Software, and to permit persons to whom the
//! Software is furnished to do so, subject to the following conditions: The
//! above copyright notice and this permission notice shall be included in all
//! copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS
//! IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
//! LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
//! PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//! HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
//! ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//! WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."

/// The colour of white at `kelvin` as red, green and blue factors, the largest
/// one 1.0. 6500 K, the white screens are made for, is 1.0 for all three.
pub fn whitepoint(kelvin: i32) -> [f64; 3] {
    if kelvin == 6500 {
        return [1.0, 1.0, 1.0];
    }
    // wlsunset's reasoning: warm, dim lights look as the Planckian locus (a
    // glowing body seen up close) says, cold bright ones as the daylight locus
    // (sunlight through the air) says, so it follows the first below 2500 K,
    // the second from 4000 K, and blends them smoothly in between.
    let (x, y) = if kelvin >= 25000 {
        illuminant_d(25000)
    } else if kelvin >= 4000 {
        illuminant_d(kelvin)
    } else if kelvin >= 2500 {
        let (x1, y1) = illuminant_d(kelvin);
        let (x2, y2) = planckian_locus(kelvin);
        let factor = (4000.0 - f64::from(kelvin)) / 1500.0;
        let sinefactor = ((std::f64::consts::PI * factor).cos() + 1.0) / 2.0;
        (
            x1 * sinefactor + x2 * (1.0 - sinefactor),
            y1 * sinefactor + y2 * (1.0 - sinefactor),
        )
    } else {
        planckian_locus(kelvin.max(1667))
    };
    let z = 1.0 - x - y;

    // CIE XYZ to linear sRGB (brucelindbloom.com), then wlsunset's sRGB curve.
    let r = srgb_gamma((3.2404542 * x - 1.5371385 * y - 0.4985314 * z).clamp(0.0, 1.0));
    let g = srgb_gamma((-0.9692660 * x + 1.8760108 * y + 0.0415560 * z).clamp(0.0, 1.0));
    let b = srgb_gamma((0.0556434 * x - 0.2040259 * y + 1.0572252 * z).clamp(0.0, 1.0));
    let max = r.max(g.max(b));
    [r / max, g / max, b / max]
}

/// The daylight locus (CIE illuminant series D): the chromaticity (x, y) of
/// daylight at `kelvin`, for 2500 to 25000 K.
///
/// wlsunset writes the squares as `pow(v, 2)`; the C compiler turns those into
/// `v * v` (which has the same result), so that is written here. The cubes stay
/// calls to the C library's `pow`, as in wlsunset.
fn illuminant_d(kelvin: i32) -> (f64, f64) {
    let t = f64::from(kelvin);
    let x = if kelvin <= 7000 {
        0.244063 + 0.09911e3 / t + 2.9678e6 / (t * t) - 4.6070e9 / t.powf(3.0)
    } else {
        0.237040 + 0.24748e3 / t + 1.9018e6 / (t * t) - 2.0064e9 / t.powf(3.0)
    };
    let y = (-3.0 * (x * x)) + (2.870 * x) - 0.275;
    (x, y)
}

/// The Planckian locus: the chromaticity (x, y) of a glowing body at
/// `kelvin`, for 1667 to 4000 K, the only part `whitepoint` uses.
fn planckian_locus(kelvin: i32) -> (f64, f64) {
    let t = f64::from(kelvin);
    let x = -0.2661239e9 / t.powf(3.0) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910;
    let y = if kelvin <= 2222 {
        -1.1064814 * x.powf(3.0) - 1.34811020 * (x * x) + 2.18555832 * x - 0.20219683
    } else {
        -0.9549476 * x.powf(3.0) - 1.37418593 * (x * x) + 2.09137015 * x - 0.16748867
    };
    (x, y)
}

/// wlsunset 0.4.0's `srgb_gamma(value, 2.2)`. It is not quite the sRGB
/// standard's curve, but it is what the screens looked like.
fn srgb_gamma(value: f64) -> f64 {
    if value <= 0.0031308 {
        12.92 * value
    } else {
        (1.055 * value).powf(1.0 / 2.2) - 0.055
    }
}

/// The gamma table for a screen whose ramps have `size` entries (at least 1):
/// the red ramp, then the green one, then the blue one, each a straight line
/// from 0 to the channel's factor in `white` times 65535.
///
/// wlsunset also raises each value to 1/gamma, with a gamma of 1.0 unless it is
/// told otherwise (Skua never did), which leaves it unchanged.
pub fn ramps(size: u32, white: [f64; 3]) -> Vec<u16> {
    let last = f64::from(size - 1);
    let mut table = Vec::with_capacity(3 * size as usize);
    for factor in white {
        for i in 0..size {
            let level = f64::from(i) / last;
            // `as` cuts the fraction off, as C's cast to uint16_t does.
            table.push((f64::from(u16::MAX) * (level * factor)) as u16);
        }
    }
    table
}

#[cfg(test)]
mod tests {
    use super::*;

    // Every number here comes from wlsunset 0.4.0's own C code. color_math.c
    // and color_math.h as they are, fill_gamma_table cut out of main.c with
    //
    //     sed -n '/^static void fill_gamma_table/,/^}/p' main.c
    //
    // and a small main() that prints, for each temperature, the bits of
    // calc_whitepoint() and, for each ramp size, the FNV-1a hash (below) of the
    // table fill_gamma_table(table, size, r, g, b, 1.0) fills, plus its last
    // and middle entries. Built with `gcc -O2 -march=x86-64 -mtune=generic
    // ... -lm` (Arch's flags for wlsunset) and again with -O0: the same output.

    /// (kelvin, red, green and blue factor as f64 bits)
    const WHITEPOINTS: [(i32, [u64; 3]); 10] = [
        (
            1000,
            [0x3ff0000000000000, 0x3fdda12cff3edad1, 0x0000000000000000],
        ),
        (
            2000,
            [0x3ff0000000000000, 0x3fe0bd71458ce586, 0x3fb0153648a3efb4],
        ),
        (
            3000,
            [0x3ff0000000000000, 0x3fe6538de6a7987a, 0x3fd8e0a93c2bc82f],
        ),
        (
            3500,
            [0x3ff0000000000000, 0x3fe87832779c952d, 0x3fdfcbcee1410b35],
        ),
        (
            4000,
            [0x3ff0000000000000, 0x3fea596a49acb3d9, 0x3fe31fa3156eae9a],
        ),
        (
            4001,
            [0x3ff0000000000000, 0x3fea5a457a44886f, 0x3fe3214c43a6aca3],
        ),
        (
            5000,
            [0x3ff0000000000000, 0x3fed2db8d8025579, 0x3fe912199a7c2bb0],
        ),
        (
            6500,
            [0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000],
        ),
        (
            7500,
            [0x3fecd6e1d2d6efff, 0x3fee06caa56acb1d, 0x3ff0000000000000],
        ),
        (
            10000,
            [0x3fe885c3e0c98faf, 0x3feb30109a52baca, 0x3ff0000000000000],
        ),
    ];

    /// (kelvin, ramp size, FNV-1a hash of the whole table)
    const TABLES: [(i32, u32, u64); 30] = [
        (1000, 256, 0xa0b4544634b9ad9c),
        (1000, 1024, 0x4a348d64079bc3fe),
        (1000, 4096, 0x6365efa4298bc1ae),
        (2000, 256, 0x9159de13adfc25a5),
        (2000, 1024, 0x7b1e71894dd1c396),
        (2000, 4096, 0x3d86ba49bddacd6d),
        (3000, 256, 0x5935881ae25cd0c6),
        (3000, 1024, 0xcc55c4e251e39701),
        (3000, 4096, 0xc6750afd83d6a9c5),
        (3500, 256, 0x3283c8f2700817f1),
        (3500, 1024, 0x7a8edab7942916bb),
        (3500, 4096, 0x54596e3b73e4f152),
        (4000, 256, 0x56e07bd05967cbf0),
        (4000, 1024, 0x232610c01c85c3bc),
        (4000, 4096, 0x81fbac66cdd36a06),
        (4001, 256, 0x4d8749dc499cd15d),
        (4001, 1024, 0xfaa06be65bd68ff0),
        (4001, 4096, 0x2e1154201cfcf29c),
        (5000, 256, 0x263cfa0078e7026d),
        (5000, 1024, 0xe68dbb8b7041c388),
        (5000, 4096, 0xd323b1dcaa1f744c),
        (6500, 256, 0xea9b825068f22d25),
        (6500, 1024, 0xd4008db532dd6bc9),
        (6500, 4096, 0x789f4cc3a6b3aa55),
        (7500, 256, 0x2fa882101a761dd3),
        (7500, 1024, 0x8bb7f7592559a333),
        (7500, 4096, 0x220c9fb8f0dd5334),
        (10000, 256, 0xd725662f8d625f1c),
        (10000, 1024, 0xb67be56d804edb18),
        (10000, 4096, 0xe70da6e791213f75),
    ];

    /// FNV-1a over the table's entries, each as two bytes, low byte first.
    fn fnv1a(table: &[u16]) -> u64 {
        let mut hash: u64 = 0xcbf29ce484222325;
        for byte in table.iter().flat_map(|value| value.to_le_bytes()) {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x100000001b3);
        }
        hash
    }

    #[test]
    fn whitepoints_match_wlsunset_bit_for_bit() {
        for (kelvin, bits) in WHITEPOINTS {
            assert_eq!(whitepoint(kelvin).map(f64::to_bits), bits, "{kelvin} K");
        }
    }

    #[test]
    fn tables_match_wlsunset_entry_for_entry() {
        for (kelvin, size, hash) in TABLES {
            let table = ramps(size, whitepoint(kelvin));
            assert_eq!(table.len(), 3 * size as usize);
            assert_eq!(fnv1a(&table), hash, "{kelvin} K, {size} entries");
        }
    }

    #[test]
    fn some_entries_read_as_wlsunset_printed_them() {
        // 4000 K, 256 entries: the last and the middle entry of each ramp.
        let table = ramps(256, whitepoint(4000));
        assert_eq!([table[255], table[511], table[767]], [65535, 53962, 39164]);
        assert_eq!([table[128], table[384], table[640]], [32896, 27087, 19659]);
        // 3000 K, 1024 entries.
        let table = ramps(1024, whitepoint(3000));
        assert_eq!(
            [table[1023], table[2047], table[3071]],
            [65535, 45723, 25474]
        );
        assert_eq!(
            [table[512], table[1536], table[2560]],
            [32799, 22884, 12749]
        );
        // 1000 K is as warm as 1667 K, wlsunset's lowest, and has no blue.
        let table = ramps(256, whitepoint(1000));
        assert_eq!([table[255], table[511], table[767]], [65535, 30340, 0]);
    }

    #[test]
    fn normal_white_is_the_identity_ramp() {
        assert_eq!(whitepoint(6500), [1.0, 1.0, 1.0]);
        for size in [256, 1024, 4096] {
            let table = ramps(size, whitepoint(6500));
            let (red, rest) = table.split_at(size as usize);
            let (green, blue) = rest.split_at(size as usize);
            assert_eq!(red, green);
            assert_eq!(red, blue);
            assert_eq!((red[0], red[size as usize - 1]), (0, 65535));
            let last = size - 1;
            for (i, value) in (0..).zip(red) {
                // A straight line from 0 to 65535; the floating-point division
                // can land one off where the exact value is a whole number.
                let exact = 65535 * i / last;
                assert!(
                    exact.abs_diff(u32::from(*value)) <= 1,
                    "{size} entries, entry {i}"
                );
            }
        }
    }
}
