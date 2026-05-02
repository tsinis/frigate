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
pub fn read_image(path: &Path) -> Result<DynamicImage, IoError> {
    image::open(path).map_err(|_| IoError::Decode)
}

/// Read raw font bytes. Returns ownership of the buffer because `ab_glyph::FontRef` borrows from
/// the slice — the `Vec` MUST outlive every `FontRef` created from it.
pub fn read_font(path: &Path) -> Result<Vec<u8>, IoError> {
    std::fs::read(path).map_err(|_| IoError::Read)
}

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
            // JPEG has no alpha channel — `into_rgb8` composites onto opaque black implicitly.
            // We clone the RGBA buffer first because the conversion consumes it; that's one
            // extra allocation per export but keeps the signature `&RgbaImage` (re-usable).
            let rgb = DynamicImage::ImageRgba8(img.clone()).into_rgb8();
            let file = std::fs::File::create(path).map_err(|_| IoError::Write)?;
            let mut writer = std::io::BufWriter::new(file);
            image::codecs::jpeg::JpegEncoder::new_with_quality(&mut writer, image_quality)
                .encode_image(&rgb)
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
    fn read_image_on_missing_file_is_decode_error() {
        // `image::open` returns a decode error kind whether the file is missing or malformed —
        // we map both to `IoError::Decode` because the caller only needs "couldn't get an image".
        let err = read_image(Path::new("/definitely/not/here.png")).unwrap_err();
        assert_eq!(err, IoError::Decode);
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
}
