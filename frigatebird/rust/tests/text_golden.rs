//! Golden image tests for text rendering + smoke / disaster-path tests for the unified
//! `render_image` FFI.
//!
//! Goldens compare the *RGBA buffer* (lossless, deterministic). JPEG is non-deterministic across
//! `image` crate minor versions, so encoding is exercised by the FFI smoke test only — never
//! pixel-matched.
//!
//! Variable-font caveat: `ab_glyph` uses the default axis instance (wght=400) for the bundled
//! `RobotoMono-VariableFont_wght.ttf`. A future `ab_glyph` update may shift rasterization — when
//! that happens the goldens fail loudly and we regenerate intentionally.
//!
//! First-run workflow:
//!   1. `cargo test --test text_golden` — panics for each missing golden with the new file path.
//!   2. Inspect the generated PNGs in `tests/golden/`, then commit.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use ab_glyph::FontRef;
use image::{Rgba, RgbaImage};

use frigate::{FfiElement, element_type};

const TEST_FONT_BYTES: &[u8] = include_bytes!("../../test/assets/RobotoMono-VariableFont_wght.ttf");

/// Build a temp-file path that's unique per process **and** per call within a process. Stops
/// concurrent `cargo test` runs (CI + local dev, or two CI matrix entries on the same node)
/// from racing on the same on-disk filename, and prevents in-binary parallel tests from
/// stomping on each other if two ever picked the same logical name.
fn unique_tmp(name: &str) -> PathBuf {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!("frigate_{}_{n}_{name}", std::process::id()))
}

fn assets_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("test")
        .join("assets")
}

fn golden_path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("golden")
        .join(name)
}

/// See `rect_golden::base_image` for the rationale — same caching pattern.
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
    use std::ffi::CString;

    let out = unique_tmp("smoke.jpg");

    let img_path = CString::new(assets_dir().join("paint.jpg").to_str().unwrap()).unwrap();
    let font_path = CString::new(
        assets_dir()
            .join("RobotoMono-VariableFont_wght.ttf")
            .to_str()
            .unwrap(),
    )
    .unwrap();
    let out_path = CString::new(out.to_str().unwrap()).unwrap();
    let text_buffer = b"Frigate";

    let element = make_text_element(0, text_buffer.len() as u32);
    let elements = [element];

    let code = unsafe {
        frigate::render_image(
            img_path.as_ptr(),
            out_path.as_ptr(),
            font_path.as_ptr(),
            elements.as_ptr(),
            elements.len(),
            text_buffer.as_ptr(),
            text_buffer.len(),
            90,
        )
    };
    assert_eq!(code, 0, "render_image returned non-zero code");
    assert!(out.exists(), "expected output file {out:?} to exist");

    let decoded = image::open(&out).expect("output should decode as a valid image");
    assert!(decoded.width() > 0 && decoded.height() > 0);

    std::fs::remove_file(&out).ok();
}

#[test]
fn render_image_rejects_text_without_font() {
    use std::ffi::CString;

    let out = unique_tmp("no_font.jpg");
    let img_path = CString::new(assets_dir().join("paint.jpg").to_str().unwrap()).unwrap();
    let out_path = CString::new(out.to_str().unwrap()).unwrap();

    let text_buffer = b"hi";
    let element = make_text_element(0, text_buffer.len() as u32);
    let elements = [element];

    let code = unsafe {
        frigate::render_image(
            img_path.as_ptr(),
            out_path.as_ptr(),
            std::ptr::null(),
            elements.as_ptr(),
            elements.len(),
            text_buffer.as_ptr(),
            text_buffer.len(),
            90,
        )
    };
    assert_eq!(code, 8, "expected MissingFont error code");
}

#[test]
fn render_image_rejects_null_paths() {
    let code = unsafe {
        frigate::render_image(
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::NonNull::<FfiElement>::dangling().as_ptr(),
            0,
            std::ptr::null(),
            0,
            80,
        )
    };
    assert_eq!(code, 7);
}

#[test]
fn render_image_rejects_nonexistent_source_image() {
    use std::ffi::CString;

    let bad_img = CString::new("/definitely/not/here.jpg").unwrap();
    let out = unique_tmp("bad_source.jpg");
    let out_path = CString::new(out.to_str().unwrap()).unwrap();

    let code = unsafe {
        frigate::render_image(
            bad_img.as_ptr(),
            out_path.as_ptr(),
            std::ptr::null(),
            std::ptr::NonNull::<FfiElement>::dangling().as_ptr(),
            0,
            std::ptr::null(),
            0,
            80,
        )
    };
    assert_eq!(code, 1, "expected ImageDecode error code");
}

#[test]
fn render_image_rejects_unsupported_output_extension() {
    use std::ffi::CString;

    let img_path = CString::new(assets_dir().join("paint.jpg").to_str().unwrap()).unwrap();
    let out = unique_tmp("bad_ext.tiff");
    let out_path = CString::new(out.to_str().unwrap()).unwrap();

    let code = unsafe {
        frigate::render_image(
            img_path.as_ptr(),
            out_path.as_ptr(),
            std::ptr::null(),
            std::ptr::NonNull::<FfiElement>::dangling().as_ptr(),
            0,
            std::ptr::null(),
            0,
            80,
        )
    };
    assert_eq!(code, 6, "expected ImageWrite error code");
}

#[test]
fn render_image_mixed_rect_text_rect_does_not_panic_and_decodes() {
    // Exercises the Surface state machine across element-type transitions
    // (Rgba -> Pixmap -> Rgba -> Pixmap -> Rgba). One rect carries a non-zero corner radius
    // so the rounded-path branch in `draw_rect_on_pixmap` is reached through the FFI in
    // addition to the rect_golden suite's direct unit coverage. If any conversion drops or
    // duplicates a draw, this fails to encode a JPEG.
    use std::ffi::CString;

    let out = unique_tmp("mixed.jpg");

    let img_path = CString::new(assets_dir().join("paint.jpg").to_str().unwrap()).unwrap();
    let font_path = CString::new(
        assets_dir()
            .join("RobotoMono-VariableFont_wght.ttf")
            .to_str()
            .unwrap(),
    )
    .unwrap();
    let out_path = CString::new(out.to_str().unwrap()).unwrap();

    let text_buffer = b"Frigate";
    let elements = [
        // Rounded rect — exercises the rounded-path branch through the FFI.
        make_rect_element(20.0, 20.0, 100.0, 80.0, 4, 0xFF_FF_00_00, 12),
        make_text_element(0, text_buffer.len() as u32),
        make_rect_element(60.0, 60.0, 120.0, 90.0, 3, 0xFF_00_00_FF, 0),
    ];

    let code = unsafe {
        frigate::render_image(
            img_path.as_ptr(),
            out_path.as_ptr(),
            font_path.as_ptr(),
            elements.as_ptr(),
            elements.len(),
            text_buffer.as_ptr(),
            text_buffer.len(),
            90,
        )
    };
    assert_eq!(code, 0, "mixed rect+text+rect run must succeed");
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
    outline_thickness: u32,
    outline_color_argb: u32,
    corner_radius_px: u32,
) -> FfiElement {
    FfiElement {
        element_type: element_type::RECTANGLE,
        x,
        y,
        width,
        height,
        rotation_deg: 0,
        fill_color_argb: 0,
        outline_color_argb,
        outline_thickness,
        blur: 0,
        text_offset: 0,
        text_length: 0,
        shape_param: corner_radius_px,
    }
}

fn make_text_element(text_offset: u32, text_length: u32) -> FfiElement {
    FfiElement {
        element_type: element_type::TEXT,
        x: 50.0,
        y: 250.0,
        width: 0.0,
        // `height` doubles as font em-box size for text elements.
        height: 40.0,
        rotation_deg: 0,
        fill_color_argb: 0xFFFF0000,
        outline_color_argb: 0,
        outline_thickness: 0,
        blur: 0,
        shape_param: 0,
        text_offset,
        text_length,
    }
}
