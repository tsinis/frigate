//! Reusable file-system helpers.
//!
//! All FFI-facing image features that need to read/write files on disk go through this module so
//! path handling, codec dispatch, and error mapping live in one place.
//!
//! We deliberately stay on `std::fs` + the `image` crate — there isn't a well-known "better" IO
//! crate that would save meaningful code here. Adding one (e.g. `fs_err` for path-attached
//! errors) is easy later if we ever need to ship a user-visible I/O error with the failing path.

use std::io::Write;
use std::path::Path;

use image::{DynamicImage, RgbaImage};

/// Typed errors for I/O operations. Each variant maps to a distinct FFI error code in `lib.rs`.
///
/// Kept as a bare enum (not boxed `dyn Error`) so the happy-path conversion stays cheap and the
/// mapping to i32 is exhaustive.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IoError {
    /// `std::fs::read` (or similar) returned an error — missing file, permissions, etc.
    Read,
    /// File was read but its bytes could not be decoded by the `image` crate.
    Decode,
    /// Writing encoded bytes to disk failed (usually out-of-space or permission).
    Write,
    /// Encoder returned an error while producing the output bytes.
    Encode,
    /// Output file extension does not map to a supported encoder.
    UnsupportedFormat,
}

/// Decode an image from disk. Format is auto-detected by the `image` crate from the file contents
/// (magic bytes), not from the extension — so a mis-labelled `.jpg` that's actually a PNG still
/// decodes correctly.
///
/// This function automatically applies EXIF orientation to the image so that the resulting
/// `DynamicImage` is physically oriented correctly.
///
/// Reads the file bytes once and parses both the image and EXIF from the same buffer,
/// avoiding a second file open for orientation detection.
pub fn read_image(path: &Path) -> Result<DynamicImage, IoError> {
    let bytes = std::fs::read(path).map_err(|_| IoError::Read)?;
    let orientation = read_orientation_from_bytes(&bytes);
    let mut img = image::load_from_memory(&bytes).map_err(|_| IoError::Decode)?;
    if orientation > 1 {
        img = apply_orientation(img, orientation);
    }
    Ok(img)
}

/// Reads the EXIF orientation tag from raw file bytes.
/// Returns a value in the range 1..=8. Returns 1 if no orientation is found or on any error.
fn read_orientation_from_bytes(bytes: &[u8]) -> u8 {
    let mut cursor = std::io::Cursor::new(bytes);
    let Ok(exif) = exif::Reader::new().read_from_container(&mut cursor) else {
        return 1;
    };

    exif.get_field(exif::Tag::Orientation, exif::In::PRIMARY)
        .and_then(|f| f.value.get_uint(0))
        .and_then(|v| {
            if (1..=8).contains(&v) {
                Some(v as u8)
            } else {
                None
            }
        })
        .unwrap_or(1)
}

/// Reads the EXIF orientation tag from an image file via a separate file open.
///
/// Used only by `get_image_info` which needs orientation without fully decoding the image.
/// A separate file open is acceptable here because both `ImageReader::into_dimensions()` and
/// this function only read small headers — far cheaper than loading the entire file into memory.
///
/// Returns a value in the range 1..=8. Returns 1 if no orientation is found or on any error.
pub(crate) fn read_orientation(path: &Path) -> u8 {
    let Ok(file) = std::fs::File::open(path) else {
        return 1;
    };
    let mut reader = std::io::BufReader::new(file);
    let Ok(exif) = exif::Reader::new().read_from_container(&mut reader) else {
        return 1;
    };

    let orientation = exif
        .get_field(exif::Tag::Orientation, exif::In::PRIMARY)
        .and_then(|f| f.value.get_uint(0))
        .and_then(|v| {
            if (1..=8).contains(&v) {
                Some(v as u8)
            } else {
                None
            }
        });

    orientation.unwrap_or(1)
}

fn apply_orientation(img: DynamicImage, orientation: u8) -> DynamicImage {
    // Standard EXIF orientation mapping:
    // 1: Horizontal (normal)
    // 2: Mirror horizontal
    // 3: Rotate 180
    // 4: Mirror vertical
    // 5: Transpose (Rotate 90 CW then Mirror horizontal)
    // 6: Rotate 90 CW
    // 7: Transverse (Rotate 270 CW then Mirror horizontal)
    // 8: Rotate 270 CW
    match orientation {
        2 => img.fliph(),
        3 => img.rotate180(),
        4 => img.flipv(),
        5 => img.rotate90().fliph(),
        6 => img.rotate90(),
        7 => img.rotate270().fliph(),
        8 => img.rotate270(),
        _ => img,
    }
}

/// Read raw font bytes. Returns ownership of the buffer because `ab_glyph::FontRef` borrows from
/// the slice — the `Vec` MUST outlive every `FontRef` created from it.
pub fn read_font(path: &Path) -> Result<Vec<u8>, IoError> {
    std::fs::read(path).map_err(|_| IoError::Read)
}

// IMPORTANT: Output must NEVER contain an EXIF Orientation tag.
// Pixels are already physically rotated by read_image. Writing an Orientation tag would cause double-rotation in any consumer.
/// Encode and write an RGBA image. Format is dispatched by file extension:
///   - `.png`  → lossless PNG, alpha preserved, `image_quality` ignored.
///   - `.jpg`/`.jpeg` → JPEG, alpha flattened to opaque black, `image_quality` applied (0..=100).
///
/// Any other extension returns `IoError::UnsupportedFormat` — we prefer an explicit error over a
/// silent fallback so the caller can surface a typed `RenderException` to the user.
pub fn write_image(path: &Path, img: &RgbaImage, image_quality: u8) -> Result<(), IoError> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_ascii_lowercase());

    match ext.as_deref() {
        Some("png") => img.save(path).map_err(|_| IoError::Write),
        Some("jpg") | Some("jpeg") => {
            // JPEG has no alpha channel. Convert RGBA → RGB in-place without cloning the
            // entire RgbaImage. We allocate only the 3-byte-per-pixel RGB buffer (75% of
            // the original 4-byte data), avoiding the old approach which cloned the full
            // 4-byte buffer just to call `into_rgb8()`.
            let (w, h) = img.dimensions();
            let mut rgb_buf = Vec::with_capacity((w as usize) * (h as usize) * 3);
            for chunk in img.as_raw().chunks_exact(4) {
                // Alpha compositing onto opaque black: rgb_out = rgb * a / 255.
                let r = chunk[0];
                let g = chunk[1];
                let b = chunk[2];
                let a = chunk[3];
                if a == 255 {
                    rgb_buf.push(r);
                    rgb_buf.push(g);
                    rgb_buf.push(b);
                } else if a == 0 {
                    rgb_buf.push(0);
                    rgb_buf.push(0);
                    rgb_buf.push(0);
                } else {
                    let alpha = a as u16;
                    rgb_buf.push(((r as u16 * alpha) / 255) as u8);
                    rgb_buf.push(((g as u16 * alpha) / 255) as u8);
                    rgb_buf.push(((b as u16 * alpha) / 255) as u8);
                }
            }
            let file = std::fs::File::create(path).map_err(|_| IoError::Write)?;
            let mut writer = std::io::BufWriter::new(file);
            image::codecs::jpeg::JpegEncoder::new_with_quality(&mut writer, image_quality)
                .encode(&rgb_buf, w, h, image::ExtendedColorType::Rgb8)
                .map_err(|_| IoError::Encode)?;
            // BufWriter's Drop impl silently swallows write errors. Flush explicitly so a
            // full-disk / permission-denied at the final buffer-drain surfaces as IoError::Write
            // instead of a zero-byte "success".
            writer.flush().map_err(|_| IoError::Write)
        }
        _ => Err(IoError::UnsupportedFormat),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_path(name: &str) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(name);
        let _ = std::fs::remove_file(&path);
        path
    }

    #[test]
    fn write_image_rejects_unsupported_extension() {
        let img = RgbaImage::from_pixel(1, 1, image::Rgba([0, 0, 0, 255]));
        let tmp = tmp_path("frigate_io_bad.tiff");
        let err = write_image(&tmp, &img, 80).unwrap_err();
        assert_eq!(err, IoError::UnsupportedFormat);
    }

    #[test]
    fn write_image_rejects_path_without_extension() {
        let img = RgbaImage::from_pixel(1, 1, image::Rgba([0, 0, 0, 255]));
        let tmp = tmp_path("frigate_io_no_ext");
        let err = write_image(&tmp, &img, 80).unwrap_err();
        assert_eq!(err, IoError::UnsupportedFormat);
    }

    #[test]
    fn write_image_matches_extension_case_insensitively() {
        let img = RgbaImage::from_pixel(2, 2, image::Rgba([10, 20, 30, 255]));
        let tmp = tmp_path("frigate_io_upper.PNG");
        write_image(&tmp, &img, 100).unwrap();
        assert!(tmp.exists());
        std::fs::remove_file(&tmp).ok();
    }

    #[test]
    fn write_and_read_png_roundtrip() {
        let img = RgbaImage::from_pixel(4, 4, image::Rgba([10, 20, 30, 255]));
        let tmp = tmp_path("frigate_io_roundtrip.png");
        write_image(&tmp, &img, 100).unwrap();
        let decoded = read_image(&tmp).unwrap().into_rgba8();
        assert_eq!(decoded.dimensions(), (4, 4));
        assert_eq!(decoded.get_pixel(0, 0).0, [10, 20, 30, 255]);
        std::fs::remove_file(&tmp).ok();
    }

    #[test]
    fn read_image_on_missing_file_is_read_error() {
        // A missing file is an I/O failure (IoError::Read), not a decode failure.
        let err = read_image(Path::new("/definitely/not/here.png")).unwrap_err();
        assert_eq!(err, IoError::Read);
    }

    #[test]
    fn read_font_on_missing_file_is_read_error() {
        let err = read_font(Path::new("/definitely/not/here.ttf")).unwrap_err();
        assert_eq!(err, IoError::Read);
    }

    #[test]
    fn write_image_jpeg_creates_a_valid_jpeg_header() {
        let img = RgbaImage::from_pixel(2, 2, image::Rgba([255, 0, 0, 255]));
        let tmp = tmp_path("frigate_io_roundtrip.jpg");
        write_image(&tmp, &img, 80).unwrap();
        let bytes = std::fs::read(&tmp).unwrap();
        // JPEG SOI marker.
        assert_eq!(&bytes[..2], &[0xFF, 0xD8]);
        std::fs::remove_file(&tmp).ok();
    }

    #[test]
    fn read_orientation_on_missing_file_is_1() {
        assert_eq!(read_orientation(Path::new("not_here.jpg")), 1);
    }

    #[test]
    fn read_orientation_on_non_image_is_1() {
        assert_eq!(read_orientation(Path::new("Cargo.toml")), 1);
    }

    #[test]
    fn write_image_jpeg_alpha_composites_onto_black() {
        // Semi-transparent red pixel: after compositing onto black, the JPEG should
        // encode approximately (r*a/255, 0, 0) = (128*128/255 ≈ 64, 0, 0).
        let img = RgbaImage::from_pixel(4, 4, image::Rgba([128, 0, 0, 128]));
        let tmp = tmp_path("frigate_io_alpha_composite.jpg");
        write_image(&tmp, &img, 100).unwrap();

        // Read back and verify the red channel is approximately correct (JPEG is lossy).
        let decoded = image::open(&tmp).unwrap().into_rgb8();
        let px = decoded.get_pixel(0, 0).0;
        // Expected: 128*128/255 ≈ 64. JPEG at quality 100 should be within ±5.
        assert!(
            (px[0] as i32 - 64).unsigned_abs() <= 5,
            "red channel should be ~64, got {}",
            px[0]
        );
        assert!(px[1] <= 5, "green should be ~0, got {}", px[1]);
        assert!(px[2] <= 5, "blue should be ~0, got {}", px[2]);
        std::fs::remove_file(&tmp).ok();
    }

    #[test]
    fn write_image_jpeg_fully_transparent_produces_black() {
        let img = RgbaImage::from_pixel(4, 4, image::Rgba([255, 128, 64, 0]));
        let tmp = tmp_path("frigate_io_transparent_jpeg.jpg");
        write_image(&tmp, &img, 100).unwrap();

        let decoded = image::open(&tmp).unwrap().into_rgb8();
        let px = decoded.get_pixel(0, 0).0;
        // Fully transparent composited onto black = pure black.
        assert!(
            px[0] <= 2 && px[1] <= 2 && px[2] <= 2,
            "expected black, got {px:?}"
        );
        std::fs::remove_file(&tmp).ok();
    }
}
