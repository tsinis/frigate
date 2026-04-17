//! Golden image tests for rectangle rendering.
//!
//! Goldens compare the *RGBA buffer* (lossless, deterministic). These baselines lock in the
//! current hand-rolled `stroke_rect_rgba` behavior so the upcoming `tiny-skia` migration
//! (steps 1–5 of the plan) can be validated visually with a tolerance pass before the goldens
//! are regenerated from the new renderer.
//!
//! First-run workflow:
//!   1. `cargo test --test rect_golden` — panics for each missing golden with the new file path.
//!   2. Inspect the generated PNGs in `tests/golden/`, then commit.

use std::path::{Path, PathBuf};

use image::RgbaImage;

use frigate::{FfiElement, element_type};

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

fn base_image() -> RgbaImage {
    let path = assets_dir().join("paint.jpg");
    image::open(&path)
        .unwrap_or_else(|_| panic!("failed to decode {path:?}"))
        .into_rgba8()
}

fn make_rect(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u32,
    outline_color_argb: u32,
) -> FfiElement {
    make_rect_with_fill(x, y, width, height, outline_thickness, outline_color_argb, 0)
}

fn make_rect_with_fill(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u32,
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

// 8 positional args is the natural shape of "make me a full FfiElement for a test" — splitting
// into a struct here would only push the same arg list into the struct literal at every call.
#[allow(clippy::too_many_arguments)]
fn make_rect_full(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u32,
    outline_color_argb: u32,
    fill_color_argb: u32,
    corner_radius_px: u32,
) -> FfiElement {
    FfiElement {
        element_type: element_type::RECTANGLE,
        x,
        y,
        width,
        height,
        rotation_deg: 0,
        fill_color_argb,
        outline_color_argb,
        outline_thickness,
        blur: 0,
        text_offset: 0,
        text_length: 0,
        shape_param: corner_radius_px,
    }
}

fn render_rects(rects: &[FfiElement]) -> RgbaImage {
    let mut img = base_image();
    for r in rects {
        frigate::draw_rect_element(&mut img, r);
    }
    img
}

fn assert_golden(actual: &RgbaImage, path: &Path) {
    // GUARD: every rect golden must change *something* compared to the unmodified base photo.
    // Without this, a test whose rect ends up entirely off-screen (or a renderer that silently
    // does nothing) passes trivially — `actual == saved-golden-which-also-equals-base` looks
    // green from the outside. This invariant catches "useless test" the moment it lands,
    // both locally and on CI's Linux x86 / ARM matrix, with no tolerance to tune.
    let base = base_image();
    assert_ne!(
        actual.as_raw(),
        base.as_raw(),
        "{path:?}: rendered output is byte-identical to the unmodified base image. \
         The rect is probably entirely off-screen — adjust coordinates so at least part of \
         the rect intersects the image bounds, otherwise the test isn't testing anything."
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
        0xFFFF0000, // opaque red
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_solid.png"));
}

#[test]
fn golden_rect_clipped_to_image_edges() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    // Rect's top-left corner sits OFF-SCREEN (negative coords); the bottom-right corner sits
    // INSIDE the image. We must see the bottom and right edges of the rect drawn well inside
    // the visible area, plus stroke material along the top and left where the rect crosses
    // the image edge — proving tiny-skia clips correctly without losing the visible portion.
    let rect = make_rect(
        -0.20 * w,
        -0.15 * h,
        0.70 * w,
        0.55 * h,
        6,
        0xFF00FF00, // opaque green
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_clipped.png"));
}

#[test]
fn golden_rect_thickness_clamped_to_min_side() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    // Stroke much larger than the rect's shortest side — `stroke_rect_rgba` auto-clamps to
    // min(clipped_w, clipped_h), effectively filling the rect.
    let rect = make_rect(
        0.10 * w,
        0.10 * h,
        0.20 * w,
        0.20 * h,
        9999,
        0xFF0000FF, // opaque blue
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_thick_clamped.png"));
}

#[test]
fn golden_rect_rounded_small_radius() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    // Modest radius — clearly rounded but well under the clamp ceiling.
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
    // Radius == min(w, h) / 2 → a pill (or a circle when w == h). Tests the clamp ceiling.
    let rect_w = 0.60 * w;
    let rect_h = 0.20 * h;
    let radius = (rect_w.min(rect_h) / 2.0) as u32;
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
    // Radius wildly exceeds min_side / 2 → must clamp to a clean pill, not corrupt geometry.
    // Visually identical to the "at clamp" case above for the same w/h ratio.
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
        99_999,
    );
    let img = render_rects(&[rect]);
    assert_golden(&img, &golden_path("rect_rounded_clamped.png"));
}

#[test]
fn golden_rect_translucent_fill_with_opaque_outline() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    // 50% red fill + opaque white outline — exercises fill+stroke ordering and translucent
    // src-over blending against the underlying photo.
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
    // Three overlapping rects in different colors — verifies draw order (later writes win,
    // since the current renderer overwrites pixels rather than alpha-blending) and that the
    // outline-only semantics leave each rect's interior visible to subsequent overdraws.
    let rects = [
        make_rect(0.10 * w, 0.10 * h, 0.50 * w, 0.50 * h, 3, 0xFFFF0000),
        make_rect(0.30 * w, 0.30 * h, 0.50 * w, 0.50 * h, 3, 0xFF00FF00),
        make_rect(0.20 * w, 0.40 * h, 0.40 * w, 0.30 * h, 3, 0xFF0000FF),
    ];
    let img = render_rects(&rects);
    assert_golden(&img, &golden_path("rect_stacked.png"));
}
