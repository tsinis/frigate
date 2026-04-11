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
