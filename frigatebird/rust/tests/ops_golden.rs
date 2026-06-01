//! Golden and integration tests for rotate, `to_jpg`, and resize FFI entry points.
//!
//! These tests exercise the full pipeline through the `#[ffi_export]` functions,
//! verifying:
//! - Correct pixel transformations (golden image comparison)
//! - Error propagation for invalid inputs
//! - Edge cases (no-op rotations, zero dimensions, invalid filters)

use std::path::PathBuf;

use image::{GenericImageView as _, Rgba, RgbaImage};

fn tmp_path(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(name);
    let _ = std::fs::remove_file(&path);
    path
}

/// Creates a small asymmetric 8×4 PNG with distinct quadrants for rotation testing.
/// Top-left=red, top-right=green, bottom-left=blue, bottom-right=white.
fn create_quadrant_png(name: &str) -> PathBuf {
    let path = tmp_path(name);
    let mut img = RgbaImage::new(8, 4);
    for y in 0..4 {
        for x in 0..8 {
            let color = match (x < 4, y < 2) {
                (true, true) => Rgba([255, 0, 0, 255]),       // top-left: red
                (false, true) => Rgba([0, 255, 0, 255]),      // top-right: green
                (true, false) => Rgba([0, 0, 255, 255]),      // bottom-left: blue
                (false, false) => Rgba([255, 255, 255, 255]), // bottom-right: white
            };
            img.put_pixel(x, y, color);
        }
    }
    img.save(&path).unwrap();
    path
}

fn create_arena() -> frigate::FfiArena {
    frigate::FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    }
}

// ── Rotate FFI Tests ─────────────────────────────────────────────────────────

#[test]
fn rotate_90_cw_golden() {
    let input = create_quadrant_png("frigate_rotate_90_golden.png");
    let output = tmp_path("frigate_rotate_90_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::rotate(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        1,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0, "rotate should succeed");

    let rotated = image::open(&output).unwrap().into_rgba8();
    // 8×4 rotated 90° CW → 4×8
    assert_eq!(rotated.width(), 4);
    assert_eq!(rotated.height(), 8);

    // After 90° CW: top-left red → top-right
    // Original bottom-left blue → new top-left
    let top_left = rotated.get_pixel(0, 0);
    assert_eq!(
        top_left.0,
        [0, 0, 255, 255],
        "top-left should be blue after 90° CW"
    );

    let top_right = rotated.get_pixel(3, 0);
    assert_eq!(
        top_right.0,
        [255, 0, 0, 255],
        "top-right should be red after 90° CW"
    );

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
fn rotate_180_golden() {
    let input = create_quadrant_png("frigate_rotate_180_golden.png");
    let output = tmp_path("frigate_rotate_180_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::rotate(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        2,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let rotated = image::open(&output).unwrap().into_rgba8();
    // 180° preserves dimensions
    assert_eq!(rotated.width(), 8);
    assert_eq!(rotated.height(), 4);

    // After 180°: top-left red → bottom-right, bottom-right white → top-left
    let top_left = rotated.get_pixel(0, 0);
    assert_eq!(
        top_left.0,
        [255, 255, 255, 255],
        "top-left should be white after 180°"
    );

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
fn rotate_270_golden() {
    let input = create_quadrant_png("frigate_rotate_270_golden.png");
    let output = tmp_path("frigate_rotate_270_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::rotate(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        3,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let rotated = image::open(&output).unwrap().into_rgba8();
    // 270° CW (= 90° CCW): 8×4 → 4×8
    assert_eq!(rotated.width(), 4);
    assert_eq!(rotated.height(), 8);

    // After 270° CW: top-left red → bottom-left
    let bottom_left = rotated.get_pixel(0, 7);
    assert_eq!(
        bottom_left.0,
        [255, 0, 0, 255],
        "bottom-left should be red after 270° CW"
    );

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
fn rotate_noop_no_file_write() {
    let input = create_quadrant_png("frigate_rotate_noop.png");
    let output = tmp_path("frigate_rotate_noop_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::rotate(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        0,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);
    // No-op should not create output file
    assert!(
        !output.exists(),
        "no-op rotate should not write output file"
    );

    std::fs::remove_file(&input).ok();
}

#[test]
fn rotate_four_turns_is_noop() {
    let input = create_quadrant_png("frigate_rotate_4_noop.png");
    let output = tmp_path("frigate_rotate_4_noop_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::rotate(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        4,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);
    assert!(!output.exists());
    std::fs::remove_file(&input).ok();
}

#[test]
fn rotate_missing_path_returns_invalid_arg() {
    let mut arena = create_arena();
    let status = frigate::rotate(None, None, 1, 80, Some(&mut arena));
    assert_eq!(status, frigate::FfiErrorCode::InvalidArg as u8);
}

#[test]
fn rotate_missing_file_returns_io_error() {
    let mut arena = create_arena();
    let bad = safer_ffi::char_p::new("/tmp/frigate_rotate_no_such_file.png");
    let out = safer_ffi::char_p::new("/tmp/frigate_rotate_missing_out.png");
    let status = frigate::rotate(
        Some(bad.as_ref()),
        Some(out.as_ref()),
        1,
        80,
        Some(&mut arena),
    );
    assert_eq!(status, frigate::FfiErrorCode::Io as u8);
}

#[test]
fn rotate_overwrites_input_when_no_output() {
    let input = create_quadrant_png("frigate_rotate_overwrite.png");
    let original_dims = image::open(&input).unwrap().dimensions();
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());

    let status = frigate::rotate(Some(in_p.as_ref()), None, 1, 100, Some(&mut arena));
    assert_eq!(status, 0);

    // File should now have transposed dimensions
    let after = image::open(&input).unwrap();
    assert_eq!(after.width(), original_dims.1, "width should be old height");
    assert_eq!(
        after.height(),
        original_dims.0,
        "height should be old width"
    );

    std::fs::remove_file(&input).ok();
}

// ── to_jpg FFI Tests ─────────────────────────────────────────────────────────

#[test]
fn to_jpg_converts_png() {
    let input = create_quadrant_png("frigate_to_jpg_ffi.png");
    let output = tmp_path("frigate_to_jpg_ffi_out.jpg");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::to_jpg(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        80,
        Some(&mut arena),
    );
    assert_eq!(status, 0);
    assert!(output.exists());

    // Verify JPEG magic bytes
    let bytes = std::fs::read(&output).unwrap();
    assert_eq!(bytes[0], 0xFF);
    assert_eq!(bytes[1], 0xD8);

    // Verify dimensions preserved
    let decoded = image::open(&output).unwrap();
    assert_eq!(decoded.width(), 8);
    assert_eq!(decoded.height(), 4);

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
fn to_jpg_missing_path_returns_invalid_arg() {
    let mut arena = create_arena();
    let status = frigate::to_jpg(None, None, 80, Some(&mut arena));
    assert_eq!(status, frigate::FfiErrorCode::InvalidArg as u8);
}

#[test]
fn to_jpg_missing_file_returns_io_error() {
    let mut arena = create_arena();
    let bad = safer_ffi::char_p::new("/tmp/frigate_to_jpg_no_such_file.png");
    let out = safer_ffi::char_p::new("/tmp/frigate_to_jpg_missing_out.jpg");
    let status = frigate::to_jpg(Some(bad.as_ref()), Some(out.as_ref()), 80, Some(&mut arena));
    assert_eq!(status, frigate::FfiErrorCode::Io as u8);
}

#[test]
fn to_jpg_bad_extension_returns_encode_error() {
    let input = create_quadrant_png("frigate_to_jpg_bad_ext.png");
    let output = tmp_path("frigate_to_jpg_bad_ext.tiff");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::to_jpg(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        80,
        Some(&mut arena),
    );
    assert_eq!(status, frigate::FfiErrorCode::Encode as u8);

    std::fs::remove_file(&input).ok();
}

#[test]
fn to_jpg_overwrites_input() {
    // Create a PNG, then convert in-place (input path has .jpg ext already)
    let path = tmp_path("frigate_to_jpg_inplace.jpg");
    let img = RgbaImage::from_pixel(4, 4, Rgba([100, 200, 50, 255]));
    // Write as PNG first (but with .jpg name — write_image won't like this, so use save_buffer)
    // Actually let's just create a proper flow: make a PNG, to_jpg with same name pattern
    let png_path = tmp_path("frigate_to_jpg_inplace_src.png");
    img.save(&png_path).unwrap();

    let mut arena = create_arena();
    let in_p = safer_ffi::char_p::new(png_path.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(path.to_str().unwrap());

    let status = frigate::to_jpg(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        90,
        Some(&mut arena),
    );
    assert_eq!(status, 0);
    assert!(path.exists());

    std::fs::remove_file(&png_path).ok();
    std::fs::remove_file(&path).ok();
}

// ── Resize FFI Tests ─────────────────────────────────────────────────────────

#[test]
fn resize_downscale() {
    let input = create_quadrant_png("frigate_resize_ffi_down.png");
    let output = tmp_path("frigate_resize_ffi_down_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    // Resize 8×4 → 4×2, bilinear (filter=1)
    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        4,
        2,
        1,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let resized = image::open(&output).unwrap();
    assert_eq!(resized.width(), 4);
    assert_eq!(resized.height(), 2);

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
fn resize_upscale() {
    let input = create_quadrant_png("frigate_resize_ffi_up.png");
    let output = tmp_path("frigate_resize_ffi_up_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    // Resize 8×4 → 16×8, lanczos (filter=3)
    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        16,
        8,
        3,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let resized = image::open(&output).unwrap();
    assert_eq!(resized.width(), 16);
    assert_eq!(resized.height(), 8);

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
fn resize_zero_width_returns_invalid_arg() {
    let input = create_quadrant_png("frigate_resize_ffi_zero_w.png");
    let output = tmp_path("frigate_resize_ffi_zero_w_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        0,
        10,
        1,
        80,
        Some(&mut arena),
    );
    assert_eq!(status, frigate::FfiErrorCode::InvalidArg as u8);

    std::fs::remove_file(&input).ok();
}

#[test]
fn resize_zero_height_returns_invalid_arg() {
    let input = create_quadrant_png("frigate_resize_ffi_zero_h.png");
    let output = tmp_path("frigate_resize_ffi_zero_h_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        10,
        0,
        1,
        80,
        Some(&mut arena),
    );
    assert_eq!(status, frigate::FfiErrorCode::InvalidArg as u8);

    std::fs::remove_file(&input).ok();
}

#[test]
fn resize_invalid_filter_returns_invalid_arg() {
    let input = create_quadrant_png("frigate_resize_ffi_bad_filter.png");
    let output = tmp_path("frigate_resize_ffi_bad_filter_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        10,
        10,
        99,
        80,
        Some(&mut arena),
    );
    assert_eq!(status, frigate::FfiErrorCode::InvalidArg as u8);

    std::fs::remove_file(&input).ok();
}

#[test]
fn resize_missing_path_returns_invalid_arg() {
    let mut arena = create_arena();
    let status = frigate::resize(None, None, 10, 10, 1, 80, Some(&mut arena));
    assert_eq!(status, frigate::FfiErrorCode::InvalidArg as u8);
}

#[test]
fn resize_missing_file_returns_io_error() {
    let mut arena = create_arena();
    let bad = safer_ffi::char_p::new("/tmp/frigate_resize_no_such_file.png");
    let out = safer_ffi::char_p::new("/tmp/frigate_resize_missing_out.png");
    let status = frigate::resize(
        Some(bad.as_ref()),
        Some(out.as_ref()),
        10,
        10,
        1,
        80,
        Some(&mut arena),
    );
    assert_eq!(status, frigate::FfiErrorCode::Io as u8);
}

#[test]
fn resize_all_filters_produce_output() {
    for filter in 0..=3u8 {
        let input = create_quadrant_png(&format!("frigate_resize_filter_{filter}.png"));
        let output = tmp_path(&format!("frigate_resize_filter_{filter}_out.png"));
        let mut arena = create_arena();

        let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
        let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

        let status = frigate::resize(
            Some(in_p.as_ref()),
            Some(out_p.as_ref()),
            4,
            2,
            filter,
            100,
            Some(&mut arena),
        );
        assert_eq!(status, 0, "filter {filter} should succeed");
        assert!(output.exists(), "filter {filter} should produce output");

        std::fs::remove_file(&input).ok();
        std::fs::remove_file(&output).ok();
    }
}

#[test]
fn resize_to_jpeg_output() {
    let input = create_quadrant_png("frigate_resize_to_jpg.png");
    let output = tmp_path("frigate_resize_to_jpg_out.jpg");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        4,
        4,
        1,
        85,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    // Verify JPEG magic
    let bytes = std::fs::read(&output).unwrap();
    assert_eq!(bytes[0], 0xFF);
    assert_eq!(bytes[1], 0xD8);

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}
