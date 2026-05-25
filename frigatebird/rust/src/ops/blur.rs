//! Gaussian blur for `RgbaImage` regions, with precise shape masking.
//!
//! # Impeller compatibility
//!
//! Flutter's `ImageFilter.blur(sigmaX, sigmaY)` uses sigma directly.
//! This module's public API uses **blur radius in image-space pixels** — the unit familiar to
//! Figma / Photoshop / CSS `filter: blur(Npx)` users. Sigma is derived internally:
//!
//! ```text
//! sigma = blur_radius as f32 / 3.0
//! ```
//!
//! So `blur_radius = 10` → sigma ≈ 3.3 px: a moderate blur.
//! A caller who needs exact Impeller sigma parity must pass `(sigma * 3.0) as u8`.
//!
//! # Gamma note
//!
//! `image::imageops::blur` operates in sRGB (gamma-encoded) space.
//! Flutter's Impeller applies blur in **linear-light** space.
//! For annotation-board usage (radius ≤ ~30, sigma ≤ 10) the visual delta is imperceptible.
//! If linear-light parity becomes a requirement, introduce a separate `blur_linear` entry point
//! that linearizes → blurs → re-encodes. This is a known, accepted divergence for v1.
//!
//! # Performance note
//!
//! // PERF: CPU-only single-threaded blur is a bottleneck for high-res images. wgpu/fastblur can optimize.

use image::{GenericImageView as _, RgbaImage};
use tiny_skia::Pixmap;

use crate::RectanglePayload;
use crate::ffi::FfiErrorCode;

/// Blend two RGBA pixels based on an alpha value from a mask (0..=255).
#[inline]
pub fn blend_pixel(bg: image::Rgba<u8>, blurred: image::Rgba<u8>, alpha: u8) -> image::Rgba<u8> {
    if alpha == 0 {
        return bg;
    }
    if alpha == 255 {
        return blurred;
    }
    let a = alpha as u32;
    let inv_a = 255 - a;
    image::Rgba([
        ((bg.0[0] as u32 * inv_a + blurred.0[0] as u32 * a) / 255) as u8,
        ((bg.0[1] as u32 * inv_a + blurred.0[1] as u32 * a) / 255) as u8,
        ((bg.0[2] as u32 * inv_a + blurred.0[2] as u32 * a) / 255) as u8,
        ((bg.0[3] as u32 * inv_a + blurred.0[3] as u32 * a) / 255) as u8,
    ])
}

/// Blur a shape-masked region of `img` in-place, reading pixels from `src`.
///
/// `rect` defines the bounding box coordinates of the shape.
/// `blur_radius_px` is the blur radius (if 0, is a guaranteed immediate no-op).
///
/// `draw_mask_fn` is a closure that draws the shape's relative mask in solid white onto a
/// temporary `tiny_skia::Pixmap` representing the shape's bounding box. The closure is passed
/// the relative Pixmap along with the absolute `(rx, ry)` offset of the cropped region, which
/// allows it to apply exact translation offsets.
pub fn blur_shape_rgba_from_src<F>(
    img: &mut RgbaImage,
    src: &RgbaImage,
    rect: RectanglePayload,
    blur_radius_px: u8,
    draw_mask_fn: F,
) -> Result<(), (FfiErrorCode, String)>
where
    F: FnOnce(&mut Pixmap, f64, f64) -> Result<(), (FfiErrorCode, String)>,
{
    if blur_radius_px == 0 {
        return Ok(());
    }

    if rect.width == 0.0 || rect.height == 0.0 {
        // Zero-area/collapsed shape is a safe no-op.
        return Ok(());
    }

    let sigma = blur_radius_px as f32 / 3.0;
    let (iw, ih) = src.dimensions();

    // Support flipped/negative dimensions robustly
    let x_raw = (rect.x as i64).clamp(0, iw as i64) as u32;
    let y_raw = (rect.y as i64).clamp(0, ih as i64) as u32;
    let x2_raw = ((rect.x + rect.width) as i64).clamp(0, iw as i64) as u32;
    let y2_raw = ((rect.y + rect.height) as i64).clamp(0, ih as i64) as u32;

    let (x, x2) = if rect.width < 0.0 {
        (x2_raw, x_raw)
    } else {
        (x_raw, x2_raw)
    };
    let (y, y2) = if rect.height < 0.0 {
        (y2_raw, y_raw)
    } else {
        (y_raw, y2_raw)
    };

    let (rx, ry, rw, rh) = (x, y, x2.saturating_sub(x), y2.saturating_sub(y));

    if rw == 0 || rh == 0 {
        // After clamping the region is empty — no-op.
        return Ok(());
    }

    // Gaussian Padding to eliminate boundary edge artifacts.
    // Pad the crop bounding box by `pad = blur_radius_px * 3`.
    let pad = (blur_radius_px as u32).saturating_mul(3);
    let px_start = rx.saturating_sub(pad);
    let py_start = ry.saturating_sub(pad);
    let px_end = (rx + rw + pad).min(iw);
    let py_end = (ry + rh + pad).min(ih);

    let pw = px_end.saturating_sub(px_start);
    let ph = py_end.saturating_sub(py_start);

    if pw == 0 || ph == 0 {
        return Ok(());
    }

    // Crop padded sub-image from src -> apply blur.
    let sub = src.view(px_start, py_start, pw, ph).to_image();
    let blurred_sub = image::imageops::blur(&sub, sigma);

    debug_assert_eq!(sub.dimensions(), blurred_sub.dimensions());

    // Create a relative tiny_skia Pixmap of the same size to serve as the shape mask.
    let mut mask = Pixmap::new(rw, rh).ok_or_else(|| {
        (
            FfiErrorCode::Render,
            "Failed to allocate tiny_skia Pixmap for mask".to_string(),
        )
    })?;

    // Draw the shape mask in solid white inside the relative pixmap coordinates.
    // Propagate errors from draw_mask_fn closure cleanly using ? operator.
    draw_mask_fn(&mut mask, rx as f64, ry as f64)?;

    // Blend pixels back based on the shape's mask alpha.
    for y in 0..rh {
        for x in 0..rw {
            if let Some(mask_px) = mask.pixel(x, y) {
                let alpha = mask_px.alpha();
                if alpha > 0 {
                    let bx = (rx + x).saturating_sub(px_start);
                    let by = (ry + y).saturating_sub(py_start);
                    if bx < pw && by < ph {
                        let bg = img.get_pixel(rx + x, ry + y);
                        let bl = blurred_sub.get_pixel(bx, by);
                        img.put_pixel(rx + x, ry + y, blend_pixel(*bg, *bl, alpha));
                    }
                }
            }
        }
    }

    Ok(())
}

/// Blur a shape-masked region of `img` in-place.
///
/// `rect` defines the bounding box coordinates of the shape.
/// `blur_radius_px` is the blur radius (if 0, is a guaranteed immediate no-op).
///
/// `draw_mask_fn` is a closure that draws the shape's relative mask in solid white onto a
/// temporary `tiny_skia::Pixmap` representing the shape's bounding box. The closure is passed
/// the relative Pixmap along with the absolute `(rx, ry)` offset of the cropped region, which
/// allows it to apply exact translation offsets.
pub fn blur_shape_rgba<F>(
    img: &mut RgbaImage,
    rect: RectanglePayload,
    blur_radius_px: u8,
    draw_mask_fn: F,
) -> Result<(), (FfiErrorCode, String)>
where
    F: FnOnce(&mut Pixmap, f64, f64) -> Result<(), (FfiErrorCode, String)>,
{
    if blur_radius_px == 0 {
        return Ok(());
    }

    if rect.width == 0.0 || rect.height == 0.0 {
        return Ok(());
    }

    let src = img.clone();
    blur_shape_rgba_from_src(img, &src, rect, blur_radius_px, draw_mask_fn)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::RectanglePayload;

    fn solid_image(w: u32, h: u32, color: [u8; 4]) -> RgbaImage {
        RgbaImage::from_pixel(w, h, image::Rgba(color))
    }

    fn full_rect_payload(w: u32, h: u32) -> RectanglePayload {
        RectanglePayload::new(0.0, 0.0, w as f64, h as f64, 0)
    }

    #[test]
    fn test_blend_pixel() {
        let bg = image::Rgba([100, 100, 100, 255]);
        let bl = image::Rgba([200, 200, 200, 255]);

        assert_eq!(blend_pixel(bg, bl, 0), bg);
        assert_eq!(blend_pixel(bg, bl, 255), bl);
        assert_eq!(blend_pixel(bg, bl, 128).0[0], 150);
    }

    #[test]
    fn blur_radius_zero_is_noop() {
        let mut img = solid_image(8, 8, [255, 0, 0, 255]);
        let before = img.clone();
        blur_shape_rgba(&mut img, full_rect_payload(8, 8), 0, |_, _, _| Ok(())).unwrap();
        assert_eq!(
            img.as_raw(),
            before.as_raw(),
            "radius=0 must leave image unchanged"
        );
    }

    #[test]
    #[cfg(not(miri))] // image::imageops::blur uses SIMD
    fn blur_changes_pixels_on_non_uniform_image() {
        let mut img = RgbaImage::new(16, 16);
        for (x, _, px) in img.enumerate_pixels_mut() {
            px.0 = if x < 8 {
                [0, 0, 0, 255]
            } else {
                [255, 255, 255, 255]
            };
        }
        let before = img.clone();
        blur_shape_rgba(&mut img, full_rect_payload(16, 16), 6, |mask, _, _| {
            mask.fill(tiny_skia::Color::from_rgba8(255, 255, 255, 255));
            Ok(())
        })
        .unwrap();
        assert_ne!(
            img.as_raw(),
            before.as_raw(),
            "blur must change pixels on non-uniform image"
        );
    }

    #[test]
    #[cfg(not(miri))]
    fn blur_region_zero_area_is_noop() {
        let mut img = RgbaImage::new(16, 16);
        for (x, _, px) in img.enumerate_pixels_mut() {
            px.0 = if x < 8 {
                [0, 0, 0, 255]
            } else {
                [255, 255, 255, 255]
            };
        }
        let before = img.clone();
        let zero_rect = RectanglePayload::new(0.0, 0.0, 0.0, 0.0, 0);
        blur_shape_rgba(&mut img, zero_rect, 6, |mask, _, _| {
            mask.fill(tiny_skia::Color::from_rgba8(255, 255, 255, 255));
            Ok(())
        })
        .unwrap();
        assert_eq!(
            img.as_raw(),
            before.as_raw(),
            "zero-area rect must be a safe no-op"
        );
    }

    #[test]
    fn blur_rect_entirely_outside_image_is_noop() {
        let mut img = solid_image(16, 16, [100, 100, 100, 255]);
        let before = img.clone();
        let outside = RectanglePayload::new(1000.0, 0.0, 50.0, 50.0, 0);
        blur_shape_rgba(&mut img, outside, 10, |_, _, _| Ok(())).unwrap();
        assert_eq!(
            img.as_raw(),
            before.as_raw(),
            "out-of-bounds rect must be a no-op"
        );
    }

    #[test]
    #[cfg(not(miri))]
    fn blur_region_negative_dimensions_swap_correctly() {
        let mut img = RgbaImage::new(16, 16);
        for (x, _, px) in img.enumerate_pixels_mut() {
            px.0 = if x < 8 {
                [0, 0, 0, 255]
            } else {
                [255, 255, 255, 255]
            };
        }
        let before = img.clone();

        // Negative dimensions: should swap x and x2, y and y2, and perform blur
        let negative_rect = RectanglePayload::new(16.0, 16.0, -16.0, -16.0, 0);
        blur_shape_rgba(&mut img, negative_rect, 6, |mask, _, _| {
            mask.fill(tiny_skia::Color::from_rgba8(255, 255, 255, 255));
            Ok(())
        })
        .unwrap();

        assert_ne!(
            img.as_raw(),
            before.as_raw(),
            "negative dimensions must swap correctly and apply blur"
        );
    }
}
