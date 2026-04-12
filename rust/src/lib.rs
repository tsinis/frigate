use std::slice;

#[repr(C)]
pub struct FfiRectElement {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub stroke_width: f64,
    pub color_argb: u32,
}

const _: () = assert!(std::mem::size_of::<FfiRectElement>() == 48);

#[repr(C)]
pub struct ByteBuffer {
    pub data: *mut u8,
    pub length: usize,
}

/// Render rectangle overlays onto a source image and encode as JPEG.
///
/// Coordinates in `rects` are **normalized** (0.0-1.0 relative to image size).
/// Rust denormalizes using the decoded image dimensions — no width/height
/// params needed, and no mismatch if Flutter/Rust decoders disagree by a pixel.
///
/// Returns `ByteBuffer { null, 0 }` on panic (e.g. corrupt image).
/// Caller must check for null before using the result.
///
/// # Safety
///
/// - `img_ptr` must point to `img_len` valid bytes (the encoded image).
/// - `rects_ptr` must point to `rects_count` valid `FfiRectElement` structs.
/// - Both slices must remain valid for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn export_image(
    img_ptr: *const u8,
    img_len: usize,
    rects_ptr: *const FfiRectElement,
    rects_count: usize,
    jpeg_quality: u8,
) -> ByteBuffer {
    // SAFETY: img_ptr/img_len and rects_ptr/rects_count are valid (Dart allocated them).
    let img_bytes = unsafe { slice::from_raw_parts(img_ptr, img_len) };
    let rects = unsafe { slice::from_raw_parts(rects_ptr, rects_count) };

    // catch_unwind prevents panic from crossing the FFI boundary (which is UB).
    // On panic, return a null ByteBuffer — Dart checks and throws StateError.
    let result = std::panic::catch_unwind(|| render(img_bytes, rects, jpeg_quality));

    match result {
        Ok(bytes) => {
            // into_boxed_slice() shrinks capacity to exactly len, so
            // free_bytes can safely use Vec::from_raw_parts(ptr, len, len).
            let boxed = bytes.into_boxed_slice();
            let len = boxed.len();
            let ptr = Box::into_raw(boxed) as *mut u8;
            ByteBuffer {
                data: ptr,
                length: len,
            }
        }
        Err(_) => ByteBuffer {
            data: std::ptr::null_mut(),
            length: 0,
        },
    }
}

/// Free a byte buffer returned by `export_image`.
///
/// Capacity == len is guaranteed because `export_image` uses
/// `into_boxed_slice()` before extracting the raw pointer.
///
/// # Safety
///
/// - `ptr` must have been returned by `export_image` (via `Box::into_raw`).
/// - `len` must be the matching `ByteBuffer.length`.
/// - Must only be called once per buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    // SAFETY: ptr+len came from into_boxed_slice() + Box::into_raw() in export_image.
    unsafe { drop(Vec::from_raw_parts(ptr, len, len)) };
}

/// 100% safe Rust — all rendering logic here.
///
/// Rect coordinates are normalized (0.0-1.0). This function denormalizes
/// them using the decoded image dimensions, so the result is pixel-accurate
/// regardless of any Flutter↔Rust decoder dimension mismatch.
fn render(img_bytes: &[u8], rects: &[FfiRectElement], jpeg_quality: u8) -> Vec<u8> {
    use tiny_skia::*;

    let img = image::load_from_memory(img_bytes)
        .expect("failed to decode image")
        .into_rgba8();

    let (w, h) = (img.width(), img.height());
    let (wf, hf) = (w as f64, h as f64);
    let mut pixmap = Pixmap::from_vec(img.into_raw(), IntSize::from_wh(w, h).unwrap()).unwrap();

    for r in rects {
        // Denormalize from 0.0-1.0 to pixel coordinates.
        let px_x = (r.x * wf) as f32;
        let px_y = (r.y * hf) as f32;
        let px_w = (r.width * wf) as f32;
        let px_h = (r.height * hf) as f32;
        let px_stroke = (r.stroke_width * wf) as f32;

        let a = ((r.color_argb >> 24) & 0xFF) as f32 / 255.0;
        let red = ((r.color_argb >> 16) & 0xFF) as f32 / 255.0;
        let g = ((r.color_argb >> 8) & 0xFF) as f32 / 255.0;
        let b = (r.color_argb & 0xFF) as f32 / 255.0;

        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba(red, g, b, a).unwrap_or(Color::BLACK));
        paint.anti_alias = true;

        let stroke = Stroke {
            width: px_stroke,
            ..Stroke::default()
        };

        if let Some(rect) = Rect::from_xywh(px_x, px_y, px_w, px_h) {
            let path = PathBuilder::from_rect(rect);
            pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
        }
    }

    let rgba_img = image::RgbaImage::from_raw(w, h, pixmap.take()).unwrap();
    let rgb_img = image::DynamicImage::ImageRgba8(rgba_img).into_rgb8();
    let mut buf = std::io::Cursor::new(Vec::new());
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, jpeg_quality)
        .encode_image(&rgb_img)
        .unwrap();

    buf.into_inner()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Encode a tiny 2×2 red PNG in memory for tests.
    fn tiny_png() -> Vec<u8> {
        use image::{ImageEncoder, RgbaImage};
        let img = RgbaImage::from_pixel(2, 2, image::Rgba([255, 0, 0, 255]));
        let mut buf = std::io::Cursor::new(Vec::new());
        image::codecs::png::PngEncoder::new(&mut buf)
            .write_image(img.as_raw(), 2, 2, image::ExtendedColorType::Rgba8)
            .unwrap();
        buf.into_inner()
    }

    #[test]
    fn render_no_rects_returns_jpeg() {
        let png = tiny_png();
        let jpeg = render(&png, &[], 80);
        // JPEG files start with the SOI marker 0xFF 0xD8.
        assert!(jpeg.len() > 2);
        assert_eq!(&jpeg[..2], &[0xFF, 0xD8]);
    }

    #[test]
    fn render_with_rect_returns_jpeg() {
        let png = tiny_png();
        let rect = FfiRectElement {
            x: 0.1,
            y: 0.1,
            width: 0.8,
            height: 0.8,
            stroke_width: 0.05,
            color_argb: 0xFF00FF00, // opaque green
        };
        let jpeg = render(&png, &[rect], 90);
        assert!(jpeg.len() > 2);
        assert_eq!(&jpeg[..2], &[0xFF, 0xD8]);
    }

    #[test]
    fn ffi_rect_element_is_48_bytes() {
        // Mirrors the compile-time assert but also exercises it at test time.
        assert_eq!(std::mem::size_of::<FfiRectElement>(), 48);
    }

    #[test]
    #[should_panic(expected = "failed to decode image")]
    fn render_corrupt_image_panics() {
        render(&[0, 1, 2, 3], &[], 80);
    }

    #[test]
    fn export_image_returns_null_on_corrupt_input() {
        // Use a dangling-but-aligned pointer for the empty rects slice —
        // slice::from_raw_parts requires non-null even when count is 0.
        let rects_ptr = std::ptr::NonNull::<FfiRectElement>::dangling().as_ptr();
        let buf = unsafe { export_image(b"bad".as_ptr(), 3, rects_ptr, 0, 80) };
        // catch_unwind inside export_image turns the panic into a null buffer.
        assert!(buf.data.is_null());
        assert_eq!(buf.length, 0);
    }
}
