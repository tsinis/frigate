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
pub fn render_text_overlay(img: &mut RgbaImage, font: &FontRef<'_>, params: &TextParams<'_>) {
    if params.text.is_empty() {
        return;
    }

    let (iw, ih) = (img.width(), img.height());
    // Clamp to avoid a zero-pixel scale that would produce an empty glyph bitmap for 0.0 input.
    let scale = PxScale::from(params.font_size_px.max(1.0));

    // Overlay buffer matches the base size so rotation shares a single coordinate system with
    // the base image — no per-glyph bounding-box math.
    let mut overlay: RgbaImage = RgbaImage::from_pixel(iw, ih, Rgba([0, 0, 0, 0]));
    rasterize_text(&mut overlay, font, scale, params.x, params.y, params.color, params.text);

    // Rotation about (x, y). We rotate the overlay in place with bilinear reverse-mapping
    // (for each dst pixel, compute where it came from in the source and sample).
    let rotated;
    let final_overlay: &RgbaImage = if params.rotation_rad.abs() > f32::EPSILON {
        rotated = rotate_about(&overlay, params.x, params.y, params.rotation_rad);
        &rotated
    } else {
        &overlay
    };

    // Source-over composite. Sum in `u32` to avoid `u8` overflow during `s + d`; otherwise
    // two bright pixels would wrap around. Formula: out_a = sa + da * (255 - sa) / 255;
    // out_rgb = (fg * fa + bg * ba * (1 - fa)) / out_a.
    for (dst_px, src_px) in img.pixels_mut().zip(final_overlay.pixels()) {
        let sa = u32::from(src_px[3]);
        if sa == 0 {
            continue;
        }
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

/// Rotate `src` counter-clockwise by `angle_rad` about `(cx, cy)` using reverse mapping with
/// bilinear sampling. Output pixels outside the source map to fully transparent.
fn rotate_about(src: &RgbaImage, cx: f32, cy: f32, angle_rad: f32) -> RgbaImage {
    let (w, h) = (src.width(), src.height());
    let mut dst = RgbaImage::from_pixel(w, h, Rgba([0, 0, 0, 0]));
    // For dst pixel (px, py) we want the source coord that lands on (px, py) after a CCW
    // rotation by angle about (cx, cy). The inverse of a CCW rotation by θ is a CW rotation
    // by θ — which is the transpose, i.e. swap sin signs.
    let cos = angle_rad.cos();
    let sin = angle_rad.sin();
    let (max_x, max_y) = (w as i32 - 1, h as i32 - 1);

    for py in 0..h {
        for px in 0..w {
            let dx = px as f32 - cx;
            let dy = py as f32 - cy;
            let sx = cx + dx * cos + dy * sin;
            let sy = cy - dx * sin + dy * cos;
            // Bilinear sample. Skip if the source coord falls outside by more than one pixel
            // so we don't accidentally blend with the (invalid) edge.
            if sx < 0.0 || sy < 0.0 || sx > max_x as f32 || sy > max_y as f32 {
                continue;
            }
            let x0 = sx.floor() as i32;
            let y0 = sy.floor() as i32;
            let x1 = (x0 + 1).min(max_x);
            let y1 = (y0 + 1).min(max_y);
            let fx = sx - x0 as f32;
            let fy = sy - y0 as f32;
            let p00 = src.get_pixel(x0 as u32, y0 as u32).0;
            let p10 = src.get_pixel(x1 as u32, y0 as u32).0;
            let p01 = src.get_pixel(x0 as u32, y1 as u32).0;
            let p11 = src.get_pixel(x1 as u32, y1 as u32).0;
            let mut out = [0u8; 4];
            for c in 0..4 {
                let v = (1.0 - fx) * (1.0 - fy) * p00[c] as f32
                    + fx * (1.0 - fy) * p10[c] as f32
                    + (1.0 - fx) * fy * p01[c] as f32
                    + fx * fy * p11[c] as f32;
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
    const FONT_BYTES: &[u8] =
        include_bytes!("../../test/assets/RobotoMono-VariableFont_wght.ttf");

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
        assert_ne!(a.as_raw(), b.as_raw(), "rotation should produce different pixels");
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
        assert!(moved[0] > 200, "expected red pixel at (1, 2), got {moved:?}");
    }
}
