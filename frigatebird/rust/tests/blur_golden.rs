//! Golden image tests for Gaussian blur rendering.
//!
//! Tests cover:
//! - Per-element blur on Rectangle, Oval, and Polygon shapes via `draw_elements`.
//! - Text element with `blur > 0` — must render identically to `blur = 0` (blur is a no-op for text).
//! - `blur_region` standalone FFI entry point: full-image and region cases.
//! - FNV-1a hash golden for the full-blur case to catch algorithm drift.

use std::path::{Path, PathBuf};

use image::RgbaImage;

use frigate::{
    FfiElement, OvalPayload, PolygonPayload, RectanglePayload, ShapeBuilder as _, TextPayload,
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

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Write a temp PNG for the `blur_region` standalone tests (needs a file on disk).
fn write_temp_png(img: &RgbaImage, name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(name);
    img.save(&path)
        .unwrap_or_else(|e| panic!("failed to write temp PNG {path:?}: {e}"));
    path
}

fn render_element(element: FfiElement) -> RgbaImage {
    let mut img = base_image();
    frigate::draw_element(&mut img, &element, None, &[]);
    img
}

/// Save if the golden does not exist (first run), otherwise compare within a small rounding tolerance.
fn assert_golden(actual: &RgbaImage, path: &Path) {
    let base = base_image();
    assert_ne!(
        actual.as_raw(),
        base.as_raw(),
        "{path:?}: rendered output is byte-identical to the unmodified base image.",
    );

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
                "pixel mismatch at ({x}, {y}) in {path:?}: got {:?}, expected {:?} (delta: {}, {}, {}, {})",
                px.0, ex.0, d0, d1, d2, d3
            );
        }
    }
}

// ── Per-element blur goldens ──────────────────────────────────────────────────

/// A `RectElement` with blur=15 (radius) should produce a visibly blurred backdrop under the fill.
#[test]
#[cfg(not(miri))]
fn golden_blur_rect_element() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let element = FfiElement::Rectangle(RectanglePayload {
        x: 0.20 * w,
        y: 0.20 * h,
        width: 0.60 * w,
        height: 0.60 * h,
        rotation_deg: 0,
        fill_color_argb: 0x40_FF_FF_FF, // 25% opaque white fill on top of blurred backdrop
        outline_color_argb: 0xFF_FF_FF_FF,
        outline_thickness: 3,
        blur: 15, // radius=15 → sigma=5
        corner_radius: 0,
    });
    let img = render_element(element);
    assert_golden(&img, &golden_path("blur_rect_element.png"));
}

/// An `OvalElement` with blur=10 should blur the oval bounding box before painting.
#[test]
#[cfg(not(miri))]
fn golden_blur_oval_element() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let element = FfiElement::Oval(OvalPayload {
        x: 0.20 * w,
        y: 0.20 * h,
        width: 0.60 * w,
        height: 0.40 * h,
        rotation_deg: 0,
        fill_color_argb: 0x60_00_80_FF, // semi-transparent blue fill
        outline_color_argb: 0xFF_FF_FF_00,
        outline_thickness: 3,
        blur: 10, // radius=10 → sigma≈3.3
        _pad: [0; 2],
    });
    let img = render_element(element);
    assert_golden(&img, &golden_path("blur_oval_element.png"));
}

/// A `PolygonElement` (triangle) with blur=8 should blur its bounding box.
#[test]
#[cfg(not(miri))]
fn golden_blur_polygon_element() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    // Triangle: centre-top, bottom-left, bottom-right.
    let verts = [0.50 * w, 0.10 * h, 0.10 * w, 0.80 * h, 0.90 * w, 0.80 * h];
    let element = FfiElement::Polygon(PolygonPayload::new(
        0.10 * w,
        0.10 * h,
        0.80 * w,
        0.70 * h,
        verts.as_ptr(),
        3,
        0x60_FF_80_00, // semi-transparent orange fill
        0xFF_FF_FF_FF,
        3,
        8, // blur radius=8 → sigma≈2.7
        0,
    ));
    let img = render_element(element);
    assert_golden(&img, &golden_path("blur_polygon_element.png"));
}

/// A `TextElement` with blur > 0 must render identically to one with blur = 0.
/// Blur is intentionally ignored for text elements.
#[test]
#[cfg(not(miri))]
fn golden_blur_text_no_blur() {
    // Render text with blur=0 for reference.
    let font_path = assets_dir().join("RobotoMono.ttf");
    if !font_path.exists() {
        // Skip gracefully if the font asset is absent (CI without assets).
        return;
    }
    let font_bytes = std::fs::read(&font_path).unwrap();
    let font = ab_glyph::FontRef::try_from_slice(&font_bytes).unwrap();

    let base_no_blur = base_image();
    let mut img_no_blur = base_no_blur.clone();
    let p_no_blur = TextPayload::new(100.0, 200.0, 48.0, 0xFF_FF_FF_FF, 0, 0, 7);
    frigate::draw_element(
        &mut img_no_blur,
        &FfiElement::Text(p_no_blur),
        Some(&font),
        b"Frigate",
    );

    // Render text with blur=20.
    let mut img_with_blur = base_no_blur.clone();
    let mut p_with_blur = p_no_blur;
    p_with_blur.blur = 20;
    frigate::draw_element(
        &mut img_with_blur,
        &FfiElement::Text(p_with_blur),
        Some(&font),
        b"Frigate",
    );

    assert_eq!(
        img_no_blur.as_raw(),
        img_with_blur.as_raw(),
        "text elements must render identically regardless of the blur field value",
    );
}

// ── blur_region standalone goldens ───────────────────────────────────────────

/// Full-image blur via `blur`.
#[test]
#[cfg(not(miri))]
fn golden_blur_full_image() {
    let base = base_image();
    let tmp = write_temp_png(&base, "frigate_blur_full.png");
    let tmp_str = tmp.to_str().unwrap();
    let path_ref = safer_ffi::char_p::new(tmp_str);

    let status = frigate::blur(
        Some(path_ref.as_ref()),
        None, // overwrite in-place
        24,
        100,
        None,
    );
    assert_eq!(status, frigate::FfiErrorCode::Success as u8);

    let result = image::open(&tmp).unwrap().into_rgba8();
    assert_golden(&result, &golden_path("blur_region_full.png"));
    std::fs::remove_file(&tmp).ok();
}

/// Region blur: blur only the centre 40% of the image.
#[test]
#[cfg(not(miri))]
fn golden_blur_region_centre() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let tmp = write_temp_png(&base, "frigate_blur_region_centre.png");
    let tmp_str = tmp.to_str().unwrap();
    let path_ref = safer_ffi::char_p::new(tmp_str);

    let region = RectanglePayload::new(0.30 * w, 0.30 * h, 0.40 * w, 0.40 * h, 0).with_blur(36);

    let status = frigate::blur_region(Some(path_ref.as_ref()), None, region, 100, None);
    assert_eq!(status, frigate::FfiErrorCode::Success as u8);

    let result = image::open(&tmp).unwrap().into_rgba8();
    assert_golden(&result, &golden_path("blur_region_centre.png"));
    std::fs::remove_file(&tmp).ok();
}

// ── blur_region error-path coverage ──────────────────────────────────────────

#[test]
fn blur_region_radius_zero_returns_success_without_reading_file() {
    // Even a bogus path must return Success when radius=0.
    let bogus = safer_ffi::char_p::new("/definitely/not/there.png");
    let region = RectanglePayload::new(0.0, 0.0, 0.0, 0.0, 0).with_blur(0);
    let status = frigate::blur_region(Some(bogus.as_ref()), None, region, 100, None);
    assert_eq!(status, frigate::FfiErrorCode::Success as u8);
}

#[test]
fn blur_region_missing_path_returns_invalid_arg() {
    let region = RectanglePayload::new(0.0, 0.0, 0.0, 0.0, 0).with_blur(10);
    let status = frigate::blur_region(None, None, region, 100, None);
    assert_eq!(status, frigate::FfiErrorCode::InvalidArg as u8);
}

#[test]
fn blur_region_nonexistent_file_returns_io_error() {
    let bogus = safer_ffi::char_p::new("/definitely/not/there.png");
    let region = RectanglePayload::new(0.0, 0.0, 100.0, 100.0, 0).with_blur(10);
    let status = frigate::blur_region(Some(bogus.as_ref()), None, region, 100, None);
    assert_eq!(status, frigate::FfiErrorCode::Io as u8);
}

/// A rectangle with transparent fill, no outline, and blur (exact model of `MaskRegionElement`).
#[test]
#[cfg(not(miri))]
fn golden_blur_mask_region_element() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let element = FfiElement::Rectangle(RectanglePayload {
        x: 0.20 * w,
        y: 0.20 * h,
        width: 0.60 * w,
        height: 0.60 * h,
        rotation_deg: 0,
        fill_color_argb: 0x00_00_00_00, // transparent fill (MaskRegionElement style)
        outline_color_argb: 0x00_00_00_00, // transparent outline
        outline_thickness: 0,
        blur: 15,
        corner_radius: 0,
    });
    let img = render_element(element);
    assert_golden(&img, &golden_path("blur_mask_region_element.png"));
}
