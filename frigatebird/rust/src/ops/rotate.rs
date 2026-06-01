//! Image rotation by 90° increments (quarter turns).
//!
//! # Supported rotations
//!
//! - `0` — no-op (identity, short-circuits without touching pixels).
//! - `1` — 90° clockwise.
//! - `2` — 180°.
//! - `3` — 270° clockwise (= 90° counter-clockwise).
//!
//! Values ≥ 4 are reduced modulo 4 (so `4` = no-op, `5` = 90° CW, etc.).
//!
//! Uses `image::imageops::rotate90/180/270` which produce pixel-exact results
//! (no interpolation needed for orthogonal rotations).

use image::DynamicImage;

/// Quarter-turn rotation applied to a `DynamicImage`.
pub struct Rotate {
    /// Number of 90° clockwise turns (0..3 after mod 4).
    pub quarter_turns: u8,
}

impl Rotate {
    /// Apply rotation in-place, returning the (possibly transposed) image.
    ///
    /// Returns `None` for no-op (0 quarter turns) so the caller can skip re-encoding.
    pub fn apply(self, img: DynamicImage) -> Option<DynamicImage> {
        match self.quarter_turns % 4 {
            0 => None,
            1 => Some(img.rotate90()),
            2 => Some(img.rotate180()),
            _ => Some(img.rotate270()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    /// Creates a small asymmetric test image (3×2) with known pixel values.
    /// Top-left is red, top-right is green, bottom-left is blue.
    fn asymmetric_image() -> DynamicImage {
        let mut img = RgbaImage::new(3, 2);
        img.put_pixel(0, 0, Rgba([255, 0, 0, 255])); // red
        img.put_pixel(2, 0, Rgba([0, 255, 0, 255])); // green
        img.put_pixel(0, 1, Rgba([0, 0, 255, 255])); // blue
        DynamicImage::ImageRgba8(img)
    }

    #[test]
    fn zero_turns_is_noop() {
        let img = asymmetric_image();
        let result = Rotate { quarter_turns: 0 }.apply(img);
        assert!(
            result.is_none(),
            "0 quarter turns should return None (no-op)"
        );
    }

    #[test]
    fn four_turns_wraps_to_noop() {
        let img = asymmetric_image();
        let result = Rotate { quarter_turns: 4 }.apply(img);
        assert!(result.is_none(), "4 quarter turns should wrap to 0 (no-op)");
    }

    #[test]
    fn eight_turns_wraps_to_noop() {
        let img = asymmetric_image();
        let result = Rotate { quarter_turns: 8 }.apply(img);
        assert!(result.is_none());
    }

    #[test]
    fn rotate_90_transposes_dimensions() {
        let img = asymmetric_image(); // 3×2
        let rotated = Rotate { quarter_turns: 1 }.apply(img).unwrap();
        assert_eq!(rotated.width(), 2, "width should become old height");
        assert_eq!(rotated.height(), 3, "height should become old width");
    }

    #[test]
    fn rotate_180_preserves_dimensions() {
        let img = asymmetric_image(); // 3×2
        let rotated = Rotate { quarter_turns: 2 }.apply(img).unwrap();
        assert_eq!(rotated.width(), 3);
        assert_eq!(rotated.height(), 2);
    }

    #[test]
    fn rotate_270_transposes_dimensions() {
        let img = asymmetric_image(); // 3×2
        let rotated = Rotate { quarter_turns: 3 }.apply(img).unwrap();
        assert_eq!(rotated.width(), 2);
        assert_eq!(rotated.height(), 3);
    }

    #[test]
    fn rotate_90_moves_top_left_to_top_right() {
        // For a 90° CW rotation of a 3×2 image → 2×3 output:
        // Original (0,0) red → goes to (height-1, 0) in rotated = (1, 0)
        let img = asymmetric_image();
        let rotated = Rotate { quarter_turns: 1 }.apply(img).unwrap().into_rgba8();
        // In a 90° CW rotation: new(x,y) = old(y, width-1-x)
        // Original top-left red (0,0) → rotated (1, 0) — bottom-left? No.
        // Standard 90° CW: pixel at (x,y) in source → (h-1-y, x) in dest
        // Source (0,0) → dest (1, 0) in a 3×2→2×3
        let pixel = rotated.get_pixel(1, 0);
        assert_eq!(
            pixel.0,
            [255, 0, 0, 255],
            "red pixel should be at (1,0) after 90° CW"
        );
    }

    #[test]
    fn rotate_180_moves_top_left_to_bottom_right() {
        let img = asymmetric_image(); // 3×2
        let rotated = Rotate { quarter_turns: 2 }.apply(img).unwrap().into_rgba8();
        // 180° rotation: (x,y) → (w-1-x, h-1-y)
        // Source (0,0) red → dest (2, 1)
        let pixel = rotated.get_pixel(2, 1);
        assert_eq!(
            pixel.0,
            [255, 0, 0, 255],
            "red pixel should be at (2,1) after 180°"
        );
    }

    #[test]
    fn rotate_270_moves_top_left_to_bottom_left() {
        let img = asymmetric_image(); // 3×2
        let rotated = Rotate { quarter_turns: 3 }.apply(img).unwrap().into_rgba8();
        // 270° CW (= 90° CCW): (x,y) → (y, w-1-x)
        // Source (0,0) red → dest (0, 2)
        let pixel = rotated.get_pixel(0, 2);
        assert_eq!(
            pixel.0,
            [255, 0, 0, 255],
            "red pixel should be at (0,2) after 270° CW"
        );
    }

    #[test]
    fn five_turns_equivalent_to_one() {
        let img1 = asymmetric_image();
        let img2 = asymmetric_image();
        let r1 = Rotate { quarter_turns: 1 }
            .apply(img1)
            .unwrap()
            .into_rgba8();
        let r5 = Rotate { quarter_turns: 5 }
            .apply(img2)
            .unwrap()
            .into_rgba8();
        assert_eq!(r1.as_raw(), r5.as_raw(), "5 turns should equal 1 turn");
    }

    #[test]
    fn full_cycle_returns_original() {
        let original = asymmetric_image().into_rgba8();
        let img = DynamicImage::ImageRgba8(original.clone());
        // Apply 4 rotations of 90° each
        let r1 = Rotate { quarter_turns: 1 }.apply(img).unwrap();
        let r2 = Rotate { quarter_turns: 1 }.apply(r1).unwrap();
        let r3 = Rotate { quarter_turns: 1 }.apply(r2).unwrap();
        let r4 = Rotate { quarter_turns: 1 }.apply(r3).unwrap().into_rgba8();
        assert_eq!(
            original.as_raw(),
            r4.as_raw(),
            "4×90° should return to original"
        );
    }
}
