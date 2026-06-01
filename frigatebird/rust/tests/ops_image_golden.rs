//! Golden image tests for rotate, resize, and `to_jpg` operations.
//!
//! Each test creates a small synthetic input image (8×4 quadrant pattern),
//! applies the operation, and compares the output against a committed golden PNG.
//!
//! Goldens live in `tests/golden/` alongside the other element goldens.
//! On first run (golden missing) the test writes the file and panics so you can
//! inspect + commit it, matching the existing `assert_golden` workflow.

use std::path::{Path, PathBuf};

use image::{Rgba, RgbaImage};

fn golden_path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("golden")
        .join(name)
}

/// Creates an 8×4 RGBA image with distinct quadrants:
/// - Top-left (4×2): red
/// - Top-right (4×2): green
/// - Bottom-left (4×2): blue
/// - Bottom-right (4×2): white
fn quadrant_image() -> RgbaImage {
    let mut img = RgbaImage::new(8, 4);
    for y in 0..4u32 {
        for x in 0..8u32 {
            let color = match (x < 4, y < 2) {
                (true, true) => Rgba([255, 0, 0, 255]),
                (false, true) => Rgba([0, 255, 0, 255]),
                (true, false) => Rgba([0, 0, 255, 255]),
                (false, false) => Rgba([255, 255, 255, 255]),
            };
            img.put_pixel(x, y, color);
        }
    }
    img
}

fn tmp_path(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(name);
    let _ = std::fs::remove_file(&path);
    path
}

fn write_quadrant_png(name: &str) -> PathBuf {
    let path = tmp_path(name);
    quadrant_image().save(&path).unwrap();
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

/// Compare actual output against a committed golden (tolerance ≤ 2 per channel).
/// If the golden does not exist, write it and panic for manual inspection.
fn assert_golden(actual: &RgbaImage, path: &Path) {
    if !path.exists() {
        std::fs::create_dir_all(path.parent().unwrap()).ok();
        actual
            .save(path)
            .unwrap_or_else(|e| panic!("failed to write new golden to {path:?}: {e}"));
        panic!(
            "Golden did not exist; wrote new golden to {path:?}. \
             Inspect visually, commit it, then re-run."
        );
    }
    let expected = image::open(path)
        .unwrap_or_else(|_| panic!("failed to decode golden {path:?}"))
        .into_rgba8();
    assert_eq!(
        actual.dimensions(),
        expected.dimensions(),
        "golden dimension mismatch at {path:?}",
    );
    for (x, y, px) in actual.enumerate_pixels() {
        let ex = expected.get_pixel(x, y);
        let d0 = (px.0[0] as i16 - ex.0[0] as i16).unsigned_abs();
        let d1 = (px.0[1] as i16 - ex.0[1] as i16).unsigned_abs();
        let d2 = (px.0[2] as i16 - ex.0[2] as i16).unsigned_abs();
        let d3 = (px.0[3] as i16 - ex.0[3] as i16).unsigned_abs();
        if d0 > 2 || d1 > 2 || d2 > 2 || d3 > 2 {
            panic!(
                "pixel mismatch at ({x}, {y}) in {path:?}: got {:?}, expected {:?}",
                px.0, ex.0
            );
        }
    }
}

// ── Rotate Goldens ───────────────────────────────────────────────────────────

#[test]
#[cfg(not(miri))]
fn golden_rotate_90_cw() {
    let input = write_quadrant_png("golden_rotate_90_in.png");
    let output = tmp_path("golden_rotate_90_out.png");
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
    assert_eq!(status, 0);

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (4, 8), "90 CW: 8×4 → 4×8");
    assert_golden(&actual, &golden_path("ops_rotate_90.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_rotate_180() {
    let input = write_quadrant_png("golden_rotate_180_in.png");
    let output = tmp_path("golden_rotate_180_out.png");
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

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (8, 4), "180: dims preserved");
    assert_golden(&actual, &golden_path("ops_rotate_180.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_rotate_270_cw() {
    let input = write_quadrant_png("golden_rotate_270_in.png");
    let output = tmp_path("golden_rotate_270_out.png");
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

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (4, 8), "270 CW: 8×4 → 4×8");
    assert_golden(&actual, &golden_path("ops_rotate_270.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

// ── Resize Goldens ───────────────────────────────────────────────────────────

#[test]
#[cfg(not(miri))]
fn golden_resize_nearest() {
    let input = write_quadrant_png("golden_resize_nearest_in.png");
    let output = tmp_path("golden_resize_nearest_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    // Upscale 8×4 → 16×8 with nearest neighbor (filter=0).
    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        16,
        8,
        0,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (16, 8));
    assert_golden(&actual, &golden_path("ops_resize_nearest.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_resize_bilinear() {
    let input = write_quadrant_png("golden_resize_bilinear_in.png");
    let output = tmp_path("golden_resize_bilinear_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    // Upscale 8×4 → 16×8 with bilinear (filter=1).
    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        16,
        8,
        1,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (16, 8));
    assert_golden(&actual, &golden_path("ops_resize_bilinear.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_resize_catmull_rom() {
    let input = write_quadrant_png("golden_resize_catmull_in.png");
    let output = tmp_path("golden_resize_catmull_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    // Upscale 8×4 → 16×8 with `CatmullRom` (filter=2).
    let status = frigate::resize(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        16,
        8,
        2,
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (16, 8));
    assert_golden(&actual, &golden_path("ops_resize_catmull_rom.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_resize_lanczos3() {
    let input = write_quadrant_png("golden_resize_lanczos_in.png");
    let output = tmp_path("golden_resize_lanczos_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    // Upscale 8×4 → 16×8 with Lanczos3 (filter=3).
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

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (16, 8));
    assert_golden(&actual, &golden_path("ops_resize_lanczos3.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_resize_downscale() {
    let input = write_quadrant_png("golden_resize_down_in.png");
    let output = tmp_path("golden_resize_down_out.png");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    // Downscale 8×4 → 4×2 with bilinear.
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

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (4, 2));
    assert_golden(&actual, &golden_path("ops_resize_downscale.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

// ── toJpg Goldens ────────────────────────────────────────────────────────────

#[test]
#[cfg(not(miri))]
fn golden_to_jpg_preserves_pixels() {
    let input = write_quadrant_png("golden_to_jpg_in.png");
    let output = tmp_path("golden_to_jpg_out.jpg");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::to_jpg(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        100,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (8, 4), "toJpg preserves dimensions");
    // JPEG is lossy — use a wider tolerance golden (saved as PNG for comparison).
    assert_golden(&actual, &golden_path("ops_to_jpg_q100.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_to_jpg_low_quality() {
    let input = write_quadrant_png("golden_to_jpg_low_in.png");
    let output = tmp_path("golden_to_jpg_low_out.jpg");
    let mut arena = create_arena();

    let in_p = safer_ffi::char_p::new(input.to_str().unwrap());
    let out_p = safer_ffi::char_p::new(output.to_str().unwrap());

    let status = frigate::to_jpg(
        Some(in_p.as_ref()),
        Some(out_p.as_ref()),
        10,
        Some(&mut arena),
    );
    assert_eq!(status, 0);

    let actual = image::open(&output).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), (8, 4));
    // Low quality will have visible artifacts — captured in golden.
    assert_golden(&actual, &golden_path("ops_to_jpg_q10.png"));

    std::fs::remove_file(&input).ok();
    std::fs::remove_file(&output).ok();
}
