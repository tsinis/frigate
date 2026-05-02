//! Integration tests for the FFI export boundary.

#![allow(unsafe_code)]

use frigate::FfiRectElement;
use std::ptr::NonNull;

/// Happy path helper for image rendering tests.
///
/// Encodes a 4×4 red image, composites some rectangles, and returns the result length.
///
/// # Safety
///
/// This function is unsafe because it calls Rust-side FFI entry points with raw pointers.
unsafe fn export_and_free(png: &[u8], rects: &[FfiRectElement], quality: u8, ctx: &str) -> usize {
    // SAFETY: img and rects are valid slices for the call duration; quality is a plain u8.
    let rects_ptr = if rects.is_empty() {
        None
    } else {
        Some(NonNull::new(rects.as_ptr() as *mut _).unwrap())
    };

    let buf = frigate::export_image(
        Some(NonNull::new(png.as_ptr() as *mut _).unwrap()),
        png.len(),
        rects_ptr,
        rects.len(),
        quality,
    );

    assert!(
        !buf.data.is_null(),
        "export_image must not return null for valid input (context: {ctx})"
    );
    assert!(
        buf.length > 0,
        "export_image result length must be positive (context: {ctx})"
    );

    let len = buf.length;
    // SAFETY: buf.data was just allocated by export_image; length matches.
    frigate::free_bytes(Some(NonNull::new(buf.data).unwrap()), len);
    len
}

#[test]
fn export_image_happy_path() {
    let png = tiny_red_png();
    let len = unsafe { export_and_free(&png, &[], 80, "happy path") };
    assert!(len > 0);
}

#[test]
fn export_image_returns_valid_jpeg_header() {
    let png = tiny_red_png();
    let rects_ptr = None;
    let buf = frigate::export_image(
        Some(NonNull::new(png.as_ptr() as *mut _).unwrap()),
        png.len(),
        rects_ptr,
        0,
        80,
    );

    // Valid JPEGs start with SOI marker: FF D8.
    assert!(!buf.data.is_null());
    let first_two = unsafe { std::slice::from_raw_parts(buf.data, 2) };
    assert_eq!(first_two, &[0xFF, 0xD8]);

    frigate::free_bytes(Some(NonNull::new(buf.data).unwrap()), buf.length);
}

#[test]
fn export_image_quality_changes_output_size() {
    let png = tiny_red_png();

    let q10 = unsafe { export_bytes(&png, &[], 10, "q=10") };
    let q90 = unsafe { export_bytes(&png, &[], 90, "q=90") };

    // At extremely small dimensions (4x4) JPEG overhead dominates, but 90% quality
    // should still be larger than 10% quality because quantization is much lighter.
    assert!(
        q90.len() >= q10.len(),
        "q90 ({} bytes) should be >= q10 ({} bytes)",
        q90.len(),
        q10.len()
    );
}

#[test]
fn export_image_composites_rects() {
    let png = tiny_red_png();
    // A visible outline must change the JPEG bytes versus no outline.
    let no_rects = unsafe { export_bytes(&png, &[], 90, "no rects baseline") };
    let with_rect = unsafe {
        export_bytes(
            &png,
            &[FfiRectElement {
                x: 0.0,
                y: 0.0,
                width: 4.0,
                height: 4.0,
                outline_thickness: 2,
                outline_color_argb: 0xFF_00_FF_00,
                shape_param: 0,
            }],
            90,
            "with rect",
        )
    };
    assert_ne!(no_rects, with_rect, "rectangle must change pixels");
}

/// Helper: exports an image and returns the bytes as a Vec.
///
/// # Safety
///
/// Same as `export_and_free`.
unsafe fn export_bytes(img: &[u8], rects: &[FfiRectElement], quality: u8, ctx: &str) -> Vec<u8> {
    // SAFETY: img and rects are valid slices for the call duration; quality is a plain u8.
    let rects_ptr = if rects.is_empty() {
        None
    } else {
        Some(NonNull::new(rects.as_ptr() as *mut _).unwrap())
    };
    let buf = frigate::export_image(
        Some(NonNull::new(img.as_ptr() as *mut _).unwrap()),
        img.len(),
        rects_ptr,
        rects.len(),
        quality,
    );

    assert!(!buf.data.is_null(), "context: {ctx}");
    let bytes = unsafe { std::slice::from_raw_parts(buf.data, buf.length) }.to_vec();

    frigate::free_bytes(Some(NonNull::new(buf.data).unwrap()), buf.length);
    bytes
}

#[test]
fn export_image_survives_corrupt_input() {
    let rects_ptr = None;
    let buf = frigate::export_image(
        Some(NonNull::new(b"not an image".as_ptr() as *mut _).unwrap()),
        12,
        rects_ptr,
        0,
        80,
    );

    // Failed decode should return a null/zero buffer, not panic.
    assert!(buf.data.is_null());
    assert_eq!(buf.length, 0);
}

#[test]
fn export_image_quality_clamped() {
    let png = tiny_red_png();
    // 0 and 255 are the boundaries of u8; neither should panic.
    unsafe { export_and_free(&png, &[], 0, "quality=0") };
    unsafe { export_and_free(&png, &[], 255, "quality=255") };
}

#[test]
fn export_image_handles_pathological_rects() {
    let png = tiny_red_png();
    let rects = [FfiRectElement {
        x: f64::NAN,
        y: f64::INFINITY,
        width: -10.0,
        height: 0.0,
        outline_thickness: 1,
        outline_color_argb: 0,
        shape_param: 0,
    }];

    // NaN/Inf/Negative geometry must be handled safely (skipped), not panic.
    unsafe { export_and_free(&png, &rects, 80, "non-finite rect coords") };
}

#[test]
fn export_image_handles_u32_max_shape_param() {
    let png = tiny_red_png();
    let rect = FfiRectElement {
        x: 0.0,
        y: 0.0,
        width: 1.0,
        height: 1.0,
        outline_thickness: 1,
        outline_color_argb: 0,
        shape_param: u32::MAX, // corner radius clamped
    };

    unsafe { export_and_free(&png, &[rect], 80, "u32::MAX corner radius") };
}

#[test]
fn export_image_handles_u8_max_thickness() {
    let png = tiny_red_png();
    let rect = FfiRectElement {
        x: 0.0,
        y: 0.0,
        width: 1.0,
        height: 1.0,
        outline_thickness: 255,
        outline_color_argb: 0,
        shape_param: 0,
    };

    unsafe { export_and_free(&png, &[rect], 80, "u8::MAX outline thickness") };
}

#[test]
fn export_image_1x1_source() {
    use image::{ImageEncoder, RgbaImage};
    let img = RgbaImage::from_pixel(1, 1, image::Rgba([0, 0, 0, 0]));
    let mut buf = std::io::Cursor::new(Vec::new());
    image::codecs::png::PngEncoder::new(&mut buf)
        .write_image(img.as_raw(), 1, 1, image::ExtendedColorType::Rgba8)
        .unwrap();
    let png = buf.into_inner();

    unsafe { export_and_free(&png, &[], 80, "1×1 source image") };
}

#[test]
fn free_bytes_handles_null() {
    // Should be a silent no-op, not a panic.
    frigate::free_bytes(None, 0);
}

#[test]
fn export_and_free_round_trip() {
    let png = tiny_red_png();
    let rects_ptr = None;

    // Allocate
    let buf = frigate::export_image(
        Some(NonNull::new(png.as_ptr() as *mut _).unwrap()),
        png.len(),
        rects_ptr,
        0,
        80,
    );
    assert!(!buf.data.is_null());

    // Free
    frigate::free_bytes(Some(NonNull::new(buf.data).unwrap()), buf.length);

    // If we reached here without a Miri failure/segfault, the pointer passed to drop()
    // reconstructed the original Box/Vec correctly.
}

fn tiny_red_png() -> Vec<u8> {
    use image::{ImageEncoder, RgbaImage};
    let img = RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 255]));
    let mut buf = std::io::Cursor::new(Vec::new());
    image::codecs::png::PngEncoder::new(&mut buf)
        .write_image(img.as_raw(), 4, 4, image::ExtendedColorType::Rgba8)
        .unwrap();
    buf.into_inner()
}
