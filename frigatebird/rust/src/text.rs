//! Text overlay rendering. Pure safe Rust — no I/O, no FFI.
//!
//! Split out from `lib.rs` so it is unit-testable directly without crossing the FFI boundary.
//!
//! Pipeline: rasterize → optional rotate → alpha-composite. Each stage is independently skippable
//! so the common case (plain axis-aligned text) pays zero cost for features it doesn't use.
//!
//! Why we don't pull in `imageproc`: we only need three primitives — glyph rasterization,
//! source-over blending, and arbitrary-angle rotation — and they're ~100 lines of straightforward
//! code with `ab_glyph`. Dropping `imageproc` also drops `nalgebra`, `rand`, and `conv` from the
//! transitive tree.

use ab_glyph::{Font, FontRef, Glyph, PxScale, ScaleFont};
use image::{Rgba, RgbaImage};

/// Pixel-space text-rendering parameters. `x`, `y`, and `font_size_px` are all in the same units
/// as the target image — Rust does not normalize, Dart does not normalize, and the on-wire
/// contract is pixels end-to-end.
pub struct TextParams<'a> {
    pub text: &'a str,
    /// Anchor x (top-left of the glyph-run bounding box, mirrors the original `imageproc`
    /// `draw_text_mut` semantics so existing callers don't need to shift their coords).
    pub x: f32,
    /// Anchor y.
    pub y: f32,
    /// Font em-box height in pixels (i.e. "font size").
    pub font_size_px: f32,
    /// Rotation in radians, counter-clockwise, about the `(x, y)` anchor.
    pub rotation_rad: f32,
    pub color: Rgba<u8>,
}

/// Mutate `img` in place with the rendered text. Returns early when there's nothing to do
/// (empty string) so the caller gets a deterministic "no-op leaves the image pixel-identical".
///
/// Optimized paths:
/// - **No rotation (common):** rasterizes directly onto `img` with per-glyph source-over
///   blending. Zero extra allocation.
/// - **With rotation:** allocates a tight bounding-box overlay (glyph-run size + margin),
///   not the full image size.
pub fn render_text_overlay(img: &mut RgbaImage, font: &FontRef<'_>, params: &TextParams<'_>) {
    if params.text.is_empty() {
        return;
    }

    let (iw, ih) = (img.width(), img.height());
    let max_reasonable = (iw.max(ih) as f32) * 4.0;
    let sanitized = if params.font_size_px.is_finite() {
        params.font_size_px
    } else {
        1.0
    };
    let scale = PxScale::from(sanitized.clamp(1.0, max_reasonable));

    if params.rotation_rad.abs() <= f32::EPSILON {
        // Fast path: no rotation — rasterize directly onto the image.
        rasterize_text_direct(
            img,
            font,
            scale,
            params.x,
            params.y,
            params.color,
            params.text,
        );
    } else {
        // Rotation path: use a tight bounding-box overlay.
        render_text_rotated(img, font, scale, params);
    }
}

/// Fast path: rasterize glyphs directly onto `img` with source-over blending per pixel.
/// No intermediate buffer allocation.
fn rasterize_text_direct(
    img: &mut RgbaImage,
    font: &FontRef<'_>,
    scale: PxScale,
    x: f32,
    y: f32,
    color: Rgba<u8>,
    text: &str,
) {
    let scaled = font.as_scaled(scale);
    let baseline_y = y + scaled.ascent();
    let mut caret_x = x;
    let mut prev_id: Option<ab_glyph::GlyphId> = None;
    let (iw, ih) = (img.width() as i32, img.height() as i32);

    for c in text.chars() {
        let id = font.glyph_id(c);
        if let Some(prev) = prev_id {
            caret_x += scaled.kern(prev, id);
        }
        let glyph: Glyph = id.with_scale_and_position(scale, ab_glyph::point(caret_x, baseline_y));
        caret_x += scaled.h_advance(id);
        prev_id = Some(id);

        let Some(outline) = font.outline_glyph(glyph) else {
            continue;
        };
        let bounds = outline.px_bounds();
        outline.draw(|gx, gy, coverage| {
            let px = bounds.min.x as i32 + gx as i32;
            let py = bounds.min.y as i32 + gy as i32;
            if px < 0 || py < 0 || px >= iw || py >= ih {
                return;
            }
            let glyph_alpha = (coverage.clamp(0.0, 1.0) * color[3] as f32) as u8;
            let src = Rgba([color[0], color[1], color[2], glyph_alpha]);
            let existing = *img.get_pixel(px as u32, py as u32);
            img.put_pixel(px as u32, py as u32, blend_src_over(src, existing));
        });
    }
}

/// Rotation path: computes tight glyph-run bbox, allocates small overlay, rotates, composites.
fn render_text_rotated(
    img: &mut RgbaImage,
    font: &FontRef<'_>,
    scale: PxScale,
    params: &TextParams<'_>,
) {
    let (iw, ih) = (img.width(), img.height());

    // Compute glyph-run bounding box to allocate a tight overlay.
    let scaled = font.as_scaled(scale);
    let baseline_y = params.y + scaled.ascent();
    let mut caret_x = params.x;
    let mut prev_id: Option<ab_glyph::GlyphId> = None;
    let mut min_x = f32::INFINITY;
    let mut min_y = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut max_y = f32::NEG_INFINITY;

    for c in params.text.chars() {
        let id = font.glyph_id(c);
        if let Some(prev) = prev_id {
            caret_x += scaled.kern(prev, id);
        }
        let glyph: Glyph = id.with_scale_and_position(scale, ab_glyph::point(caret_x, baseline_y));
        caret_x += scaled.h_advance(id);
        prev_id = Some(id);

        if let Some(outline) = font.outline_glyph(glyph) {
            let bounds = outline.px_bounds();
            min_x = min_x.min(bounds.min.x);
            min_y = min_y.min(bounds.min.y);
            max_x = max_x.max(bounds.max.x);
            max_y = max_y.max(bounds.max.y);
        }
    }

    if min_x >= max_x || min_y >= max_y {
        return; // No visible glyphs.
    }

    // Rotation happens about (params.x, params.y) — the anchor point, NOT the center
    // of the glyph run. Compute the max distance from the rotation center to any corner
    // of the glyph bounding box; that radius determines how large the overlay must be.
    let cx = params.x;
    let cy = params.y;
    let corners: [(f32, f32); 4] = [
        (min_x, min_y),
        (max_x, min_y),
        (min_x, max_y),
        (max_x, max_y),
    ];
    let radius = corners
        .iter()
        .map(|&(x, y)| ((x - cx) * (x - cx) + (y - cy) * (y - cy)).sqrt())
        .fold(0.0f32, f32::max)
        .ceil();

    // Overlay centered on the rotation point, sized to encompass the full rotation arc.
    let ov_x = (cx - radius).floor().max(0.0) as u32;
    let ov_y = (cy - radius).floor().max(0.0) as u32;
    let ov_x2 = ((cx + radius).ceil() as u32).min(iw);
    let ov_y2 = ((cy + radius).ceil() as u32).min(ih);
    let ov_w = ov_x2.saturating_sub(ov_x);
    let ov_h = ov_y2.saturating_sub(ov_y);

    if ov_w == 0 || ov_h == 0 {
        return;
    }

    // Allocate tight overlay and rasterize with offset.
    let mut overlay = RgbaImage::from_pixel(ov_w, ov_h, Rgba([0, 0, 0, 0]));
    rasterize_text(
        &mut overlay,
        font,
        scale,
        params.x - ov_x as f32,
        params.y - ov_y as f32,
        params.color,
        params.text,
    );

    // Rotate about the anchor point (relative to overlay origin).
    let cx = params.x - ov_x as f32;
    let cy = params.y - ov_y as f32;
    let rotated = rotate_about(&overlay, cx, cy, params.rotation_rad);

    // Composite the rotated overlay back onto img at (ov_x, ov_y).
    for py in 0..ov_h {
        for px in 0..ov_w {
            let src_px = rotated.get_pixel(px, py);
            let sa = u32::from(src_px[3]);
            if sa == 0 {
                continue;
            }
            let dst_px = img.get_pixel_mut(ov_x + px, ov_y + py);
            let da = u32::from(dst_px[3]);
            let out_a = sa + da * (255 - sa) / 255;
            if out_a == 0 {
                continue;
            }
            for i in 0..3 {
                let s = u32::from(src_px[i]) * sa;
                let d = u32::from(dst_px[i]) * da * (255 - sa) / 255;
                dst_px[i] = ((s + d) / out_a) as u8;
            }
            dst_px[3] = out_a as u8;
        }
    }
}

/// Rasterize `text` glyph-by-glyph at `(x, y)` (top-left of the first glyph's bounding box).
/// Mirrors `imageproc::drawing::draw_text_mut` semantics so callers don't need to shift coords
/// when we swapped crates.
fn rasterize_text(
    dst: &mut RgbaImage,
    font: &FontRef<'_>,
    scale: PxScale,
    x: f32,
    y: f32,
    color: Rgba<u8>,
    text: &str,
) {
    let scaled = font.as_scaled(scale);
    // ab_glyph positions glyphs by the baseline; `imageproc` positions by the top-left. Shift
    // the baseline down by the ascent so `(x, y)` names the top of the text run.
    let baseline_y = y + scaled.ascent();
    let mut caret_x = x;
    let mut prev_id: Option<ab_glyph::GlyphId> = None;

    for c in text.chars() {
        let id = font.glyph_id(c);
        if let Some(prev) = prev_id {
            caret_x += scaled.kern(prev, id);
        }
        let glyph: Glyph = id.with_scale_and_position(scale, ab_glyph::point(caret_x, baseline_y));
        caret_x += scaled.h_advance(id);
        prev_id = Some(id);

        let Some(outline) = font.outline_glyph(glyph) else {
            // Whitespace / control characters have no outline — advance the caret and continue.
            continue;
        };
        let bounds = outline.px_bounds();
        outline.draw(|gx, gy, coverage| {
            let px = bounds.min.x as i32 + gx as i32;
            let py = bounds.min.y as i32 + gy as i32;
            if px < 0 || py < 0 || px >= dst.width() as i32 || py >= dst.height() as i32 {
                return;
            }
            // Blend this glyph pixel into the destination. `coverage` is 0.0..=1.0 — multiply
            // into the fill alpha, then source-over onto whatever's already in the overlay
            // (lets overlapping glyphs blend smoothly).
            let glyph_alpha = (coverage.clamp(0.0, 1.0) * color[3] as f32) as u8;
            let src = Rgba([color[0], color[1], color[2], glyph_alpha]);
            let existing = *dst.get_pixel(px as u32, py as u32);
            dst.put_pixel(px as u32, py as u32, blend_src_over(src, existing));
        });
    }
}

/// Rotate `src` by `angle_rad` about `(cx, cy)` using reverse mapping with bilinear sampling.
/// Output pixels outside the source map to fully transparent.
///
/// **Direction convention:** positive `angle_rad` is mathematical counter-clockwise (y-up).
/// Because image coordinates are y-down, that *appears* on screen as visual **clockwise** —
/// which is what the Dart-side `DrawElement.rotation` doc promises. If you pass 90° from Dart,
/// the text spins the same direction a clock's second hand goes.
///
/// **f64 internals:** the public contract accepts `f32` (matches `TextParams`), but trig and
/// bilinear math run in `f64`. Reason: Rust's `f32::cos`/`f32::sin` delegate to the system libm,
/// which is not bit-identical across glibc-x86_64 / glibc-arm64 / Apple libm. `f64` versions of
/// the same functions are much more tightly specified across those libms, so cross-platform
/// golden tests don't drift by one ULP and flake in CI.
fn rotate_about(src: &RgbaImage, cx: f32, cy: f32, angle_rad: f32) -> RgbaImage {
    let (w, h) = (src.width(), src.height());
    let mut dst = RgbaImage::from_pixel(w, h, Rgba([0, 0, 0, 0]));
    // For dst pixel (px, py) we want the source coord that lands on (px, py) after a CCW
    // rotation by `angle_rad` about (cx, cy). The inverse of a CCW rotation by θ is a CW
    // rotation by θ, which is the transpose — i.e. swap sin signs.
    let cx = f64::from(cx);
    let cy = f64::from(cy);
    let cos = f64::from(angle_rad).cos();
    let sin = f64::from(angle_rad).sin();
    let (max_x, max_y) = (w as i32 - 1, h as i32 - 1);

    for py in 0..h {
        for px in 0..w {
            let dx = f64::from(px) - cx;
            let dy = f64::from(py) - cy;
            let sx = cx + dx * cos + dy * sin;
            let sy = cy - dx * sin + dy * cos;
            // Bilinear sample. Skip if the source coord falls outside by more than one pixel
            // so we don't accidentally blend with the (invalid) edge.
            if sx < 0.0 || sy < 0.0 || sx > f64::from(max_x) || sy > f64::from(max_y) {
                continue;
            }
            let x0 = sx.floor() as i32;
            let y0 = sy.floor() as i32;
            let x1 = (x0 + 1).min(max_x);
            let y1 = (y0 + 1).min(max_y);
            let fx = sx - f64::from(x0);
            let fy = sy - f64::from(y0);
            let p00 = src.get_pixel(x0 as u32, y0 as u32).0;
            let p10 = src.get_pixel(x1 as u32, y0 as u32).0;
            let p01 = src.get_pixel(x0 as u32, y1 as u32).0;
            let p11 = src.get_pixel(x1 as u32, y1 as u32).0;
            let mut out = [0u8; 4];
            for c in 0..4 {
                let v = (1.0 - fx) * (1.0 - fy) * f64::from(p00[c])
                    + fx * (1.0 - fy) * f64::from(p10[c])
                    + (1.0 - fx) * fy * f64::from(p01[c])
                    + fx * fy * f64::from(p11[c]);
                out[c] = v as u8;
            }
            dst.put_pixel(px, py, Rgba(out));
        }
    }
    dst
}

/// Source-over blend in integer space (u32 to avoid overflow during `s + d`).
fn blend_src_over(src: Rgba<u8>, dst: Rgba<u8>) -> Rgba<u8> {
    let sa = u32::from(src[3]);
    if sa == 0 {
        return dst;
    }
    let da = u32::from(dst[3]);
    let out_a = sa + da * (255 - sa) / 255;
    if out_a == 0 {
        return Rgba([0, 0, 0, 0]);
    }
    let mut out = [0u8; 4];
    for i in 0..3 {
        let s = u32::from(src[i]) * sa;
        let d = u32::from(dst[i]) * da * (255 - sa) / 255;
        out[i] = ((s + d) / out_a) as u8;
    }
    out[3] = out_a as u8;
    Rgba(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Bundled test font. `ab_glyph` picks the default axis instance (wght=400) for variable
    // fonts — if a future ab_glyph update shifts rasterization the goldens will fail loudly and
    // we regenerate intentionally.
    const FONT_BYTES: &[u8] = include_bytes!("../tests/assets/RobotoMono-VariableFont_wght.ttf");

    fn black_image(w: u32, h: u32) -> RgbaImage {
        RgbaImage::from_pixel(w, h, Rgba([0, 0, 0, 255]))
    }

    fn font() -> FontRef<'static> {
        FontRef::try_from_slice(FONT_BYTES).expect("bundled test font should always parse")
    }

    fn base_params<'a>(text: &'a str) -> TextParams<'a> {
        TextParams {
            text,
            x: 4.0,
            y: 4.0,
            font_size_px: 12.0,
            rotation_rad: 0.0,
            color: Rgba([255, 255, 255, 255]),
        }
    }

    #[test]
    fn empty_text_is_noop() {
        let font = font();
        let mut img = black_image(16, 16);
        let before = img.clone();
        render_text_overlay(&mut img, &font, &base_params(""));
        assert_eq!(img.as_raw(), before.as_raw());
    }

    #[test]
    fn text_produces_non_black_pixels() {
        let font = font();
        let mut img = black_image(64, 32);
        render_text_overlay(
            &mut img,
            &font,
            &TextParams {
                text: "Hi",
                x: 4.0,
                y: 4.0,
                font_size_px: 20.0,
                rotation_rad: 0.0,
                color: Rgba([255, 0, 0, 255]),
            },
        );
        assert!(img.pixels().any(|p| p.0[0] > 0));
    }

    #[test]
    fn zero_font_size_does_not_panic() {
        let font = font();
        let mut img = black_image(16, 16);
        render_text_overlay(
            &mut img,
            &font,
            &TextParams {
                font_size_px: 0.0,
                ..base_params("Hi")
            },
        );
    }

    #[test]
    fn out_of_bounds_anchor_does_not_panic() {
        let font = font();
        let mut img = black_image(16, 16);
        render_text_overlay(
            &mut img,
            &font,
            &TextParams {
                text: "Hello World",
                x: 100.0,
                y: 100.0,
                ..base_params("Hello World")
            },
        );
    }

    #[test]
    fn rotated_text_differs_from_unrotated() {
        let font = font();
        let mut a = black_image(64, 64);
        let mut b = black_image(64, 64);
        render_text_overlay(&mut a, &font, &base_params("Hi"));
        render_text_overlay(
            &mut b,
            &font,
            &TextParams {
                rotation_rad: std::f32::consts::FRAC_PI_4,
                ..base_params("Hi")
            },
        );
        assert_ne!(
            a.as_raw(),
            b.as_raw(),
            "rotation should produce different pixels"
        );
    }

    #[test]
    fn full_rotation_round_trips_close_to_identity() {
        // Rotating by 2π should produce (nearly) the same image. Bilinear sampling adds tiny
        // rounding error, but the difference should be bounded by ~1 per channel.
        let font = font();
        let mut a = black_image(32, 32);
        let mut b = black_image(32, 32);
        render_text_overlay(&mut a, &font, &base_params("Hi"));
        render_text_overlay(
            &mut b,
            &font,
            &TextParams {
                rotation_rad: std::f32::consts::TAU,
                ..base_params("Hi")
            },
        );
        let max_diff = a
            .as_raw()
            .iter()
            .zip(b.as_raw().iter())
            .map(|(x, y)| x.abs_diff(*y))
            .max()
            .unwrap_or(0);
        assert!(max_diff <= 3, "2π rotation drift > 3, got {max_diff}");
    }

    #[test]
    fn render_text_survives_pathological_font_size() {
        // `font_size_px` originates from a Dart-side `f64` (`TextElement.fontSize`). A caller
        // who passes 1e10 must not crash the renderer — at worst we get a (mostly) empty
        // image because the glyph bounds land off-screen. The point of this test is "never
        // panic", not "renders correctly at insane sizes".
        let font = font();
        let mut img = black_image(64, 64);
        render_text_overlay(
            &mut img,
            &font,
            &TextParams {
                text: "Hi",
                x: 0.0,
                y: 0.0,
                font_size_px: 1e10,
                rotation_rad: 0.0,
                color: Rgba([255, 255, 255, 255]),
            },
        );
        // Reaching this line is the assertion. (No `expect!` needed — the test framework
        // marks the test failed if anything above panicked.)
    }

    #[test]
    fn render_text_survives_nan_and_infinite_font_size() {
        // `f32::clamp(NaN, lo, hi)` returns NaN, which used to feed ab_glyph's rasterizer and
        // panic inside a `_ as i32` cast. The non-finite guard substitutes the lower bound so
        // NaN / ±inf all render as a tiny-but-valid glyph run.
        let font = font();
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let mut img = black_image(32, 32);
            render_text_overlay(
                &mut img,
                &font,
                &TextParams {
                    text: "Hi",
                    x: 4.0,
                    y: 4.0,
                    font_size_px: bad,
                    rotation_rad: 0.0,
                    color: Rgba([255, 255, 255, 255]),
                },
            );
        }
    }

    #[test]
    fn render_text_survives_negative_font_size() {
        // f32 negatives also possible from a Dart caller. The clamp on line 42 caps to 1.0,
        // so this should render normally.
        let font = font();
        let mut img = black_image(32, 32);
        render_text_overlay(
            &mut img,
            &font,
            &TextParams {
                text: "Hi",
                x: 4.0,
                y: 4.0,
                font_size_px: -100.0,
                rotation_rad: 0.0,
                color: Rgba([255, 255, 255, 255]),
            },
        );
    }

    #[test]
    fn translucent_source_blends_with_existing_background() {
        let font = font();
        let mut img = RgbaImage::from_pixel(8, 8, Rgba([100, 100, 100, 255]));
        render_text_overlay(
            &mut img,
            &font,
            &TextParams {
                text: "H",
                x: 0.0,
                y: 0.0,
                font_size_px: 10.0,
                rotation_rad: 0.0,
                // Half-opaque red: compositing should produce some pixels with R>100 but not 255.
                color: Rgba([255, 0, 0, 128]),
            },
        );
        assert!(img.pixels().all(|p| p.0[3] == 255));
        assert!(img.pixels().any(|p| p.0[0] > 100));
    }

    #[test]
    fn blend_src_over_fully_opaque_source_replaces_dst() {
        let out = blend_src_over(Rgba([200, 0, 0, 255]), Rgba([0, 200, 0, 255]));
        assert_eq!(out.0, [200, 0, 0, 255]);
    }

    #[test]
    fn blend_src_over_zero_alpha_source_leaves_dst() {
        let out = blend_src_over(Rgba([200, 0, 0, 0]), Rgba([0, 200, 0, 255]));
        assert_eq!(out.0, [0, 200, 0, 255]);
    }

    #[test]
    fn blend_src_over_transparent_source_is_a_no_op_on_dst() {
        // sa == 0 → the fast-path returns dst unchanged. RGB stays the way the caller provided
        // it (straight-alpha convention — we don't pre-multiply). The alpha stays 0.
        let out = blend_src_over(Rgba([200, 0, 0, 0]), Rgba([0, 200, 0, 0]));
        assert_eq!(out.0, [0, 200, 0, 0]);
    }

    #[test]
    fn rotate_by_zero_is_pixel_identical() {
        let mut src = RgbaImage::new(8, 8);
        for y in 0..8 {
            for x in 0..8 {
                src.put_pixel(x, y, Rgba([x as u8 * 16, y as u8 * 16, 0, 255]));
            }
        }
        let rotated = rotate_about(&src, 4.0, 4.0, 0.0);
        assert_eq!(rotated.as_raw(), src.as_raw());
    }

    #[test]
    fn rotate_90_degrees_moves_pixels_to_expected_positions() {
        // 3×3 image, red pixel at (2, 1) — right-of-centre. Rotating the content 90° CCW about
        // (1, 1) in screen coords (y-down) visually takes "right" → "down", so the red pixel
        // ends up below centre at (1, 2).
        let mut src = RgbaImage::from_pixel(3, 3, Rgba([0, 0, 0, 255]));
        src.put_pixel(2, 1, Rgba([255, 0, 0, 255]));
        let rotated = rotate_about(&src, 1.0, 1.0, std::f32::consts::FRAC_PI_2);
        let moved = rotated.get_pixel(1, 2).0;
        assert!(
            moved[0] > 200,
            "expected red pixel at (1, 2), got {moved:?}"
        );
    }

    #[test]
    fn rotated_45_text_extends_along_diagonal() {
        // Property test: text rotated 45° CW at anchor (10, 10) on a large image must have
        // non-background pixels well below the anchor along the diagonal. This catches
        // clipping bugs where the overlay is too small and truncates the rotated text.
        let font = font();
        let mut img = black_image(200, 200);
        render_text_overlay(
            &mut img,
            &font,
            &TextParams {
                text: "LongTextForTest",
                x: 10.0,
                y: 10.0,
                font_size_px: 16.0,
                rotation_rad: std::f32::consts::FRAC_PI_4,
                color: Rgba([255, 255, 255, 255]),
            },
        );

        // After 45° CW rotation about (10, 10), the text extends diagonally to ~y=95.
        // The tight-bbox clipping bug (using diagonal/2 padding) would limit the overlay
        // to ~y=76, clipping text below that. Assert pixels exist at y>=80.
        let has_text_below_80 = img
            .enumerate_pixels()
            .any(|(_, y, px)| y >= 80 && px.0 != [0, 0, 0, 255]);
        assert!(
            has_text_below_80,
            "rotated text must extend below y=80 along diagonal; overlay clipping bug if not"
        );
    }
}
