use std::ffi::{CStr, c_char};
use std::path::Path;
use std::slice;

mod ffi_element;
pub mod io;
pub mod text;

pub use ffi_element::{FfiElement, element_type};

#[repr(C)]
pub struct FfiRectElement {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub outline_thickness: u32,
    pub outline_color_argb: u32,
}

// 4 × f64 (32) + 2 × u32 (8) = 40 bytes; struct alignment = 8 so size is padded to 40.
const _: () = assert!(std::mem::size_of::<FfiRectElement>() == 40);

#[repr(C)]
pub struct ByteBuffer {
    pub data: *mut u8,
    pub length: usize,
}

/// Render rectangle overlays onto a source image and encode as JPEG.
///
/// Bytes-in / bytes-out — used by the Flutter integration via `ExportBackend`. Coordinates are
/// **pixels** (no normalization). Returns a null `ByteBuffer.data` on panic; the caller checks and
/// reports a typed error.
///
/// # Safety
/// - `img_ptr` must point to `img_len` valid bytes.
/// - `rects_ptr` must point to `rects_count` valid `FfiRectElement` structs.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn export_image(
    img_ptr: *const u8,
    img_len: usize,
    rects_ptr: *const FfiRectElement,
    rects_count: usize,
    image_quality: u8,
) -> ByteBuffer {
    let img_bytes = unsafe { slice::from_raw_parts(img_ptr, img_len) };
    let rects = unsafe { slice::from_raw_parts(rects_ptr, rects_count) };
    // catch_unwind: panicking across an FFI boundary is undefined behavior.
    let result = std::panic::catch_unwind(|| render_jpeg_with_rects(img_bytes, rects, image_quality));
    match result {
        Ok(bytes) => {
            // into_boxed_slice shrinks capacity to == len, so free_bytes can reconstruct the Vec
            // safely with Vec::from_raw_parts(ptr, len, len).
            let boxed = bytes.into_boxed_slice();
            let len = boxed.len();
            let ptr = Box::into_raw(boxed) as *mut u8;
            ByteBuffer { data: ptr, length: len }
        }
        Err(_) => ByteBuffer { data: std::ptr::null_mut(), length: 0 },
    }
}

/// Free a buffer returned by [`export_image`]. No-op for null pointers.
///
/// # Safety
/// `ptr` must have been returned by `export_image` (and not yet freed); `len` must match the
/// `ByteBuffer.length` from that return value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    unsafe { drop(Vec::from_raw_parts(ptr, len, len)) };
}

/// Error codes returned by [`render_image`].
#[derive(Debug)]
enum RenderError {
    ImageDecode,
    FontRead,
    FontParse,
    BadUtf8Text,
    BadUtf8Path,
    ImageWrite,
    NullPtr,
    /// A `TextElement` was present but `font_path_ptr` was null.
    MissingFont,
}

impl RenderError {
    fn code(&self) -> i32 {
        match self {
            Self::ImageDecode => 1,
            Self::FontRead => 2,
            Self::FontParse => 3,
            Self::BadUtf8Text => 4,
            Self::BadUtf8Path => 5,
            Self::ImageWrite => 6,
            Self::NullPtr => 7,
            Self::MissingFont => 8,
        }
    }
}

impl From<io::IoError> for RenderError {
    fn from(e: io::IoError) -> Self {
        match e {
            io::IoError::Read | io::IoError::Decode => Self::ImageDecode,
            io::IoError::Write | io::IoError::Encode | io::IoError::UnsupportedFormat => Self::ImageWrite,
        }
    }
}

/// Render an arbitrary list of [`FfiElement`]s onto the image at `image_path_ptr` and write the
/// composited result to `output_path_ptr`.
///
/// `font_path_ptr` may be null when the element list contains no `TEXT` items.
///
/// `text_buffer_ptr` + `text_buffer_len` describe a shared UTF-8 buffer; each text element
/// references its slice via `text_offset` / `text_length`.
///
/// Returns:
/// - `0`  success
/// - `1`  image read/decode failed
/// - `2`  font read failed
/// - `3`  font parse failed
/// - `4`  text not valid UTF-8
/// - `5`  path not valid UTF-8
/// - `6`  image write failed
/// - `7`  null pointer for a required argument
/// - `8`  text element present but no font_path supplied
/// - `99` panic
///
/// # Safety
/// - `image_path_ptr`, `output_path_ptr` must be non-null, NUL-terminated, valid UTF-8 C strings.
/// - `font_path_ptr` may be null when no text elements; otherwise same constraints as above.
/// - `elements_ptr` must point to `elements_count` valid `FfiElement` structs (or be a dangling
///   non-null pointer when `elements_count == 0`).
/// - `text_buffer_ptr` may be null when `text_buffer_len == 0`; otherwise must point to
///   `text_buffer_len` valid bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn render_image(
    image_path_ptr: *const c_char,
    output_path_ptr: *const c_char,
    font_path_ptr: *const c_char,
    elements_ptr: *const FfiElement,
    elements_count: usize,
    text_buffer_ptr: *const u8,
    text_buffer_len: usize,
    image_quality: u8,
) -> i32 {
    let result = std::panic::catch_unwind(|| unsafe {
        render_image_inner(
            image_path_ptr,
            output_path_ptr,
            font_path_ptr,
            elements_ptr,
            elements_count,
            text_buffer_ptr,
            text_buffer_len,
            image_quality,
        )
    });
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => e.code(),
        Err(_) => 99,
    }
}

unsafe fn c_str_to_str<'a>(ptr: *const c_char) -> Result<&'a str, RenderError> {
    if ptr.is_null() {
        return Err(RenderError::NullPtr);
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().map_err(|_| RenderError::BadUtf8Path)
}

#[allow(clippy::too_many_arguments)]
unsafe fn render_image_inner(
    image_path_ptr: *const c_char,
    output_path_ptr: *const c_char,
    font_path_ptr: *const c_char,
    elements_ptr: *const FfiElement,
    elements_count: usize,
    text_buffer_ptr: *const u8,
    text_buffer_len: usize,
    image_quality: u8,
) -> Result<(), RenderError> {
    let image_path = unsafe { c_str_to_str(image_path_ptr) }?;
    let output_path = unsafe { c_str_to_str(output_path_ptr) }?;

    let elements: &[FfiElement] = if elements_count == 0 {
        &[]
    } else {
        if elements_ptr.is_null() {
            return Err(RenderError::NullPtr);
        }
        unsafe { slice::from_raw_parts(elements_ptr, elements_count) }
    };

    let text_buffer: &[u8] = if text_buffer_len == 0 {
        &[]
    } else {
        if text_buffer_ptr.is_null() {
            return Err(RenderError::NullPtr);
        }
        unsafe { slice::from_raw_parts(text_buffer_ptr, text_buffer_len) }
    };

    // Lazy-load the font: only required when the element list actually contains text.
    let needs_font = elements.iter().any(|e| e.element_type == element_type::TEXT);
    let font_bytes_holder;
    let font: Option<ab_glyph::FontRef<'_>> = if needs_font {
        if font_path_ptr.is_null() {
            return Err(RenderError::MissingFont);
        }
        let font_path = unsafe { c_str_to_str(font_path_ptr) }?;
        font_bytes_holder =
            io::read_font(Path::new(font_path)).map_err(|_| RenderError::FontRead)?;
        Some(
            ab_glyph::FontRef::try_from_slice(&font_bytes_holder)
                .map_err(|_| RenderError::FontParse)?,
        )
    } else {
        None
    };

    let mut img = io::read_image(Path::new(image_path))?.into_rgba8();

    for element in elements {
        match element.element_type {
            element_type::RECTANGLE => draw_rect_element(&mut img, element),
            element_type::TEXT => {
                let text_slice = element_text(element, text_buffer)?;
                if let Some(font_ref) = &font {
                    draw_text_element(&mut img, font_ref, element, text_slice);
                }
            }
            // Unknown element types are skipped silently — forward-compat for adding shapes
            // without breaking older Rust binaries that haven't shipped the new dispatch.
            _ => {}
        }
    }

    io::write_image(Path::new(output_path), &img, image_quality)
        .map_err(|_| RenderError::ImageWrite)?;
    Ok(())
}

fn element_text<'b>(
    element: &FfiElement,
    text_buffer: &'b [u8],
) -> Result<&'b str, RenderError> {
    let start = element.text_offset as usize;
    let len = element.text_length as usize;
    let end = start.checked_add(len).ok_or(RenderError::BadUtf8Text)?;
    if end > text_buffer.len() {
        return Err(RenderError::BadUtf8Text);
    }
    std::str::from_utf8(&text_buffer[start..end]).map_err(|_| RenderError::BadUtf8Text)
}

fn draw_rect_element(img: &mut image::RgbaImage, e: &FfiElement) {
    // Zero outline is the well-defined "no outline" state — short-circuit to skip the 1px clamp.
    if e.outline_thickness == 0 {
        return;
    }
    stroke_rect_rgba(
        img,
        e.x as i32,
        e.y as i32,
        e.width.max(0.0) as u32,
        e.height.max(0.0) as u32,
        e.outline_thickness.max(1),
        argb_to_rgba(e.outline_color_argb),
    );
}

fn draw_text_element(
    img: &mut image::RgbaImage,
    font: &ab_glyph::FontRef<'_>,
    e: &FfiElement,
    text_str: &str,
) {
    // Font size rides in `height`; width is unused for text. Degrees -> radians on Rust side so
    // the wire value stays in Dart's SMI range (int32 degrees vs. float64 radians).
    let params = text::TextParams {
        text: text_str,
        x: e.x as f32,
        y: e.y as f32,
        font_size_px: e.height as f32,
        rotation_rad: (e.rotation_deg as f32).to_radians(),
        color: argb_to_rgba(e.fill_color_argb),
    };
    text::render_text_overlay(img, font, &params);
}

fn argb_to_rgba(argb: u32) -> image::Rgba<u8> {
    image::Rgba([
        ((argb >> 16) & 0xFF) as u8,
        ((argb >> 8) & 0xFF) as u8,
        (argb & 0xFF) as u8,
        ((argb >> 24) & 0xFF) as u8,
    ])
}

/// Bytes-in/bytes-out path used by `export_image`. Rect coordinates are pixel-space — no
/// normalization step.
fn render_jpeg_with_rects(
    img_bytes: &[u8],
    rects: &[FfiRectElement],
    image_quality: u8,
) -> Vec<u8> {
    let mut img = image::load_from_memory(img_bytes)
        .expect("failed to decode image")
        .into_rgba8();

    for r in rects {
        stroke_rect_rgba(
            &mut img,
            r.x as i32,
            r.y as i32,
            r.width.max(0.0) as u32,
            r.height.max(0.0) as u32,
            r.outline_thickness.max(1),
            argb_to_rgba(r.outline_color_argb),
        );
    }

    let rgb_img = image::DynamicImage::ImageRgba8(img).into_rgb8();
    let mut buf = std::io::Cursor::new(Vec::new());
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, image_quality)
        .encode_image(&rgb_img)
        .unwrap();

    buf.into_inner()
}

/// Draw a hollow axis-aligned rectangle by filling the four outline bars directly into the RGBA
/// buffer. Pixel-aligned (no anti-aliasing) — good enough for screenshot annotations and keeps us
/// off a dedicated drawing crate.
fn stroke_rect_rgba(
    img: &mut image::RgbaImage,
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    stroke: u32,
    color: image::Rgba<u8>,
) {
    if w == 0 || h == 0 {
        return;
    }
    let s = stroke.min(w.min(h));
    if s == 0 {
        return;
    }
    // Top bar
    fill_rect(img, x, y, w, s, color);
    // Bottom bar
    fill_rect(img, x, y + (h - s) as i32, w, s, color);
    // Left bar
    fill_rect(img, x, y, s, h, color);
    // Right bar
    fill_rect(img, x + (w - s) as i32, y, s, h, color);
}

/// Set every pixel inside the `(x, y, w, h)` rectangle to `color`. Out-of-bounds pixels are
/// silently clipped — matches how callers use it (decoded image dims are authoritative; callers
/// don't need to pre-clamp their rects).
fn fill_rect(img: &mut image::RgbaImage, x: i32, y: i32, w: u32, h: u32, color: image::Rgba<u8>) {
    let (iw, ih) = (img.width() as i32, img.height() as i32);
    let x_start = x.max(0);
    let y_start = y.max(0);
    let x_end = (x + w as i32).min(iw);
    let y_end = (y + h as i32).min(ih);
    if x_end <= x_start || y_end <= y_start {
        return;
    }
    for py in y_start..y_end {
        for px in x_start..x_end {
            img.put_pixel(px as u32, py as u32, color);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Encode a 4×4 solid-red PNG in memory. Small enough for every test (no file I/O), big enough
    /// for rectangle-edge tests not to run out of pixels.
    fn tiny_red_png() -> Vec<u8> {
        use image::{ImageEncoder, RgbaImage};
        let img = RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 255]));
        let mut buf = std::io::Cursor::new(Vec::new());
        image::codecs::png::PngEncoder::new(&mut buf)
            .write_image(img.as_raw(), 4, 4, image::ExtendedColorType::Rgba8)
            .unwrap();
        buf.into_inner()
    }

    // --- render_jpeg_with_rects (the bytes-in / bytes-out Flutter path) ------------------------

    #[test]
    fn render_no_rects_returns_jpeg() {
        let png = tiny_red_png();
        let jpeg = render_jpeg_with_rects(&png, &[], 80);
        assert!(jpeg.len() > 2);
        assert_eq!(&jpeg[..2], &[0xFF, 0xD8], "JPEG Start-Of-Image marker");
    }

    #[test]
    fn render_with_pixel_rect_returns_jpeg() {
        let png = tiny_red_png();
        let rect = FfiRectElement {
            x: 0.0,
            y: 0.0,
            width: 4.0,
            height: 4.0,
            outline_thickness: 1,
            outline_color_argb: 0xFF00FF00, // opaque green
        };
        let jpeg = render_jpeg_with_rects(&png, &[rect], 90);
        assert!(jpeg.len() > 2);
        assert_eq!(&jpeg[..2], &[0xFF, 0xD8]);
    }

    #[test]
    fn render_with_zero_thickness_rect_skips_outline() {
        // Thickness 0 → no outline draw. Check by re-rendering with a rect that has a nonzero
        // (and bright) outline, and confirming the two JPEGs differ.
        let png = tiny_red_png();
        let no_outline = FfiRectElement {
            x: 0.0,
            y: 0.0,
            width: 4.0,
            height: 4.0,
            outline_thickness: 0,
            outline_color_argb: 0xFF00FF00,
        };
        let with_outline = FfiRectElement {
            outline_thickness: 2,
            ..no_outline
        };
        let a = render_jpeg_with_rects(&png, &[no_outline], 90);
        let b = render_jpeg_with_rects(&png, &[with_outline], 90);
        assert_ne!(a, b, "drawing an outline should change the JPEG bytes");
    }

    #[test]
    #[should_panic(expected = "failed to decode image")]
    fn render_corrupt_image_panics() {
        render_jpeg_with_rects(&[0, 1, 2, 3], &[], 80);
    }

    // --- export_image (FFI boundary — panics must not cross) ------------------------------------

    #[test]
    fn export_image_returns_null_on_corrupt_input() {
        let rects_ptr = std::ptr::NonNull::<FfiRectElement>::dangling().as_ptr();
        let buf = unsafe { export_image(b"bad".as_ptr(), 3, rects_ptr, 0, 80) };
        assert!(buf.data.is_null(), "null data signals caught panic");
        assert_eq!(buf.length, 0);
    }

    #[test]
    fn export_image_happy_path_returns_nonzero_len() {
        let png = tiny_red_png();
        let rects_ptr = std::ptr::NonNull::<FfiRectElement>::dangling().as_ptr();
        let buf = unsafe { export_image(png.as_ptr(), png.len(), rects_ptr, 0, 80) };
        assert!(!buf.data.is_null());
        assert!(buf.length > 2);
        // Clean up — otherwise we leak the Rust-allocated Vec back to the allocator.
        unsafe { free_bytes(buf.data, buf.length) };
    }

    #[test]
    fn free_bytes_tolerates_null() {
        // Rust-side defensive check: a null `ByteBuffer.data` (from a panic) should be safely
        // freeable — Dart calls free_bytes unconditionally in its try/finally.
        unsafe { free_bytes(std::ptr::null_mut(), 0) };
    }

    // --- FfiRectElement layout invariant --------------------------------------------------------

    #[test]
    fn ffi_rect_element_is_40_bytes() {
        assert_eq!(std::mem::size_of::<FfiRectElement>(), 40);
    }

    // --- argb_to_rgba ---------------------------------------------------------------------------

    #[test]
    fn argb_to_rgba_unpacks_channels_correctly() {
        // 0xAARRGGBB — alpha high, blue low. Matches Flutter's `Color` convention end-to-end.
        let rgba = argb_to_rgba(0xFF_11_22_33);
        assert_eq!(rgba.0, [0x11, 0x22, 0x33, 0xFF], "R G B A");
    }

    #[test]
    fn argb_to_rgba_preserves_transparent_sentinel() {
        assert_eq!(argb_to_rgba(0x00_00_00_00).0, [0, 0, 0, 0]);
    }

    // --- fill_rect + stroke_rect_rgba clipping --------------------------------------------------

    #[test]
    fn fill_rect_clips_to_image_bounds() {
        let mut img = image::RgbaImage::from_pixel(4, 4, image::Rgba([0, 0, 0, 255]));
        fill_rect(&mut img, -10, -10, 3, 3, image::Rgba([255, 0, 0, 255]));
        // All pixels should still be black — the rectangle is entirely off-screen.
        assert!(img.pixels().all(|p| p.0 == [0, 0, 0, 255]));
    }

    #[test]
    fn fill_rect_clips_partial_overlap() {
        let mut img = image::RgbaImage::from_pixel(4, 4, image::Rgba([0, 0, 0, 255]));
        // (-2, -2, 4, 4) covers only the top-left 2×2 of the image.
        fill_rect(&mut img, -2, -2, 4, 4, image::Rgba([255, 0, 0, 255]));
        // Pixels that should be red.
        for y in 0..2 {
            for x in 0..2 {
                assert_eq!(img.get_pixel(x, y).0, [255, 0, 0, 255]);
            }
        }
        // Pixels that should still be black.
        for y in 0..4 {
            for x in 0..4 {
                if x >= 2 || y >= 2 {
                    assert_eq!(img.get_pixel(x, y).0, [0, 0, 0, 255]);
                }
            }
        }
    }

    #[test]
    fn fill_rect_is_noop_for_zero_size() {
        let mut img = image::RgbaImage::from_pixel(4, 4, image::Rgba([0, 0, 0, 255]));
        fill_rect(&mut img, 0, 0, 0, 0, image::Rgba([255, 0, 0, 255]));
        assert!(img.pixels().all(|p| p.0 == [0, 0, 0, 255]));
    }

    #[test]
    fn stroke_rect_rgba_clamps_thickness_to_shortest_side() {
        let mut img = image::RgbaImage::from_pixel(4, 4, image::Rgba([0, 0, 0, 255]));
        // Stroke of 10 on a 4x4 rect: clamp to 4 (the shortest side), so everything inside is red.
        stroke_rect_rgba(&mut img, 0, 0, 4, 4, 10, image::Rgba([255, 0, 0, 255]));
        assert!(img.pixels().all(|p| p.0 == [255, 0, 0, 255]));
    }

    #[test]
    fn stroke_rect_rgba_with_zero_thickness_is_noop() {
        let mut img = image::RgbaImage::from_pixel(4, 4, image::Rgba([0, 0, 0, 255]));
        stroke_rect_rgba(&mut img, 0, 0, 4, 4, 0, image::Rgba([255, 0, 0, 255]));
        assert!(img.pixels().all(|p| p.0 == [0, 0, 0, 255]));
    }

    #[test]
    fn stroke_rect_rgba_with_zero_size_is_noop() {
        let mut img = image::RgbaImage::from_pixel(4, 4, image::Rgba([0, 0, 0, 255]));
        stroke_rect_rgba(&mut img, 0, 0, 0, 0, 1, image::Rgba([255, 0, 0, 255]));
        assert!(img.pixels().all(|p| p.0 == [0, 0, 0, 255]));
    }

    #[test]
    fn stroke_rect_rgba_draws_outline_only_interior_unchanged() {
        let mut img = image::RgbaImage::from_pixel(5, 5, image::Rgba([0, 0, 0, 255]));
        stroke_rect_rgba(&mut img, 0, 0, 5, 5, 1, image::Rgba([255, 0, 0, 255]));
        // Corners + edges should be red, centre (2, 2) untouched.
        assert_eq!(img.get_pixel(0, 0).0, [255, 0, 0, 255]);
        assert_eq!(img.get_pixel(4, 4).0, [255, 0, 0, 255]);
        assert_eq!(img.get_pixel(2, 2).0, [0, 0, 0, 255], "interior of a 1px stroke is untouched");
    }

    // --- element_text helper (bounds + UTF-8) --------------------------------------------------

    #[test]
    fn element_text_returns_slice_when_range_valid() {
        let buf = b"hello";
        let mut el = make_rect_element();
        el.text_offset = 1;
        el.text_length = 3;
        let slice = element_text(&el, buf).unwrap();
        assert_eq!(slice, "ell");
    }

    #[test]
    fn element_text_rejects_out_of_bounds_range() {
        let buf = b"hi";
        let mut el = make_rect_element();
        el.text_offset = 0;
        el.text_length = 99;
        assert!(matches!(element_text(&el, buf), Err(RenderError::BadUtf8Text)));
    }

    #[test]
    fn element_text_rejects_offset_overflow() {
        let buf = b"hi";
        let mut el = make_rect_element();
        el.text_offset = u32::MAX;
        el.text_length = 1;
        assert!(matches!(element_text(&el, buf), Err(RenderError::BadUtf8Text)));
    }

    #[test]
    fn element_text_rejects_invalid_utf8() {
        // 0xFF on its own is not a valid UTF-8 start byte.
        let buf: &[u8] = &[0xFF];
        let mut el = make_rect_element();
        el.text_offset = 0;
        el.text_length = 1;
        assert!(matches!(element_text(&el, buf), Err(RenderError::BadUtf8Text)));
    }

    fn make_rect_element() -> FfiElement {
        FfiElement {
            element_type: element_type::RECTANGLE,
            x: 0.0,
            y: 0.0,
            width: 0.0,
            height: 0.0,
            rotation_deg: 0,
            fill_color_argb: 0,
            outline_color_argb: 0,
            outline_thickness: 0,
            blur: 0,
            text_offset: 0,
            text_length: 0,
        }
    }
}
