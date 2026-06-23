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
    /// File was read but is incomplete/truncated — e.g. a JPEG missing its trailing EOI marker.
    /// Detected *before* decode because zune-jpeg (the `image`-crate JPEG backend) would otherwise
    /// silently return a partially-decoded, grey-filled buffer with `Ok` instead of an error.
    Truncated,
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
    ensure_complete_jpeg(&bytes)?;
    let orientation = read_orientation_from_bytes(&bytes);
    let mut img = image::load_from_memory(&bytes).map_err(|_| IoError::Decode)?;
    if orientation > 1 {
        img = apply_orientation(img, orientation);
    }
    Ok(img)
}

/// Reject incomplete JPEG inputs *before* decoding.
///
/// A complete JPEG always ends with the EOI marker `0xFF 0xD9` as its **final two bytes**. We
/// check only those two bytes — not the entire file — for two reasons:
///
/// 1. **Correctness**: JPEG files often embed EXIF thumbnails near the beginning of the file.
///    Those thumbnails are self-contained JPEGs and contain their own interior `0xFF 0xD9` EOI
///    markers. A file-wide scan would find a thumbnail's EOI and incorrectly report a truncated
///    main image as complete. Checking only the last two bytes is the spec-correct check.
/// 2. **Performance**: O(1) regardless of file size.
///
/// Without this guard, zune-jpeg decodes a truncated JPEG *non-strictly*: it returns `Ok` with
/// the undecoded region reconstructed to mid-grey (128, the IDCT level-shift default), silently
/// producing a half-grey output image. We fail loud instead.
///
/// Only JPEG is checked here; PNG/other inputs are left to the (already strict) `image` decoders.
fn ensure_complete_jpeg(bytes: &[u8]) -> Result<(), IoError> {
    if bytes.starts_with(&[0xFF, 0xD8]) && !bytes.ends_with(&[0xFF, 0xD9]) {
        return Err(IoError::Truncated);
    }
    Ok(())
}

/// Extracts and validates the EXIF orientation tag from an existing Exif container.
/// Returns a value in 1..=8, or None if invalid or missing.
fn extract_orientation(exif: &exif::Exif) -> Option<u8> {
    exif.get_field(exif::Tag::Orientation, exif::In::PRIMARY)
        .and_then(|f| f.value.get_uint(0))
        .and_then(|v| {
            if (1..=8).contains(&v) {
                Some(v as u8)
            } else {
                None
            }
        })
}

/// Reads the EXIF orientation tag from raw file bytes.
/// Returns a value in the range 1..=8. Returns 1 if no orientation is found or on any error.
fn read_orientation_from_bytes(bytes: &[u8]) -> u8 {
    let mut cursor = std::io::Cursor::new(bytes);
    let Ok(exif) = exif::Reader::new().read_from_container(&mut cursor) else {
        return 1;
    };

    extract_orientation(&exif).unwrap_or(1)
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

    extract_orientation(&exif).unwrap_or(1)
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

    #[test]
    fn apply_orientation_ignores_invalid_values() {
        let img = RgbaImage::from_pixel(2, 2, image::Rgba([0, 0, 0, 255]));
        let dyn_img = DynamicImage::ImageRgba8(img);
        let res = apply_orientation(dyn_img, 9);
        assert_eq!(res.width(), 2);
    }

    /// Builds a gradient image whose JPEG carries substantial entropy-coded scan data, so
    /// truncating the encoded bytes lands inside the scan (header intact) — the real-world
    /// torn-file shape — rather than inside the tiny header of a flat-colour image.
    ///
    /// Encodes in-memory (no temp file) so parallel tests cannot race on a shared path.
    fn gradient_jpeg_bytes() -> Vec<u8> {
        let mut img = RgbaImage::new(256, 256);
        for (x, y, px) in img.enumerate_pixels_mut() {
            *px = image::Rgba([(x % 256) as u8, (y % 256) as u8, ((x + y) % 256) as u8, 255]);
        }
        let (w, h) = img.dimensions();
        // JPEG has no alpha channel — strip it to plain RGB first.
        let rgb: Vec<u8> = img
            .as_raw()
            .chunks_exact(4)
            .flat_map(|c| [c[0], c[1], c[2]])
            .collect();
        let mut buf = Vec::new();
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, 85)
            .encode(&rgb, w, h, image::ExtendedColorType::Rgb8)
            .expect("gradient JPEG encode must succeed");
        buf
    }

    #[test]
    fn ensure_complete_jpeg_is_not_fooled_by_interior_eoi() {
        // Regression for false-positive: JPEG files often embed thumbnails in APP1/EXIF data.
        // Those thumbnails are self-contained JPEGs and contain their own 0xFF 0xD9 EOI markers
        // near the START of the file. A backward window scan finds that interior EOI and
        // incorrectly reports the file as complete, even when the main scan is truncated.
        //
        // The fix (check only the final 2 bytes) must NOT be fooled by this.
        let mut bytes = vec![
            0xFF, 0xD8, // SOI
            0xFF, 0xE1, // APP1 (EXIF block)
            0xFF, 0xD9, // Interior EOI — simulates embedded thumbnail's EOI inside EXIF
            0xAB, 0xCD, 0xEF, // Truncated scan data — no terminal EOI follows
        ];
        // Sanity: the interior EOI is present but the file doesn't end with it.
        assert!(!bytes.ends_with(&[0xFF, 0xD9]));
        // The function must detect truncation despite the interior 0xFF 0xD9.
        assert_eq!(
            ensure_complete_jpeg(&bytes),
            Err(IoError::Truncated),
            "interior EOI from EXIF thumbnail must not mask a truncated main image"
        );
        // A trailing byte appended so the file ends in a non-EOI byte also fails.
        bytes.push(0x00);
        assert_eq!(ensure_complete_jpeg(&bytes), Err(IoError::Truncated));
    }

    #[test]
    fn read_image_rejects_truncated_jpeg() {
        // Regression for the rare "bottom-of-image-is-grey" bug: a torn/partial JPEG. The image
        // crate's JPEG backend decodes this to a grey-filled buffer and returns Ok; read_image
        // must instead fail loud so the caller never renders onto garbage pixels.
        let mut bytes = gradient_jpeg_bytes();
        assert!(bytes.len() > 64, "sanity: a real JPEG was produced");
        // Keep the header + part of the scan; drop the trailing EOI (0xFF 0xD9) marker.
        bytes.truncate(bytes.len() * 6 / 10);
        let tmp = tmp_path("frigate_io_truncated.jpg");
        std::fs::write(&tmp, &bytes).unwrap();

        let err = read_image(&tmp).unwrap_err();
        assert_eq!(
            err,
            IoError::Truncated,
            "a truncated JPEG must fail loud, not silently decode to grey"
        );
        std::fs::remove_file(&tmp).ok();
    }

    #[test]
    fn read_image_accepts_a_complete_jpeg() {
        // The gate must be a no-op for valid JPEGs — no false positives on good input.
        let bytes = gradient_jpeg_bytes();
        let tmp = tmp_path("frigate_io_complete.jpg");
        std::fs::write(&tmp, &bytes).unwrap();
        let decoded = read_image(&tmp).unwrap().into_rgba8();
        assert_eq!(decoded.dimensions(), (256, 256));
        std::fs::remove_file(&tmp).ok();
    }

    #[test]
    fn image_crate_decodes_truncated_jpeg_without_error() {
        // Documents the root cause the gate defends against: the underlying decoder accepts a
        // truncated JPEG WITHOUT error (this bypasses read_image's gate by calling the decoder
        // directly). This silent success is exactly why a higher-level integrity check is required.
        let mut bytes = gradient_jpeg_bytes();
        bytes.truncate(bytes.len() * 6 / 10);
        assert!(
            image::load_from_memory(&bytes).is_ok(),
            "image crate silently decodes a truncated JPEG; read_image now gates this"
        );
    }
}
