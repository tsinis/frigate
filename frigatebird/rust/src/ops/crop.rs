use image::RgbaImage;

use crate::ffi::FfiErrorCode;

/// Crops `img` to the rectangle (`x`, `y`, `width`, `height`) given in image-space pixels.
///
/// The rect is clamped to the image bounds (origin floored, far edge ceiled) so an `f64` rect that
/// nominally equals the full image resolves to a no-op crop. Returns:
/// - `Ok(None)` when the clamped box covers the whole image (the caller keeps the original),
/// - `Ok(Some(cropped))` for a proper sub-region,
/// - `Err(InvalidArg)` for a degenerate (non-finite / non-positive extent) or fully out-of-bounds box.
pub fn crop_rgba(
    img: &RgbaImage,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
) -> Result<Option<RgbaImage>, (FfiErrorCode, String)> {
    if !(x.is_finite() && y.is_finite() && width.is_finite() && height.is_finite())
        || width <= 0.0
        || height <= 0.0
    {
        return Err((
            FfiErrorCode::InvalidArg,
            "Invalid crop rectangle".to_string(),
        ));
    }

    let (iw, ih) = img.dimensions();
    // `as u32` saturates on overflow (Rust ≥ 1.45), so an absurd coordinate clamps rather than wraps.
    let x0 = x.floor().max(0.0) as u32;
    let y0 = y.floor().max(0.0) as u32;
    let x1 = ((x + width).ceil().max(0.0) as u32).min(iw);
    let y1 = ((y + height).ceil().max(0.0) as u32).min(ih);

    if x1 <= x0 || y1 <= y0 {
        return Err((
            FfiErrorCode::InvalidArg,
            "Crop rectangle is outside the image".to_string(),
        ));
    }

    let (cw, ch) = (x1 - x0, y1 - y0);
    if x0 == 0 && y0 == 0 && cw == iw && ch == ih {
        return Ok(None); // Full-image crop == no crop.
    }

    Ok(Some(
        image::imageops::crop_imm(img, x0, y0, cw, ch).to_image(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn img(w: u32, h: u32) -> RgbaImage {
        RgbaImage::from_pixel(w, h, image::Rgba([1, 2, 3, 255]))
    }

    #[test]
    fn full_image_rect_is_no_crop() {
        assert!(
            crop_rgba(&img(100, 80), 0.0, 0.0, 100.0, 80.0)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn sub_region_crops_to_dimensions() {
        let out = crop_rgba(&img(100, 80), 10.0, 20.0, 40.0, 30.0)
            .unwrap()
            .unwrap();
        assert_eq!(out.dimensions(), (40, 30));
    }

    #[test]
    fn out_of_bounds_rect_clamps_then_crops() {
        // Far edge beyond the image clamps to the image bound.
        let out = crop_rgba(&img(100, 80), 90.0, 0.0, 50.0, 80.0)
            .unwrap()
            .unwrap();
        assert_eq!(out.dimensions(), (10, 80));
    }

    #[test]
    fn degenerate_rect_errors() {
        assert_eq!(
            crop_rgba(&img(100, 80), 0.0, 0.0, 0.0, 10.0).unwrap_err().0,
            FfiErrorCode::InvalidArg
        );
    }

    #[test]
    fn fully_outside_rect_errors() {
        assert_eq!(
            crop_rgba(&img(100, 80), 200.0, 200.0, 10.0, 10.0)
                .unwrap_err()
                .0,
            FfiErrorCode::InvalidArg
        );
    }
}
