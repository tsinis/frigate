// Golden image tests for text rendering.

use std::path::{Path, PathBuf};

use ab_glyph::FontRef;
use image::{Rgba, RgbaImage};

use frigate::{FfiArena, FfiErrorCode, TextPayload};

const TEST_FONT_BYTES: &[u8] = include_bytes!("assets/RobotoMono-VariableFont_wght.ttf");

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

fn render_case(
    text: &str,
    x: f32,
    y: f32,
    height: f32,
    rot_rad: f32,
    color: Rgba<u8>,
) -> RgbaImage {
    let font = FontRef::try_from_slice(TEST_FONT_BYTES).unwrap();
    let mut img = base_image();
    let params = frigate::text::TextParams {
        text,
        x,
        y,
        font_size_px: height,
        rotation_rad: rot_rad,
        color,
    };
    frigate::text::render_text_overlay(&mut img, &font, &params);
    img
}

fn assert_golden(actual: &RgbaImage, path: &Path) {
    if !path.exists() {
        actual.save(path).unwrap();
        panic!("Golden did not exist; wrote new golden to {path:?}.");
    }
    let expected = image::open(path).unwrap().into_rgba8();
    assert_eq!(actual.dimensions(), expected.dimensions());
    for (x, y, px) in actual.enumerate_pixels() {
        assert_eq!(px, expected.get_pixel(x, y), "mismatch at ({x}, {y})");
    }
}

#[test]
fn golden_basic_text() {
    let img = render_case(
        "Frigate Bird",
        50.0,
        100.0,
        48.0,
        0.0,
        Rgba([255, 255, 255, 255]),
    );
    assert_golden(&img, &golden_path("text_basic.png"));
}

#[test]
fn golden_rotated_text() {
    let img = render_case(
        "Rotated 45°",
        150.0,
        150.0,
        32.0,
        (45.0f32).to_radians(),
        Rgba([255, 255, 0, 255]),
    );
    assert_golden(&img, &golden_path("text_rotated.png"));
}

#[test]
fn golden_translucent_text() {
    let img = render_case(
        "Translucent",
        20.0,
        200.0,
        64.0,
        0.0,
        Rgba([0, 255, 255, 128]),
    );
    assert_golden(&img, &golden_path("text_translucent.png"));
}

/// Call `draw_elements` and return a numeric error code (0 = success).
///
/// Centralises the FFI call so each test stays concise.
fn call_draw(
    image_path: Option<&safer_ffi::char_p::char_p_boxed>,
    output_path: Option<&safer_ffi::char_p::char_p_boxed>,
    font_path: Option<&safer_ffi::char_p::char_p_boxed>,
    elements: &[frigate::FfiElement],
    arena: &mut FfiArena,
    quality: u8,
) -> u8 {
    #[expect(unsafe_code, reason = "FFI call to draw_elements requires raw pointer")]
    unsafe {
        let img_cs = image_path.map(|p| std::ffi::CString::new(p.to_string()).unwrap());
        let out_cs = output_path.map(|p| std::ffi::CString::new(p.to_string()).unwrap());
        let font_cs = font_path.map(|p| std::ffi::CString::new(p.to_string()).unwrap());

        let img_p = img_cs.as_ref().map_or(std::ptr::null(), |cs| cs.as_ptr());
        let out_p = out_cs.as_ref().map_or(std::ptr::null(), |cs| cs.as_ptr());
        let font_p = font_cs.as_ref().map_or(std::ptr::null(), |cs| cs.as_ptr());

        frigate::draw_elements(
            img_p,
            out_p,
            font_p,
            elements.as_ptr(),
            elements.len(),
            quality,
            arena as *mut FfiArena,
        )
    }
}

#[test]
fn render_image_end_to_end_writes_jpeg() {
    let img_path = assets_dir().join("paint.jpg");
    let out = std::env::temp_dir().join("test_out.jpg");
    let font_path = assets_dir().join("RobotoMono-VariableFont_wght.ttf");

    let img_cs = safer_ffi::char_p::new(img_path.to_str().unwrap());
    let out_cs = safer_ffi::char_p::new(out.to_str().unwrap());
    let font_cs = safer_ffi::char_p::new(font_path.to_str().unwrap());

    let text = "FFI Test";
    let elements = [frigate::FfiElement::Text(TextPayload::new(
        10.0, 10.0, 24.0, 0xFFFF0000, 0, 0, 8,
    ))];
    let mut arena = FfiArena {
        text_buf: text.as_ptr(),
        text_len: text.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    let code = call_draw(
        Some(&img_cs),
        Some(&out_cs),
        Some(&font_cs),
        &elements,
        &mut arena,
        90,
    );
    if code != FfiErrorCode::Success as u8 {
        #[expect(
            unsafe_code,
            reason = "Reading arena error buffer for test diagnostics"
        )]
        let msg = unsafe { std::ffi::CStr::from_ptr(arena.error.as_ptr().cast()) };
        panic!("FFI call failed with code {code}: {:?}", msg);
    }
    assert!(out.exists(), "expected output file {out:?} to exist");

    let decoded = image::open(&out).expect("output should decode as a valid image");
    assert!(
        decoded.width() > 0 && decoded.height() > 0,
        "output must be a non-empty image"
    );
}

#[test]
fn render_image_rejects_text_without_font() {
    let img_path = assets_dir().join("paint.jpg");
    let out = std::env::temp_dir().join("test_out_nofont.jpg");

    let img_cs = safer_ffi::char_p::new(img_path.to_str().unwrap());
    let out_cs = safer_ffi::char_p::new(out.to_str().unwrap());

    let text = "No Font";
    let elements = [frigate::FfiElement::Text(TextPayload::new(
        10.0, 10.0, 24.0, 0xFFFF0000, 0, 0, 7,
    ))];
    let mut arena = FfiArena {
        text_buf: text.as_ptr(),
        text_len: text.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    let code = call_draw(
        Some(&img_cs),
        Some(&out_cs),
        None,
        &elements,
        &mut arena,
        90,
    );
    assert_eq!(code, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn render_image_rejects_null_image_path() {
    let out = std::env::temp_dir().join("test_out_null.jpg");
    let out_cs = safer_ffi::char_p::new(out.to_str().unwrap());

    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    let code = call_draw(None, Some(&out_cs), None, &[], &mut arena, 100);
    assert_eq!(code, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn render_image_rejects_nonexistent_source_image() {
    let out = std::env::temp_dir().join("test_out_missing.jpg");
    let out_cs = safer_ffi::char_p::new(out.to_str().unwrap());
    let bad_img = std::env::temp_dir().join("definitely_not_here_12345.jpg");
    let bad_img_cs = safer_ffi::char_p::new(bad_img.to_str().unwrap());

    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    let code = call_draw(Some(&bad_img_cs), Some(&out_cs), None, &[], &mut arena, 80);
    assert_eq!(code, FfiErrorCode::Decode as u8);
}

#[test]
fn render_image_rejects_unsupported_output_extension() {
    let img_path = assets_dir().join("paint.jpg");
    let out = std::env::temp_dir().join("test_out.tiff");

    let img_cs = safer_ffi::char_p::new(img_path.to_str().unwrap());
    let out_cs = safer_ffi::char_p::new(out.to_str().unwrap());

    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    let code = call_draw(Some(&img_cs), Some(&out_cs), None, &[], &mut arena, 80);
    if code != FfiErrorCode::Encode as u8 {
        #[expect(
            unsafe_code,
            reason = "Reading arena error buffer for test diagnostics"
        )]
        let msg = unsafe { std::ffi::CStr::from_ptr(arena.error.as_ptr().cast()) };
        panic!("FFI call failed with code {code} (wanted 5): {:?}", msg);
    }
    assert!(
        !out.exists(),
        "output file should not be created for unsupported format"
    );
}
#[test]
fn render_image_mixed_rect_text_rect_does_not_panic_and_decodes() {
    let img_path = assets_dir().join("paint.jpg");
    let out = std::env::temp_dir().join("test_out_mixed.jpg");
    let font_path = assets_dir().join("RobotoMono-VariableFont_wght.ttf");

    let img_cs = safer_ffi::char_p::new(img_path.to_str().unwrap());
    let out_cs = safer_ffi::char_p::new(out.to_str().unwrap());
    let font_cs = safer_ffi::char_p::new(font_path.to_str().unwrap());

    let text = "Mixed";
    let elements = [
        frigate::FfiElement::Rectangle(frigate::RectanglePayload::new(
            0.0, 0.0, 100.0, 100.0, 0xFFFF0000,
        )),
        frigate::FfiElement::Text(TextPayload::new(10.0, 10.0, 24.0, 0xFF00FF00, 0, 0, 5)),
        frigate::FfiElement::Rectangle(frigate::RectanglePayload::new(
            50.0, 50.0, 100.0, 100.0, 0xFF0000FF,
        )),
    ];
    let mut arena = FfiArena {
        text_buf: text.as_ptr(),
        text_len: text.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 256].into_boxed_slice().into(),
    };

    let code = call_draw(
        Some(&img_cs),
        Some(&out_cs),
        Some(&font_cs),
        &elements,
        &mut arena,
        90,
    );
    if code != FfiErrorCode::Success as u8 {
        #[expect(
            unsafe_code,
            reason = "Reading arena error buffer for test diagnostics"
        )]
        let msg = unsafe { std::ffi::CStr::from_ptr(arena.error.as_ptr().cast()) };
        panic!("FFI call failed with code {code}: {:?}", msg);
    }
    assert!(out.exists());
    let decoded = image::open(&out).expect("mixed output should decode");
    assert!(
        decoded.width() > 0 && decoded.height() > 0,
        "output must be a non-empty image"
    );
}
