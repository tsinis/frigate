use image::RgbaImage;

/// Alpha-blends a single ARGB `tint_argb` colour over every pixel of `img`.
///
/// Straight-alpha source-over with integer `/255` math (mirroring the JPEG-flatten math in
/// `io::write_image`), performed in **sRGB / gamma-encoded space** — the same pragmatic choice the
/// blur op documents, so blur and tint stay visually consistent (linear-light is an accepted
/// future divergence). A zero-alpha tint is a no-op. Destination alpha is preserved (photos are
/// opaque; this keeps the JPEG flatten path unsurprising).
pub fn tint_rgba(img: &mut RgbaImage, tint_argb: u32) {
    let ta = (tint_argb >> 24) & 0xFF;
    if ta == 0 {
        return;
    }
    let tr = (tint_argb >> 16) & 0xFF;
    let tg = (tint_argb >> 8) & 0xFF;
    let tb = tint_argb & 0xFF;
    let inv = 255 - ta;

    for px in img.pixels_mut() {
        let r = u32::from(px.0[0]);
        let g = u32::from(px.0[1]);
        let b = u32::from(px.0[2]);
        px.0[0] = ((tr * ta + r * inv) / 255) as u8;
        px.0[1] = ((tg * ta + g * inv) / 255) as u8;
        px.0[2] = ((tb * ta + b * inv) / 255) as u8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_alpha_is_noop() {
        let mut img = RgbaImage::from_pixel(2, 2, image::Rgba([10, 20, 30, 255]));
        tint_rgba(&mut img, 0x00_FF_FF_FF);
        assert_eq!(img.get_pixel(0, 0).0, [10, 20, 30, 255]);
    }

    #[test]
    fn opaque_tint_replaces_rgb_keeps_alpha() {
        let mut img = RgbaImage::from_pixel(1, 1, image::Rgba([10, 20, 30, 200]));
        tint_rgba(&mut img, 0xFF_01_02_03);
        assert_eq!(img.get_pixel(0, 0).0, [1, 2, 3, 200]);
    }

    #[test]
    fn half_alpha_blends_midway() {
        let mut img = RgbaImage::from_pixel(1, 1, image::Rgba([0, 0, 0, 255]));
        // alpha 128 over black with white tint ≈ 128.
        tint_rgba(&mut img, 0x80_FF_FF_FF);
        let p = img.get_pixel(0, 0).0;
        assert!(p[0] >= 127 && p[0] <= 129, "got {}", p[0]);
        assert_eq!(p[3], 255);
    }
}
