//! Golden + behavioral tests for the `compose` FFI entry point.
//!
//! `compose` applies the unified background-tool pipeline (original image space, crop last):
//! full-image blur → tint → draw shapes → composite a sharp foreground → crop.
//!
//! Goldens cover blur-only, tint-only, shapes-then-foreground ordering, crop, and the full
//! pipeline. Behavioral tests cover passthrough, JPEG output, and the error paths.
#![allow(unsafe_code)]

use std::ffi::CString;
use std::path::{Path, PathBuf};

use image::RgbaImage;

use frigate::{
    FfiArena, FfiElement, FfiErrorCode, OvalPayload, PolygonPayload, RectanglePayload, TextPayload,
};

fn assets_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/assets")
}

fn golden_path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("golden")
        .join(name)
}

fn base_image() -> RgbaImage {
    let path = assets_dir().join("paint.jpg");
    image::open(&path)
        .unwrap_or_else(|_| panic!("failed to decode {path:?}"))
        .into_rgba8()
}

fn temp_path(name: &str) -> PathBuf {
    std::env::temp_dir().join(name)
}

fn cstr(value: &str) -> CString {
    CString::new(value).expect("path contains an interior NUL")
}

/// A treatment rectangle (crop region + full-image blur + tint).
fn treatment(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    blur: u8,
    fill_argb: u32,
) -> RectanglePayload {
    RectanglePayload {
        x,
        y,
        width,
        height,
        rotation_deg: 0,
        fill_color_argb: fill_argb,
        outline_color_argb: 0,
        outline_thickness: 0,
        blur,
        corner_radius: 0,
    }
}

/// A synthetic alpha foreground: a centred opaque red disc on a transparent canvas, matching the
/// background's pixel dimensions (the 1:1 contract).
fn make_foreground(width: u32, height: u32) -> RgbaImage {
    let mut img = RgbaImage::from_pixel(width, height, image::Rgba([0, 0, 0, 0]));
    let (cx, cy) = (width as f32 / 2.0, height as f32 / 2.0);
    let radius = (width.min(height) as f32) * 0.25;
    for (x, y, px) in img.enumerate_pixels_mut() {
        let (dx, dy) = (x as f32 - cx, y as f32 - cy);
        if dx * dx + dy * dy <= radius * radius {
            *px = image::Rgba([255, 0, 0, 255]);
        }
    }
    img
}

/// Thin wrapper over the raw `compose` FFI call. Keeps the `CString`s alive across the call.
fn call_compose(
    image_path: &str,
    output_path: &str,
    treatment: Option<&RectanglePayload>,
    foreground_path: Option<&str>,
    elements: &[FfiElement],
    quality: u8,
) -> u8 {
    let img_c = cstr(image_path);
    let out_c = cstr(output_path);
    let fg_c = foreground_path.map(cstr);

    let treatment_ptr = treatment.map_or(std::ptr::null(), |t| t as *const RectanglePayload);
    let fg_ptr = fg_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
    let (elem_ptr, elem_count) = if elements.is_empty() {
        (std::ptr::null(), 0)
    } else {
        (elements.as_ptr(), elements.len())
    };

    // SAFETY: all pointers are valid for the duration of the call; the CStrings outlive it.
    unsafe {
        frigate::compose(
            img_c.as_ptr(),
            out_c.as_ptr(),
            std::ptr::null(),
            treatment_ptr,
            fg_ptr,
            elem_ptr,
            elem_count,
            quality,
            std::ptr::null_mut(),
        )
    }
}

/// Save if the golden does not exist (first run), otherwise compare within a ±2 rounding tolerance.
fn assert_golden(actual: &RgbaImage, path: &Path) {
    if !path.exists() {
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
        let d0 = (px.0[0] as i16 - ex.0[0] as i16).abs();
        let d1 = (px.0[1] as i16 - ex.0[1] as i16).abs();
        let d2 = (px.0[2] as i16 - ex.0[2] as i16).abs();
        let d3 = (px.0[3] as i16 - ex.0[3] as i16).abs();
        if d0 > 2 || d1 > 2 || d2 > 2 || d3 > 2 {
            panic!(
                "pixel mismatch at ({x}, {y}) in {path:?}: got {:?}, expected {:?}",
                px.0, ex.0
            );
        }
    }
}

// ── Golden pipeline cases ──────────────────────────────────────────────────────

#[test]
#[cfg(not(miri))]
fn golden_compose_blur_only() {
    let base = base_image();
    let (w, h) = (base.width(), base.height());
    let out = temp_path("frigate_compose_blur_only.png");
    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        Some(&treatment(0.0, 0.0, w as f64, h as f64, 24, 0)),
        None,
        &[],
        100,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);

    let result = image::open(&out).unwrap().into_rgba8();
    assert_golden(&result, &golden_path("compose_blur_only.png"));
    std::fs::remove_file(&out).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_compose_tint_only() {
    let base = base_image();
    let (w, h) = (base.width(), base.height());
    let out = temp_path("frigate_compose_tint_only.png");
    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        // 50% black tint, no blur.
        Some(&treatment(0.0, 0.0, w as f64, h as f64, 0, 0x80_00_00_00)),
        None,
        &[],
        100,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);

    let result = image::open(&out).unwrap().into_rgba8();
    assert_golden(&result, &golden_path("compose_tint_only.png"));
    std::fs::remove_file(&out).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_compose_shapes_then_foreground() {
    let base = base_image();
    let (w, h) = (base.width(), base.height());
    let fg_path = temp_path("frigate_compose_fg_a.png");
    make_foreground(w, h).save(&fg_path).unwrap();
    let out = temp_path("frigate_compose_shapes_then_fg.png");

    // An opaque rectangle the foreground disc must paint over (subject is composited after shapes).
    let rect = FfiElement::Rectangle(RectanglePayload {
        x: 0.10 * w as f64,
        y: 0.10 * h as f64,
        width: 0.80 * w as f64,
        height: 0.80 * h as f64,
        rotation_deg: 0,
        fill_color_argb: 0xFF_00_80_00, // opaque green
        outline_color_argb: 0,
        outline_thickness: 0,
        blur: 0,
        corner_radius: 0,
    });

    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        None,
        Some(fg_path.to_str().unwrap()),
        &[rect],
        100,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);

    let result = image::open(&out).unwrap().into_rgba8();
    // The centre pixel is inside the disc → red foreground, proving subject-over-shape ordering.
    assert_eq!(result.get_pixel(w / 2, h / 2).0, [255, 0, 0, 255]);
    assert_golden(&result, &golden_path("compose_shapes_then_foreground.png"));
    std::fs::remove_file(&out).ok();
    std::fs::remove_file(&fg_path).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_compose_crop() {
    let out = temp_path("frigate_compose_crop.png");
    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        Some(&treatment(40.0, 30.0, 200.0, 150.0, 0, 0)),
        None,
        &[],
        100,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);

    let result = image::open(&out).unwrap().into_rgba8();
    assert_eq!(
        result.dimensions(),
        (200, 150),
        "output is cropped to the treatment rect"
    );
    assert_golden(&result, &golden_path("compose_crop.png"));
    std::fs::remove_file(&out).ok();
}

#[test]
#[cfg(not(miri))]
fn golden_compose_full_pipeline() {
    let base = base_image();
    let (w, h) = (base.width(), base.height());
    let fg_path = temp_path("frigate_compose_fg_b.png");
    make_foreground(w, h).save(&fg_path).unwrap();
    let out = temp_path("frigate_compose_full.png");

    // A blurred translucent rectangle (per-shape blur) sampled over the treated background.
    let rect = FfiElement::Rectangle(RectanglePayload {
        x: 0.15 * w as f64,
        y: 0.15 * h as f64,
        width: 0.40 * w as f64,
        height: 0.40 * h as f64,
        rotation_deg: 0,
        fill_color_argb: 0x40_FF_FF_FF,
        outline_color_argb: 0,
        outline_thickness: 0,
        blur: 12,
        corner_radius: 0,
    });

    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        // blur + tint + crop to the centre region.
        Some(&treatment(
            0.10 * w as f64,
            0.10 * h as f64,
            0.80 * w as f64,
            0.80 * h as f64,
            18,
            0x30_00_00_00,
        )),
        Some(fg_path.to_str().unwrap()),
        &[rect],
        100,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);

    let result = image::open(&out).unwrap().into_rgba8();
    // Cropped to ~80% of each axis (exact pixel count depends on crop ceil/floor rounding).
    assert!(
        result.width() < w && result.height() < h,
        "output is cropped smaller than the base"
    );
    assert_golden(&result, &golden_path("compose_full_pipeline.png"));
    std::fs::remove_file(&out).ok();
    std::fs::remove_file(&fg_path).ok();
}

// ── Behavioral / error-path coverage ──────────────────────────────────────────

#[test]
#[cfg(not(miri))]
fn compose_passthrough_writes_output_at_input_dimensions() {
    let base = base_image();
    let out = temp_path("frigate_compose_passthrough.png");
    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        None,
        None,
        &[],
        100,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);

    let result = image::open(&out).unwrap().into_rgba8();
    assert_eq!(result.dimensions(), base.dimensions());
    std::fs::remove_file(&out).ok();
}

#[test]
#[cfg(not(miri))]
fn compose_writes_jpeg_output() {
    let out = temp_path("frigate_compose_out.jpg");
    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        Some(&treatment(0.0, 0.0, 100.0, 100.0, 8, 0)),
        None,
        &[],
        80,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);
    assert!(image::open(&out).is_ok(), "JPEG output decodes");
    std::fs::remove_file(&out).ok();
}

#[test]
fn compose_missing_image_path_returns_invalid_arg() {
    let out = cstr(temp_path("frigate_compose_noop.png").to_str().unwrap());
    // SAFETY: null image path is the case under test; all other pointers are valid/null.
    let status = unsafe {
        frigate::compose(
            std::ptr::null(),
            out.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            100,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn compose_nonexistent_file_returns_io_error() {
    let out = temp_path("frigate_compose_io.png");
    let status = call_compose(
        "/definitely/not/there.jpg",
        out.to_str().unwrap(),
        None,
        None,
        &[],
        100,
    );
    assert_eq!(status, FfiErrorCode::Io as u8);
}

#[test]
fn compose_bad_foreground_returns_decode_error() {
    let out = temp_path("frigate_compose_bad_foreground.png");
    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        None,
        Some("/definitely/not/an_image.png"),
        &[],
        100,
    );
    assert_eq!(status, FfiErrorCode::Decode as u8);
    std::fs::remove_file(&out).ok();
}

#[test]
fn compose_degenerate_crop_returns_invalid_arg() {
    let out = temp_path("frigate_compose_bad_crop.png");
    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        // Zero-width crop rect → degenerate.
        Some(&treatment(0.0, 0.0, 0.0, 100.0, 0, 0)),
        None,
        &[],
        100,
    );
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    std::fs::remove_file(&out).ok();
}

// ── Coverage: font/text path, per-shape blur clone, and the defensive FFI guards ──

#[test]
#[cfg(not(miri))]
fn compose_renders_text_via_font_and_arena() {
    let img = cstr(assets_dir().join("paint.jpg").to_str().unwrap());
    let out = temp_path("frigate_compose_text.png");
    let out_c = cstr(out.to_str().unwrap());
    let font = cstr(
        assets_dir()
            .join("RobotoMono-VariableFont_wght.ttf")
            .to_str()
            .unwrap(),
    );

    let text = "Compose";
    let elements = [FfiElement::Text(TextPayload::new(
        10.0,
        10.0,
        24.0,
        0xFF_FF_00_00,
        0,
        0,
        text.len() as u32,
    ))];
    let mut arena = FfiArena {
        text_buf: text.as_ptr(),
        text_len: text.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    // SAFETY: every pointer is valid for the duration of the call; the buffers outlive it.
    let status = unsafe {
        frigate::compose(
            img.as_ptr(),
            out_c.as_ptr(),
            font.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            elements.as_ptr(),
            elements.len(),
            100,
            &raw mut arena,
        )
    };
    assert_eq!(status, FfiErrorCode::Success as u8);
    assert!(image::open(&out).is_ok(), "text composite decodes");
    std::fs::remove_file(&out).ok();
}

#[test]
#[cfg(not(miri))]
fn compose_clones_clean_image_for_oval_and_polygon_blur() {
    let out = temp_path("frigate_compose_oval_poly.png");
    let verts: [f64; 6] = [20.0, 20.0, 120.0, 20.0, 70.0, 120.0];
    // The sharp oval comes first so `needs_clean_img`'s `.any(..)` does not short-circuit before it
    // evaluates the (blurred) polygon arm — both per-shape-blur arms must execute.
    let elements = [
        FfiElement::Oval(OvalPayload {
            x: 10.0,
            y: 10.0,
            width: 80.0,
            height: 60.0,
            rotation_deg: 0,
            fill_color_argb: 0x80_00_00_FF,
            outline_color_argb: 0,
            outline_thickness: 0,
            blur: 0,
            _pad: [0; 2],
        }),
        FfiElement::Polygon(PolygonPayload::new(
            20.0,
            20.0,
            100.0,
            100.0,
            verts.as_ptr(),
            (verts.len() / 2) as u32,
            0x80_00_FF_00,
            0,
            0,
            6,
            0,
        )),
    ];

    let status = call_compose(
        assets_dir().join("paint.jpg").to_str().unwrap(),
        out.to_str().unwrap(),
        None,
        None,
        &elements,
        100,
    );
    assert_eq!(status, FfiErrorCode::Success as u8);
    std::fs::remove_file(&out).ok();
}

#[test]
#[cfg(not(miri))]
fn compose_null_output_overwrites_input() {
    let src = temp_path("frigate_compose_overwrite_src.png");
    base_image()
        .save(&src)
        .expect("failed to seed the overwrite source image");
    let img = cstr(src.to_str().unwrap());

    // SAFETY: a null output path is the case under test — compose overwrites the input path.
    let status = unsafe {
        frigate::compose(
            img.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            &treatment(0.0, 0.0, 50.0, 40.0, 4, 0),
            std::ptr::null(),
            std::ptr::null(),
            0,
            100,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Success as u8);
    let result = image::open(&src).unwrap();
    assert_eq!(
        (result.width(), result.height()),
        (50, 40),
        "input file is overwritten with the cropped output"
    );
    std::fs::remove_file(&src).ok();
}

#[test]
fn compose_null_elements_pointer_with_count_returns_invalid_arg() {
    let img = cstr(assets_dir().join("paint.jpg").to_str().unwrap());
    let out = cstr(
        temp_path("frigate_compose_null_elements.png")
            .to_str()
            .unwrap(),
    );

    // SAFETY: `elements_count > 0` with a null `elements_ptr` is the case under test.
    let status = unsafe {
        frigate::compose(
            img.as_ptr(),
            out.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            1,
            100,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn compose_null_text_buffer_with_text_len_returns_invalid_arg() {
    let img = cstr(assets_dir().join("paint.jpg").to_str().unwrap());
    let out = cstr(temp_path("frigate_compose_null_text.png").to_str().unwrap());
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 5,
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    // SAFETY: `text_len > 0` with a null `text_buf` is the case under test.
    let status = unsafe {
        frigate::compose(
            img.as_ptr(),
            out.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            100,
            &raw mut arena,
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);
}

/// "f" + an invalid UTF-8 byte + NUL: a valid C string whose bytes are not valid UTF-8.
const BAD_UTF8: [u8; 3] = [0x66, 0xFF, 0x00];

#[test]
#[cfg(not(miri))]
fn compose_non_image_background_returns_decode_error() {
    let bad = temp_path("frigate_compose_not_an_image.jpg");
    std::fs::write(&bad, b"this is plainly not an image").unwrap();
    let out = temp_path("frigate_compose_decode_out.png");
    let status = call_compose(
        bad.to_str().unwrap(),
        out.to_str().unwrap(),
        None,
        None,
        &[],
        100,
    );

    assert_eq!(status, FfiErrorCode::Decode as u8);
    std::fs::remove_file(&bad).ok();
}

#[test]
#[cfg(not(miri))]
fn compose_truncated_jpeg_background_returns_truncated() {
    // A real JPEG with its trailing EOI marker (0xFF 0xD9) chopped off: starts with the SOI marker
    // but is incomplete, so `read_image` reports it as truncated rather than a generic decode error.
    let full = std::fs::read(assets_dir().join("paint.jpg")).unwrap();
    let truncated = &full[..full.len() - 2];
    let bad = temp_path("frigate_compose_truncated.jpg");
    std::fs::write(&bad, truncated).unwrap();
    let out = temp_path("frigate_compose_truncated_out.png");
    let status = call_compose(
        bad.to_str().unwrap(),
        out.to_str().unwrap(),
        None,
        None,
        &[],
        100,
    );

    assert_eq!(status, FfiErrorCode::Truncated as u8);
    std::fs::remove_file(&bad).ok();
}

#[test]
fn compose_invalid_utf8_image_path_returns_utf8_error() {
    let out = cstr(temp_path("frigate_compose_utf8_img.png").to_str().unwrap());
    // SAFETY: a NUL-terminated C string with non-UTF-8 content in the image path.
    let status = unsafe {
        frigate::compose(
            BAD_UTF8.as_ptr().cast(),
            out.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            100,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Utf8 as u8);
}

#[test]
fn compose_invalid_utf8_output_path_returns_utf8_error() {
    let img = cstr(assets_dir().join("paint.jpg").to_str().unwrap());
    // SAFETY: a NUL-terminated C string with non-UTF-8 content in the output path.
    let status = unsafe {
        frigate::compose(
            img.as_ptr(),
            BAD_UTF8.as_ptr().cast(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            100,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Utf8 as u8);
}

#[test]
fn compose_invalid_utf8_font_path_returns_utf8_error() {
    let img = cstr(assets_dir().join("paint.jpg").to_str().unwrap());
    let out = cstr(temp_path("frigate_compose_utf8_font.png").to_str().unwrap());
    // SAFETY: a NUL-terminated C string with non-UTF-8 content in the font path.
    let status = unsafe {
        frigate::compose(
            img.as_ptr(),
            out.as_ptr(),
            BAD_UTF8.as_ptr().cast(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            100,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Utf8 as u8);
}

#[test]
fn compose_invalid_utf8_foreground_path_returns_utf8_error() {
    let img = cstr(assets_dir().join("paint.jpg").to_str().unwrap());
    let out = cstr(temp_path("frigate_compose_utf8_fg.png").to_str().unwrap());
    // SAFETY: a NUL-terminated C string with non-UTF-8 content in the foreground path.
    let status = unsafe {
        frigate::compose(
            img.as_ptr(),
            out.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            BAD_UTF8.as_ptr().cast(),
            std::ptr::null(),
            0,
            100,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Utf8 as u8);
}
