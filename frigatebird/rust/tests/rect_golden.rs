//! Golden image tests for rectangle rendering.

#![allow(unsafe_code)]

use std::path::{Path, PathBuf};

use image::RgbaImage;

use frigate::{FfiElement, RectanglePayload};

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
    // Cache the base image to avoid re-decoding it for every test case.
    // Cloning an RgbaImage is a shallow reference-count bump in some libraries,
    // but in `image` crate it's a full pixel copy — still faster than JPEG decode.
    CACHE
        .get_or_init(|| {
            let path = assets_dir().join("paint.jpg");
            image::open(&path)
                .unwrap_or_else(|_| panic!("failed to decode {path:?}"))
                .into_rgba8()
        })
        .clone()
}

fn make_rect(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u8,
    outline_color_argb: u32,
) -> FfiElement {
    make_rect_with_fill(
        x,
        y,
        width,
        height,
        outline_thickness,
        outline_color_argb,
        0,
    )
}

fn make_rect_with_fill(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u8,
    outline_color_argb: u32,
    fill_color_argb: u32,
) -> FfiElement {
    make_rect_full(
        x,
        y,
        width,
        height,
        outline_thickness,
        outline_color_argb,
        fill_color_argb,
        0,
    )
}

#[allow(clippy::too_many_arguments)]
fn make_rect_full(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u8,
    outline_color_argb: u32,
    fill_color_argb: u32,
    corner_radius: u16,
) -> FfiElement {
    FfiElement::Rectangle(RectanglePayload {
        x,
        y,
        width,
        height,
        rotation_deg: 0,
        fill_color_argb,
        outline_color_argb,
        outline_thickness,
        blur: 0,
        corner_radius,
    })
}

fn render_rects(rects: &[FfiElement]) -> RgbaImage {
    let mut img = base_image();
    for r in rects {
        frigate::draw_rect_element(&mut img, r);
    }
    img
}

fn assert_golden(actual: &RgbaImage, path: &Path) {
    let base = base_image();
    // Guard against tests that accidentally render nothing — the golden would "pass"
    // but the test would be a silent no-op.
    assert_ne!(
        actual.as_raw(),
        base.as_raw(),
        "{path:?}: rendered output is byte-identical to the unmodified base image."
    );

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
fn golden_rect_solid_outline() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rect = make_rect(
        0.20 * w,
        0.20 * h,
        0.60 * w,
        0.60 * h,
        4,
        0xFFFF_0000, // opaque red
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_solid.png"));
}

#[test]
fn golden_rect_clipped_to_image_edges() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rect = make_rect(
        -0.20 * w,
        -0.15 * h,
        0.70 * w,
        0.55 * h,
        6,
        0xFF00_FF00, // opaque green
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_clipped.png"));
}

#[test]
fn golden_rect_thickness_clamped_to_min_side() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rect = make_rect(
        0.10 * w,
        0.10 * h,
        0.20 * w,
        0.20 * h,
        u8::MAX,     // vastly exceeds min_side → clamped
        0xFF00_00FF, // opaque blue
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_thick_clamped.png"));
}

#[test]
fn golden_rect_rounded_small_radius() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rect = make_rect_full(
        0.20 * w,
        0.20 * h,
        0.60 * w,
        0.60 * h,
        4,
        0xFF_FF_FF_FF, // white outline
        0x80_00_00_FF, // 50% blue fill
        24,
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_rounded_small.png"));
}

#[test]
fn golden_rect_rounded_pill_radius_at_clamp() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rect_w = 0.60 * w;
    let rect_h = 0.20 * h;
    // corner radius = half of minimum dimension (pill shape)
    let radius = (rect_w.min(rect_h) / 2.0) as u16;
    let rect = make_rect_full(
        0.20 * w,
        0.40 * h,
        rect_w,
        rect_h,
        4,
        0xFF_FF_00_00, // red outline
        0xFF_FF_FF_00, // opaque yellow fill
        radius,
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_rounded_pill.png"));
}

#[test]
fn golden_rect_rounded_radius_clamped_to_min_side() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rect_w = 0.60 * w;
    let rect_h = 0.20 * h;
    let rect = make_rect_full(
        0.20 * w,
        0.40 * h,
        rect_w,
        rect_h,
        4,
        0xFF_FF_00_00,
        0xFF_FF_FF_00,
        u16::MAX, // exceeds bounds -> will be clamped to min(w, h)/2
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_rounded_clamped.png"));
}

#[test]
fn golden_rect_translucent_fill_with_opaque_outline() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rect = make_rect_with_fill(
        0.20 * w,
        0.20 * h,
        0.60 * w,
        0.60 * h,
        4,
        0xFF_FF_FF_FF, // opaque white outline
        0x80_FF_00_00, // 50% red fill
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_filled.png"));
}

#[test]
fn golden_rect_stacked_overlapping() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let rects = [
        make_rect(0.10 * w, 0.10 * h, 0.50 * w, 0.50 * h, 3, 0xFFFF_0000),
        make_rect(0.30 * w, 0.30 * h, 0.50 * w, 0.50 * h, 3, 0xFF00_FF00),
        make_rect(0.20 * w, 0.40 * h, 0.40 * w, 0.30 * h, 3, 0xFF00_00FF),
    ];
    let img = render_rects(&rects);
    assert_golden(&img, &golden_path("rect_stacked.png"));
}
