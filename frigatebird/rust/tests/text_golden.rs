//! Golden image tests for text rendering + smoke / disaster-path tests for the unified
//! `render_image` FFI.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use ab_glyph::FontRef;
use image::{Rgba, RgbaImage};

use frigate::{FfiArena, FfiElement, RectanglePayload, TextPayload};

const TEST_FONT_BYTES: &[u8] = include_bytes!("../tests/assets/RobotoMono-VariableFont_wght.ttf");

/// Build a temp-file path that's unique per process **and** per call within a process.
fn unique_tmp(name: &str) -> PathBuf {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!("frigate_{}_{n}_{name}", std::process::id()))
}

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
    static CACHE: std::sync::OnceLock<RgbaImage> = std::sync::OnceLock::new();
    CACHE
        .get_or_init(|| {
            let path = assets_dir().join("paint.jpg");
            image::open(&path)
                .unwrap_or_else(|_| panic!("failed to decode {path:?}"))
                .into_rgba8()
        })
        .clone()
}

fn render_case(
    text: &str,
    x: f32,
    y: f32,
    font_px: f32,
    rot_rad: f32,
    color: Rgba<u8>,
) -> RgbaImage {
    let font = FontRef::try_from_slice(TEST_FONT_BYTES).unwrap();
    let mut img = base_image();
    let params = frigate::text::TextParams {
        text,
        x,
        y,
        font_size_px: font_px,
        rotation_rad: rot_rad,
        color,
    };
    frigate::text::render_text_overlay(&mut img, &font, &params);
    img
}

fn assert_golden(actual: &RgbaImage, path: &Path) {
    if !path.exists() {
        actual
            .save(path)
            .unwrap_or_else(|e| panic!("failed to write new golden to {path:?}: {e}"));
        panic!(
            "Golden did not exist; wrote new golden to {path:?}. Inspect visually, commit it, then re-run."
        );
    }
    let expected = image::open(path)
        .unwrap_or_else(|_| panic!("failed to decode golden {path:?}"))
        .into_rgba8();
    assert_eq!(
        actual.dimensions(),
        expected.dimensions(),
        "golden dimension mismatch at {path:?}"
    );
    for (x, y, px) in actual.enumerate_pixels() {
        let ex = expected.get_pixel(x, y);
        if px != ex {
            panic!(
                "pixel mismatch at ({x}, {y}) in {path:?}: got {:?}, expected {:?}",
                px.0, ex.0
            );
        }
    }
}

#[test]
fn golden_basic_text() {
    let base = base_image();
    let img = render_case(
        "Frigate",
        0.10 * base.width() as f32,
        0.50 * base.height() as f32,
        0.08 * base.height() as f32,
        0.0,
        Rgba([255, 0, 0, 255]),
    );
    assert_golden(&img, &golden_path("text_basic.png"));
}

#[test]
fn golden_rotated_text() {
    let base = base_image();
    let img = render_case(
        "Frigate",
        0.10 * base.width() as f32,
        0.50 * base.height() as f32,
        0.08 * base.height() as f32,
        30.0_f32.to_radians(),
        Rgba([0, 255, 0, 255]),
    );
    assert_golden(&img, &golden_path("text_rotated.png"));
}

#[test]
fn golden_translucent_text() {
    let base = base_image();
    let img = render_case(
        "Frigate",
        0.10 * base.width() as f32,
        0.50 * base.height() as f32,
        0.08 * base.height() as f32,
        0.0,
        Rgba([0, 0, 255, 128]),
    );
    assert_golden(&img, &golden_path("text_translucent.png"));
}

#[test]
fn render_image_end_to_end_writes_jpeg() {
    use safer_ffi::char_p;

    let out = unique_tmp("smoke.jpg");

    let img_path_cs = char_p::new(assets_dir().join("paint.jpg").to_str().unwrap());
    let font_path_cs = char_p::new(
        assets_dir()
            .join("RobotoMono-VariableFont_wght.ttf")
            .to_str()
            .unwrap(),
    );
    let out_path_cs = char_p::new(out.to_str().unwrap());
    let text_buffer = b"Frigate";

    let element = make_text_element(0, text_buffer.len() as u32);
    let elements = [element];

    let mut error_buf = [0u8; 256];
    let mut arena = FfiArena {
        text_buf: text_buffer.as_ptr(),
        text_len: text_buffer.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };
    let mut out_res = frigate::FfiResultUnit::Ok(());

    #[expect(unsafe_code, reason = "FFI call")]
    unsafe {
        frigate::draw_elements(
            Some(img_path_cs.as_ref()),
            Some(out_path_cs.as_ref()),
            Some(font_path_cs.as_ref()),
            elements.as_ptr(),
            elements.len(),
            90,
            &raw mut arena,
            &raw mut out_res,
        );
    };
    assert!(
        matches!(out_res, frigate::FfiResultUnit::Ok(())),
        "draw_elements returned error"
    );
    assert!(out.exists(), "expected output file {out:?} to exist");

    let decoded = image::open(&out).expect("output should decode as a valid image");
    assert!(decoded.width() > 0 && decoded.height() > 0);

    std::fs::remove_file(&out).ok();
}

#[test]
fn render_image_rejects_text_without_font() {
    use safer_ffi::char_p;

    let out = unique_tmp("no_font.jpg");
    let img_path_cs = char_p::new(assets_dir().join("paint.jpg").to_str().unwrap());
    let out_path_cs = char_p::new(out.to_str().unwrap());

    let text_buffer = b"hi";
    let element = make_text_element(0, text_buffer.len() as u32);
    let elements = [element];

    let mut error_buf = [0u8; 256];
    let mut arena = FfiArena {
        text_buf: text_buffer.as_ptr(),
        text_len: text_buffer.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };
    let mut out_res = frigate::FfiResultUnit::Ok(());

    #[expect(unsafe_code, reason = "FFI call")]
    unsafe {
        frigate::draw_elements(
            Some(img_path_cs.as_ref()),
            Some(out_path_cs.as_ref()),
            None,
            elements.as_ptr(),
            elements.len(),
            90,
            &raw mut arena,
            &raw mut out_res,
        );
    };
    let frigate::FfiResultUnit::Err(e) = out_res else {
        panic!("expected error, got Ok");
    };
    assert_eq!(
        e.code,
        frigate::FfiErrorCode::InvalidArg as u8,
        "expected InvalidArg for missing font"
    );
}

#[test]
fn render_image_rejects_null_image_path() {
    use safer_ffi::char_p;

    let out_path_cs = char_p::new("dummy");
    let font_path_cs = char_p::new("dummy");
    let mut error_buf = vec![0u8; 256];
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };
    let mut out_res = frigate::FfiResultUnit::Ok(());

    #[expect(unsafe_code, reason = "FFI call")]
    unsafe {
        frigate::draw_elements(
            None,
            Some(out_path_cs.as_ref()),
            Some(font_path_cs.as_ref()),
            std::ptr::NonNull::<frigate::FfiElement>::dangling().as_ptr(),
            0,
            100,
            &raw mut arena,
            &raw mut out_res,
        );
    };

    assert!(
        matches!(out_res, frigate::FfiResultUnit::Err(_)),
        "expected error for null path"
    );
}

#[test]
fn render_image_rejects_nonexistent_source_image() {
    use safer_ffi::char_p;

    let bad_img_cs = char_p::new("/definitely/not/here.jpg");
    let out = unique_tmp("bad_source.jpg");
    let out_path_cs = char_p::new(out.to_str().unwrap());

    let mut error_buf = [0u8; 256];
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };
    let mut out_res = frigate::FfiResultUnit::Ok(());

    #[expect(unsafe_code, reason = "FFI call")]
    unsafe {
        frigate::draw_elements(
            Some(bad_img_cs.as_ref()),
            Some(out_path_cs.as_ref()),
            None,
            std::ptr::NonNull::<frigate::FfiElement>::dangling().as_ptr(),
            0,
            80,
            &raw mut arena,
            &raw mut out_res,
        );
    };
    let frigate::FfiResultUnit::Err(e) = out_res else {
        panic!("expected error, got Ok");
    };
    assert_eq!(
        e.code,
        frigate::FfiErrorCode::Decode as u8,
        "expected Decode error for missing image"
    );
}

#[test]
fn render_image_rejects_unsupported_output_extension() {
    use safer_ffi::char_p;

    let img_path_cs = char_p::new(assets_dir().join("paint.jpg").to_str().unwrap());
    let out = unique_tmp("bad_ext.tiff");
    let out_path_cs = char_p::new(out.to_str().unwrap());

    let mut error_buf = [0u8; 256];
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };
    let mut out_res = frigate::FfiResultUnit::Ok(());

    #[expect(unsafe_code, reason = "FFI call")]
    unsafe {
        frigate::draw_elements(
            Some(img_path_cs.as_ref()),
            Some(out_path_cs.as_ref()),
            None,
            std::ptr::NonNull::<frigate::FfiElement>::dangling().as_ptr(),
            0,
            80,
            &raw mut arena,
            &raw mut out_res,
        );
    };
    let frigate::FfiResultUnit::Err(e) = out_res else {
        panic!("expected error, got Ok");
    };
    assert_eq!(
        e.code,
        frigate::FfiErrorCode::Encode as u8,
        "expected Encode error for bad extension"
    );
}

#[test]
fn render_image_mixed_rect_text_rect_does_not_panic_and_decodes() {
    use safer_ffi::char_p;

    let out = unique_tmp("mixed.jpg");

    let img_path_cs = char_p::new(assets_dir().join("paint.jpg").to_str().unwrap());
    let font_path_cs = char_p::new(
        assets_dir()
            .join("RobotoMono-VariableFont_wght.ttf")
            .to_str()
            .unwrap(),
    );
    let out_path_cs = char_p::new(out.to_str().unwrap());

    let text_buffer = b"Frigate";
    let elements = [
        make_rect_element(20.0, 20.0, 100.0, 80.0, 4, 0xFF_FF_00_00, 12),
        make_text_element(0, text_buffer.len() as u32),
        make_rect_element(60.0, 60.0, 120.0, 90.0, 3, 0xFF_00_00_FF, 0),
    ];

    let mut error_buf = [0u8; 256];
    let mut arena = FfiArena {
        text_buf: text_buffer.as_ptr(),
        text_len: text_buffer.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };
    let mut out_res = frigate::FfiResultUnit::Ok(());

    #[expect(unsafe_code, reason = "FFI call")]
    unsafe {
        frigate::draw_elements(
            Some(img_path_cs.as_ref()),
            Some(out_path_cs.as_ref()),
            Some(font_path_cs.as_ref()),
            elements.as_ptr(),
            elements.len(),
            90,
            &raw mut arena,
            &raw mut out_res,
        );
    };
    assert!(
        matches!(out_res, frigate::FfiResultUnit::Ok(())),
        "mixed rect+text+rect run must succeed"
    );
    assert!(out.exists());
    let decoded = image::open(&out).expect("output should decode");
    assert!(decoded.width() > 0 && decoded.height() > 0);

    std::fs::remove_file(&out).ok();
}

fn make_rect_element(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u8,
    outline_color_argb: u32,
    corner_radius: u16,
) -> FfiElement {
    FfiElement::Rectangle(RectanglePayload {
        x,
        y,
        width,
        height,
        rotation_deg: 0,
        fill_color_argb: 0,
        outline_color_argb,
        outline_thickness,
        blur: 0,
        corner_radius,
    })
}

fn make_text_element(text_offset: u32, text_length: u32) -> FfiElement {
    FfiElement::Text(TextPayload {
        x: 50.0,
        y: 250.0,
        height: 40.0,
        rotation_deg: 0,
        fill_color_argb: 0xFFFF0000,
        blur: 0,
        _pad: [0; 3],
        font_id: 0,
        text_offset,
        text_len: text_length,
    })
}
