//! `image::RgbaImage` <-> `tiny_skia::Pixmap` conversion at the drawing-pipeline boundary.
//!
//! `image::RgbaImage` stores **non-premultiplied** RGBA. `tiny_skia::Pixmap` stores
//! **premultiplied** RGBA. We do the channel math here so callers (and tests) never have to.
//!
//! Premultiplication formula: `c' = round(c * a / 255)` per color channel. Reverse:
//! `c = round(c' * 255 / a)` when `a > 0`, else 0.

use image::{Rgba, RgbaImage};
use tiny_skia::Pixmap;

/// Build a Pixmap from an RgbaImage, premultiplying alpha as we go.
///
/// Panics if the image dimensions are zero — `Pixmap::new` rejects 0×N or N×0 buffers, and
/// the calling pipeline already guarantees a valid decoded image.
pub fn to_pixmap(img: &RgbaImage) -> Pixmap {
    let (w, h) = img.dimensions();
    let mut pixmap = Pixmap::new(w, h).expect("non-zero image dimensions");
    let dst = pixmap.data_mut();
    for (i, Rgba([r, g, b, a])) in img.pixels().enumerate() {
        let off = i * 4;
        dst[off] = premul_channel(*r, *a);
        dst[off + 1] = premul_channel(*g, *a);
        dst[off + 2] = premul_channel(*b, *a);
        dst[off + 3] = *a;
    }
    pixmap
}

/// Build an RgbaImage from a Pixmap, unpremultiplying alpha.
pub fn from_pixmap(pixmap: &Pixmap) -> RgbaImage {
    let (w, h) = (pixmap.width(), pixmap.height());
    let src = pixmap.data();
    let mut out = RgbaImage::new(w, h);
    for (i, px) in out.pixels_mut().enumerate() {
        let off = i * 4;
        let a = src[off + 3];
        px.0 = [
            unpremul_channel(src[off], a),
            unpremul_channel(src[off + 1], a),
            unpremul_channel(src[off + 2], a),
            a,
        ];
    }
    out
}

#[inline]
fn premul_channel(c: u8, a: u8) -> u8 {
    // (c * a + 127) / 255 — the +127 gives proper rounding without floats.
    let p = u32::from(c) * u32::from(a) + 127;
    ((p + (p >> 8)) >> 8) as u8
}

#[inline]
fn unpremul_channel(c: u8, a: u8) -> u8 {
    if a == 0 {
        return 0;
    }
    // c * 255 / a, saturated to 255 in case of rounding overshoot.
    ((u32::from(c) * 255 + u32::from(a) / 2) / u32::from(a)).min(255) as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opaque_round_trip_is_identity() {
        let mut img = RgbaImage::new(3, 2);
        for (i, p) in img.pixels_mut().enumerate() {
            p.0 = [(i * 30) as u8, (i * 40) as u8, (i * 50) as u8, 255];
        }
        let pixmap = to_pixmap(&img);
        let back = from_pixmap(&pixmap);
        assert_eq!(img.as_raw(), back.as_raw(), "opaque pixels must round-trip exactly");
    }

    #[test]
    fn fully_transparent_round_trip_zeroes_color() {
        let img = RgbaImage::from_pixel(2, 2, Rgba([200, 100, 50, 0]));
        let pixmap = to_pixmap(&img);
        let back = from_pixmap(&pixmap);
        for px in back.pixels() {
            assert_eq!(px.0, [0, 0, 0, 0], "alpha=0 collapses color to 0");
        }
    }

    #[test]
    fn translucent_round_trip_within_one_lsb() {
        // Premul -> unpremul is lossy at low alphas; assert tolerance, not equality.
        let img = RgbaImage::from_pixel(1, 1, Rgba([200, 100, 50, 128]));
        let pixmap = to_pixmap(&img);
        let back = from_pixmap(&pixmap);
        let got = back.get_pixel(0, 0).0;
        let exp: [u8; 4] = [200, 100, 50, 128];
        for i in 0..4 {
            let diff = i32::from(got[i]) - i32::from(exp[i]);
            assert!(
                diff.abs() <= 1,
                "channel {i}: got {} expected {} (diff {diff})",
                got[i],
                exp[i]
            );
        }
    }

    #[test]
    fn pixmap_dimensions_match_source() {
        let img = RgbaImage::new(7, 5);
        let pixmap = to_pixmap(&img);
        assert_eq!((pixmap.width(), pixmap.height()), (7, 5));
    }
}
