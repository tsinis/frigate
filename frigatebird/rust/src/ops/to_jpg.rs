//! Format conversion to JPEG.
//!
//! Reads any supported image format (PNG, JPEG) and writes it as JPEG at the specified quality.
//! If the input is already JPEG, it re-encodes at the requested quality (lossy → lossy is
//! accepted for this use case — the caller wants explicit quality control).
//!
//! This op delegates to `io::write_image` for the actual JPEG encoding (alpha → RGB compositing,
//! `BufWriter` flush, quality param). The output path MUST have a `.jpg` or `.jpeg` extension.

use std::path::Path;

use crate::io::{self, IoError};

/// Converts an image file to JPEG format.
pub struct ToJpg {
    /// JPEG quality (0..=100). Higher = better quality, larger file.
    pub quality: u8,
}

impl ToJpg {
    /// Read image from `input`, write as JPEG to `output`.
    ///
    /// If `output` is the same as `input`, the file is overwritten in place.
    /// The output path extension determines the format — it MUST be `.jpg` or `.jpeg`.
    pub fn apply(&self, input: &Path, output: &Path) -> Result<(), IoError> {
        let img = io::read_image(input)?;
        let rgba = img.into_rgba8();
        io::write_image(output, &rgba, self.quality)
    }
}

#[cfg(all(test, not(miri)))]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};
    use std::path::PathBuf;

    fn tmp_path(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(name);
        let _ = std::fs::remove_file(&path);
        path
    }

    fn create_test_png(name: &str) -> PathBuf {
        let path = tmp_path(name);
        let mut img = RgbaImage::new(4, 4);
        for y in 0..4 {
            for x in 0..4 {
                img.put_pixel(x, y, Rgba([255, 0, 0, 255]));
            }
        }
        img.save(&path).unwrap();
        path
    }

    #[test]
    fn converts_png_to_jpg() {
        let input = create_test_png("frigate_to_jpg_input.png");
        let output = tmp_path("frigate_to_jpg_output.jpg");

        let result = ToJpg { quality: 80 }.apply(&input, &output);
        assert!(result.is_ok());
        assert!(output.exists(), "output JPEG should exist");

        // Verify it's actually a JPEG (starts with FF D8 magic bytes)
        let bytes = std::fs::read(&output).unwrap();
        assert!(bytes.len() > 2);
        assert_eq!(bytes[0], 0xFF);
        assert_eq!(bytes[1], 0xD8);

        std::fs::remove_file(&input).ok();
        std::fs::remove_file(&output).ok();
    }

    #[test]
    fn reencodes_jpg_to_jpg() {
        // Create a JPEG first
        let png_input = create_test_png("frigate_to_jpg_reencode_src.png");
        let jpg_input = tmp_path("frigate_to_jpg_reencode_input.jpg");
        ToJpg { quality: 90 }.apply(&png_input, &jpg_input).unwrap();

        // Re-encode the JPEG at lower quality
        let output = tmp_path("frigate_to_jpg_reencode_output.jpg");
        let result = ToJpg { quality: 30 }.apply(&jpg_input, &output);
        assert!(result.is_ok());

        // Lower quality should produce a smaller file
        let high_size = std::fs::metadata(&jpg_input).unwrap().len();
        let low_size = std::fs::metadata(&output).unwrap().len();
        assert!(
            low_size <= high_size,
            "quality=30 ({low_size}B) should be <= quality=90 ({high_size}B)"
        );

        std::fs::remove_file(&png_input).ok();
        std::fs::remove_file(&jpg_input).ok();
        std::fs::remove_file(&output).ok();
    }

    #[test]
    fn quality_zero_produces_smallest() {
        let input = create_test_png("frigate_to_jpg_q0_input.png");
        let out_q0 = tmp_path("frigate_to_jpg_q0.jpg");
        let out_q100 = tmp_path("frigate_to_jpg_q100.jpg");

        ToJpg { quality: 0 }.apply(&input, &out_q0).unwrap();
        ToJpg { quality: 100 }.apply(&input, &out_q100).unwrap();

        let size_q0 = std::fs::metadata(&out_q0).unwrap().len();
        let size_q100 = std::fs::metadata(&out_q100).unwrap().len();
        assert!(
            size_q0 < size_q100,
            "quality=0 ({size_q0}B) should be < quality=100 ({size_q100}B)"
        );

        std::fs::remove_file(&input).ok();
        std::fs::remove_file(&out_q0).ok();
        std::fs::remove_file(&out_q100).ok();
    }

    #[test]
    fn error_on_missing_input() {
        let input = Path::new("/tmp/frigate_to_jpg_nonexistent.png");
        let output = tmp_path("frigate_to_jpg_missing_out.jpg");
        let result = ToJpg { quality: 80 }.apply(input, &output);
        assert_eq!(result.unwrap_err(), IoError::Read);
    }

    #[test]
    fn error_on_unsupported_output_extension() {
        let input = create_test_png("frigate_to_jpg_bad_ext_input.png");
        let output = tmp_path("frigate_to_jpg_bad_ext_output.tiff");
        let result = ToJpg { quality: 80 }.apply(&input, &output);
        assert_eq!(result.unwrap_err(), IoError::UnsupportedFormat);
        std::fs::remove_file(&input).ok();
    }

    #[test]
    fn overwrite_in_place() {
        // Create a PNG, convert to JPG at a temp path, then overwrite it
        let input = create_test_png("frigate_to_jpg_overwrite_src.png");
        let jpg_path = tmp_path("frigate_to_jpg_overwrite.jpg");
        ToJpg { quality: 80 }.apply(&input, &jpg_path).unwrap();

        let original_size = std::fs::metadata(&jpg_path).unwrap().len();

        // Re-encode in place at different quality
        let result = ToJpg { quality: 50 }.apply(&jpg_path, &jpg_path);
        assert!(result.is_ok());

        let new_size = std::fs::metadata(&jpg_path).unwrap().len();
        // Sizes should differ (different quality)
        assert_ne!(original_size, new_size);

        std::fs::remove_file(&input).ok();
        std::fs::remove_file(&jpg_path).ok();
    }

    #[test]
    fn preserves_image_dimensions() {
        let input = create_test_png("frigate_to_jpg_dims_input.png");
        let output = tmp_path("frigate_to_jpg_dims_output.jpg");
        ToJpg { quality: 80 }.apply(&input, &output).unwrap();

        let decoded = image::open(&output).unwrap();
        assert_eq!(decoded.width(), 4);
        assert_eq!(decoded.height(), 4);

        std::fs::remove_file(&input).ok();
        std::fs::remove_file(&output).ok();
    }

    #[test]
    fn handles_transparent_pixels() {
        // JPEG has no alpha — transparent pixels should composite onto black
        let path = tmp_path("frigate_to_jpg_alpha_input.png");
        let mut img = RgbaImage::new(2, 2);
        img.put_pixel(0, 0, Rgba([255, 0, 0, 0])); // fully transparent red
        img.put_pixel(1, 0, Rgba([0, 255, 0, 128])); // semi-transparent green
        img.put_pixel(0, 1, Rgba([0, 0, 255, 255])); // opaque blue
        img.put_pixel(1, 1, Rgba([255, 255, 255, 255])); // opaque white
        img.save(&path).unwrap();

        let output = tmp_path("frigate_to_jpg_alpha_output.jpg");
        let result = ToJpg { quality: 100 }.apply(&path, &output);
        assert!(result.is_ok());

        // Decode and check: fully transparent pixel → near-black
        let decoded = image::open(&output).unwrap().into_rgb8();
        let px = decoded.get_pixel(0, 0);
        // JPEG compression may introduce tiny artifacts, allow tolerance
        assert!(
            px.0[0] < 10 && px.0[1] < 10 && px.0[2] < 10,
            "transparent red → near-black"
        );

        std::fs::remove_file(&path).ok();
        std::fs::remove_file(&output).ok();
    }
}
