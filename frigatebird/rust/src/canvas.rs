//! `image::RgbaImage` <-> `tiny_skia::Pixmap` conversion at the drawing-pipeline boundary.
//!
//! `image::RgbaImage` stores **non-premultiplied** RGBA. `tiny_skia::Pixmap` stores
//! **premultiplied** RGBA. The channel math is delegated to tiny-skia's typed wrappers
//! (`ColorU8::premultiply` / `PremultipliedColorU8::demultiply`) so we don't reinvent it and
//! we automatically inherit any future tiny-skia rounding tweaks.

use image::{Rgba, RgbaImage};
use tiny_skia::{ColorU8, Pixmap};

/// Build a Pixmap from an `RgbaImage`, premultiplying alpha as we go.
///
/// Panics if the image dimensions are zero — `Pixmap::new` rejects 0×N or N×0 buffers, and
/// the calling pipeline already guarantees a valid decoded image.
pub fn to_pixmap(img: &RgbaImage) -> Pixmap {
    let (w, h) = img.dimensions();
    let mut pixmap = Pixmap::new(w, h).expect("non-zero image dimensions");
    for (src, dst) in img.pixels().zip(pixmap.pixels_mut()) {
        let Rgba([r, g, b, a]) = *src;
        *dst = ColorU8::from_rgba(r, g, b, a).premultiply();
    }
    pixmap
}

/// Build an `RgbaImage` from a Pixmap, unpremultiplying alpha.
pub fn from_pixmap(pixmap: &Pixmap) -> RgbaImage {
    let (w, h) = (pixmap.width(), pixmap.height());
    let mut out = RgbaImage::new(w, h);
    for (src, dst) in pixmap.pixels().iter().zip(out.pixels_mut()) {
        let demul = src.demultiply();
        dst.0 = [demul.red(), demul.green(), demul.blue(), demul.alpha()];
    }
    out
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
        assert_eq!(
            img.as_raw(),
            back.as_raw(),
            "opaque pixels must round-trip exactly"
        );
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

    /// Alpha must round-trip exactly for **every** alpha value, regardless of the source
    /// channel. The conversion never touches the alpha byte directly — it's stored as-is and
    /// read back as-is — so any drift here would mean a structural bug in the tiny-skia
    /// wrapper integration, not a quantization artifact.
    #[test]
    fn alpha_channel_round_trips_exactly_for_all_alpha_values() {
        for a in 0u8..=255 {
            let img = RgbaImage::from_pixel(1, 1, Rgba([200, 100, 50, a]));
            let back = from_pixmap(&to_pixmap(&img));
            assert_eq!(back.get_pixel(0, 0).0[3], a, "alpha drift at a={a}");
        }
    }

    /// `to_pixmap` must produce byte-identical output to constructing each pixel directly via
    /// `ColorU8::from_rgba(...).premultiply()` — i.e. the bulk conversion is exactly the
    /// per-pixel typed-wrapper conversion, with no extra rounding step in the iteration loop.
    /// Catches accidental introduction of intermediate float math or alternate constants.
    #[test]
    fn to_pixmap_matches_per_pixel_tiny_skia_premultiply() {
        let mut img = RgbaImage::new(4, 4);
        for (i, p) in img.pixels_mut().enumerate() {
            // Spread across the input space: high/low alphas, mixed channels.
            p.0 = [
                (i * 17) as u8,
                (i * 31) as u8,
                (i * 53) as u8,
                ((i * 13) % 256) as u8,
            ];
        }
        let pixmap = to_pixmap(&img);
        for (src, got) in img.pixels().zip(pixmap.pixels()) {
            let Rgba([r, g, b, a]) = *src;
            let want = ColorU8::from_rgba(r, g, b, a).premultiply();
            assert_eq!(
                *got, want,
                "bulk conversion must match per-pixel typed wrapper"
            );
        }
    }
}
