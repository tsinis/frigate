use std::ffi::{CStr, c_char};
use std::path::Path;
use std::slice;

use tiny_skia::{Paint, PathBuilder, Pixmap, Rect, Stroke, Transform};

pub mod canvas;
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
    /// Corner radius in pixels (0 = sharp corners). Clamped to `min(width, height) / 2` at
    /// render time. Mirrors `FfiElement.shape_param` for the slim export struct.
    pub shape_param: u32,
}

// 4 × f64 (32) + 3 × u32 (12) = 44 bytes content; alignment 8 → padded to 48 bytes total.
const _: () = assert!(std::mem::size_of::<FfiRectElement>() == 48);

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
    // `slice::from_raw_parts` requires a non-null, properly aligned pointer even when `len == 0`
    // (Rust reference: "data must be non-null and aligned even for zero-length slices"). Handle
    // the empty case explicitly so a null/dangling `rects_ptr` with `rects_count == 0` is UB-free.
    let rects: &[FfiRectElement] = if rects_count == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(rects_ptr, rects_count) }
    };
    // catch_unwind: panicking across an FFI boundary is undefined behavior.
    let result =
        std::panic::catch_unwind(|| render_jpeg_with_rects(img_bytes, rects, image_quality));
    match result {
        Ok(bytes) => {
            // into_boxed_slice shrinks capacity to == len, so free_bytes can reconstruct the Vec
            // safely with Vec::from_raw_parts(ptr, len, len).
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
            io::IoError::Write | io::IoError::Encode | io::IoError::UnsupportedFormat => {
                Self::ImageWrite
            }
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
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|_| RenderError::BadUtf8Path)
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
    let needs_font = elements
        .iter()
        .any(|e| e.element_type == element_type::TEXT);
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

    let img = io::read_image(Path::new(image_path))?.into_rgba8();
    let mut surface = Surface::Rgba(img);

    for element in elements {
        match element.element_type {
            element_type::RECTANGLE => {
                let style: RectStyle = element.into();
                if !style.paints_anything() {
                    continue;
                }
                draw_rect_on_pixmap(
                    surface.as_pixmap(),
                    element.x,
                    element.y,
                    element.width,
                    element.height,
                    &style,
                );
            }
            element_type::TEXT => {
                let text_slice = element_text(element, text_buffer)?;
                if let Some(font_ref) = &font {
                    draw_text_element(surface.as_rgba(), font_ref, element, text_slice);
                }
            }
            // Unknown element types are skipped silently — forward-compat for adding shapes
            // without breaking older Rust binaries that haven't shipped the new dispatch.
            _ => {}
        }
    }

    let img = surface.into_rgba();
    io::write_image(Path::new(output_path), &img, image_quality)
        .map_err(|_| RenderError::ImageWrite)?;
    Ok(())
}

fn element_text<'b>(element: &FfiElement, text_buffer: &'b [u8]) -> Result<&'b str, RenderError> {
    let start = element.text_offset as usize;
    let len = element.text_length as usize;
    let end = start.checked_add(len).ok_or(RenderError::BadUtf8Text)?;
    if end > text_buffer.len() {
        return Err(RenderError::BadUtf8Text);
    }
    std::str::from_utf8(&text_buffer[start..end]).map_err(|_| RenderError::BadUtf8Text)
}

pub fn draw_rect_element(img: &mut image::RgbaImage, e: &FfiElement) {
    let style: RectStyle = e.into();
    // Skip the conversion round-trip when neither fill nor stroke would paint visible pixels.
    if !style.paints_anything() {
        return;
    }
    let mut pixmap = canvas::to_pixmap(img);
    draw_rect_on_pixmap(&mut pixmap, e.x, e.y, e.width, e.height, &style);
    *img = canvas::from_pixmap(&pixmap);
}

/// Drawing surface that lazily converts between `RgbaImage` (text-friendly) and
/// `Pixmap` (rect-friendly), so a long run of same-type elements pays one conversion total
/// instead of one per element. Element order is preserved exactly — transitions between
/// rect and text are the only conversion points.
enum Surface {
    Rgba(image::RgbaImage),
    Pixmap(Pixmap),
}

impl Surface {
    fn as_rgba(&mut self) -> &mut image::RgbaImage {
        if let Self::Pixmap(p) = self {
            *self = Self::Rgba(canvas::from_pixmap(p));
        }
        match self {
            Self::Rgba(img) => img,
            Self::Pixmap(_) => unreachable!("just converted above"),
        }
    }

    fn as_pixmap(&mut self) -> &mut Pixmap {
        if let Self::Rgba(img) = self {
            *self = Self::Pixmap(canvas::to_pixmap(img));
        }
        match self {
            Self::Pixmap(p) => p,
            Self::Rgba(_) => unreachable!("just converted above"),
        }
    }

    fn into_rgba(self) -> image::RgbaImage {
        match self {
            Self::Rgba(img) => img,
            Self::Pixmap(p) => canvas::from_pixmap(&p),
        }
    }
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

/// Single source of truth for `0xAARRGGBB` -> `[R, G, B, A]` byte unpacking. `argb_to_rgba`
/// and `argb_to_tiny_color` both wrap this so a future packed-color format change touches
/// one place.
#[inline]
fn argb_unpack(argb: u32) -> [u8; 4] {
    [
        ((argb >> 16) & 0xFF) as u8,
        ((argb >> 8) & 0xFF) as u8,
        (argb & 0xFF) as u8,
        ((argb >> 24) & 0xFF) as u8,
    ]
}

fn argb_to_rgba(argb: u32) -> image::Rgba<u8> {
    image::Rgba(argb_unpack(argb))
}

/// Bytes-in/bytes-out path used by `export_image`. Rect coordinates are pixel-space — no
/// normalization step.
fn render_jpeg_with_rects(
    img_bytes: &[u8],
    rects: &[FfiRectElement],
    image_quality: u8,
) -> Vec<u8> {
    let img = image::load_from_memory(img_bytes)
        .expect("failed to decode image")
        .into_rgba8();

    // One conversion pair per export, regardless of rect count — much cheaper than the
    // per-rect round-trip in `draw_rect_element`.
    let mut pixmap = canvas::to_pixmap(&img);
    for r in rects {
        draw_rect_on_pixmap(&mut pixmap, r.x, r.y, r.width, r.height, &r.into());
    }
    let img = canvas::from_pixmap(&pixmap);

    let rgb_img = image::DynamicImage::ImageRgba8(img).into_rgb8();
    let mut buf = std::io::Cursor::new(Vec::new());
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, image_quality)
        .encode_image(&rgb_img)
        .unwrap();

    buf.into_inner()
}

/// Visual style for a single rectangle. Pulled out of `draw_rect_on_pixmap`'s argument list
/// so the signature stays readable as we add more shape parameters.
pub struct RectStyle {
    pub outline_thickness: u32,
    pub outline_color_argb: u32,
    pub fill_color_argb: u32,
    /// Corner radius in pixels. 0 = sharp corners (axis-aligned rect). Auto-clamped to
    /// `min(width, height) / 2` at render time so the path always remains valid.
    pub corner_radius_px: u32,
}

impl RectStyle {
    /// `true` when at least one of fill or stroke would deposit visible pixels. Used by
    /// callers to skip the to_pixmap conversion entirely for "invisible" rects (zero-alpha
    /// fill + zero thickness or zero-alpha outline) — the conversion round-trip is O(pixels).
    pub fn paints_anything(&self) -> bool {
        let has_outline = self.outline_thickness > 0 && argb_alpha(self.outline_color_argb) > 0;
        let has_fill = argb_alpha(self.fill_color_argb) > 0;
        has_outline || has_fill
    }
}

impl From<&FfiElement> for RectStyle {
    fn from(e: &FfiElement) -> Self {
        Self {
            outline_thickness: e.outline_thickness,
            outline_color_argb: e.outline_color_argb,
            fill_color_argb: e.fill_color_argb,
            corner_radius_px: e.shape_param,
        }
    }
}

impl From<&FfiRectElement> for RectStyle {
    /// The slim export struct carries no fill — it's outline-only by contract.
    fn from(r: &FfiRectElement) -> Self {
        Self {
            outline_thickness: r.outline_thickness,
            outline_color_argb: r.outline_color_argb,
            fill_color_argb: 0,
            corner_radius_px: r.shape_param,
        }
    }
}

/// Fill (if `fill_color_argb` alpha > 0) and/or stroke an axis-aligned rectangle onto `pixmap`
/// using `tiny-skia`'s path renderer.
///
/// Visual contract:
/// - Fill is painted only when `argb_alpha(fill_color_argb) > 0` — fully transparent
///   (`0x00_RR_GG_BB`) means "no fill", matching how Dart's defaults express "outline-only".
/// - Stroke is painted only when `outline_thickness > 0` AND
///   `argb_alpha(outline_color_argb) > 0`.
/// - Stroke width is clamped to `min(width, height)` so giant thickness values from Dart
///   (up to `u32::MAX`) can never blow up tiny-skia's stroked-path geometry.
/// - `width <= 0`, `height <= 0`, or any non-finite coordinate → no draw.
/// - Fill is drawn before stroke, so the stroke sits on top of the fill (Flutter convention).
/// - **Anti-aliasing is on only for rounded corners.** Sharp-corner rectangles render with
///   pixel-aligned edges (no half-pixel bleed into neighboring pixels); rounded corners
///   require AA to look smooth on the curves. This matches what Flutter does when its `Paint`
///   `isAntiAlias` is left at the default for axis-aligned `drawRect` vs `drawRRect`.
fn draw_rect_on_pixmap(
    pixmap: &mut Pixmap,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    style: &RectStyle,
) {
    if width <= 0.0 || height <= 0.0 {
        return;
    }
    // Cast through f32 carefully: any non-finite or sign-flipped value collapses to None below.
    let Some(rect) = Rect::from_xywh(x as f32, y as f32, width as f32, height as f32) else {
        return;
    };
    let path = build_rect_path(rect, style.corner_radius_px);
    let anti_alias = style.corner_radius_px > 0;

    // Fill first, stroke on top — matches Flutter's draw order so preview and export agree.
    if argb_alpha(style.fill_color_argb) > 0 {
        let mut paint = Paint::default();
        paint.set_color(argb_to_tiny_color(style.fill_color_argb));
        paint.anti_alias = anti_alias;
        pixmap.fill_path(
            &path,
            &paint,
            tiny_skia::FillRule::Winding,
            Transform::identity(),
            None,
        );
    }

    if style.outline_thickness > 0 && argb_alpha(style.outline_color_argb) > 0 {
        // Clamp stroke width to the rect's shortest side. Two reasons:
        //   1. Preserves the legacy "huge thickness fills the rect" semantics so callers
        //      porting from the old renderer don't suddenly see strokes ballooning past the
        //      rect bounds.
        //   2. Bounds the work tiny-skia does building stroked geometry — `u32::MAX`
        //      thickness from Dart can't trigger pathological allocations.
        let max_stroke = rect.width().min(rect.height());
        let stroke_width = (style.outline_thickness as f32).min(max_stroke);
        if stroke_width > 0.0 {
            let mut paint = Paint::default();
            paint.set_color(argb_to_tiny_color(style.outline_color_argb));
            paint.anti_alias = anti_alias;
            let stroke = Stroke {
                width: stroke_width,
                ..Stroke::default()
            };
            pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
        }
    }
}

/// Build a (rounded) rectangle path. `corner_radius_px == 0` short-circuits to the cheap
/// 4-line axis-aligned path; otherwise we trace 4 corner arcs + 4 straight edges.
///
/// The radius is clamped to `min(width, height) / 2` so the rounded rect can never collapse
/// into invalid geometry: at the clamp ceiling the corners exactly meet and the shape is a
/// pill (or a circle if `width == height`).
fn build_rect_path(rect: Rect, corner_radius_px: u32) -> tiny_skia::Path {
    if corner_radius_px == 0 {
        return PathBuilder::from_rect(rect);
    }
    let max_r = rect.width().min(rect.height()) * 0.5;
    let r = (corner_radius_px as f32).min(max_r);
    if r <= 0.0 {
        return PathBuilder::from_rect(rect);
    }
    // Cubic bezier control-point distance for approximating a quarter-circle. Standard "magic
    // number" — error vs a true circle is below 1e-3 of the radius, far under one pixel for
    // any sane radius.
    const KAPPA: f32 = 0.552_284_8;
    let c = r * KAPPA;

    let l = rect.left();
    let t = rect.top();
    let ri = rect.right();
    let b = rect.bottom();

    let mut pb = PathBuilder::new();
    // Start at the top-left corner's right edge (clockwise traversal).
    pb.move_to(l + r, t);
    // Top edge → top-right arc.
    pb.line_to(ri - r, t);
    pb.cubic_to(ri - r + c, t, ri, t + r - c, ri, t + r);
    // Right edge → bottom-right arc.
    pb.line_to(ri, b - r);
    pb.cubic_to(ri, b - r + c, ri - r + c, b, ri - r, b);
    // Bottom edge → bottom-left arc.
    pb.line_to(l + r, b);
    pb.cubic_to(l + r - c, b, l, b - r + c, l, b - r);
    // Left edge → top-left arc.
    pb.line_to(l, t + r);
    pb.cubic_to(l, t + r - c, l + r - c, t, l + r, t);
    pb.close();
    pb.finish()
        .expect("rounded-rect path is well-formed by construction")
}

fn argb_to_tiny_color(argb: u32) -> tiny_skia::Color {
    let [r, g, b, a] = argb_unpack(argb);
    tiny_skia::Color::from_rgba8(r, g, b, a)
}

#[inline]
fn argb_alpha(argb: u32) -> u8 {
    argb_unpack(argb)[3]
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
            shape_param: 0,
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
            shape_param: 0,
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

    // --- Audit: extreme inputs across the FFI boundary -----------------------------
    // These tests document/guard against silent panics for inputs Dart trusts (or can mistakenly
    // forward) without explicit validation. Every case must complete without crossing the FFI
    // panic boundary; null ByteBuffer return is acceptable, panic is not.

    #[test]
    fn export_image_handles_quality_zero_without_panic() {
        // Dart clamps to [0, 100], so quality=0 is a legal in-range value. The image-crate JPEG
        // encoder must accept it; if it ever changes to require quality >= 1, this test catches
        // the regression at the FFI boundary instead of in production.
        let png = tiny_red_png();
        let rects_ptr = std::ptr::NonNull::<FfiRectElement>::dangling().as_ptr();
        let buf = unsafe { export_image(png.as_ptr(), png.len(), rects_ptr, 0, 0) };
        assert!(
            !buf.data.is_null(),
            "quality=0 must produce a valid JPEG, not a caught panic"
        );
        assert!(buf.length > 2);
        unsafe { free_bytes(buf.data, buf.length) };
    }

    #[test]
    fn export_image_handles_quality_above_100_without_panic() {
        // The wire type is `u8` (max 255). Dart clamps before sending, but a direct-FFI caller
        // (or future bypass) could pass anything in 0..=255. Must not panic across the boundary.
        let png = tiny_red_png();
        let rects_ptr = std::ptr::NonNull::<FfiRectElement>::dangling().as_ptr();
        let buf = unsafe { export_image(png.as_ptr(), png.len(), rects_ptr, 0, 255) };
        assert!(
            !buf.data.is_null(),
            "quality=255 must be tolerated, not crash"
        );
        assert!(buf.length > 2);
        unsafe { free_bytes(buf.data, buf.length) };
    }

    #[test]
    fn export_image_handles_nan_inf_rect_coords_without_panic() {
        // Dart `double` can be NaN/+Inf/-Inf. f64 → f32 cast preserves these. `Rect::from_xywh`
        // rejects them, so `draw_rect_on_pixmap` short-circuits without touching the pixmap —
        // and the rest of the pipeline runs to completion.
        let png = tiny_red_png();
        let rects = [
            FfiRectElement {
                x: f64::NAN,
                y: 0.0,
                width: 4.0,
                height: 4.0,
                outline_thickness: 1,
                outline_color_argb: 0xFF_FF_00_00,
                shape_param: 0,
            },
            FfiRectElement {
                x: 0.0,
                y: f64::INFINITY,
                width: 4.0,
                height: 4.0,
                outline_thickness: 1,
                outline_color_argb: 0xFF_00_FF_00,
                shape_param: 0,
            },
            FfiRectElement {
                x: 0.0,
                y: 0.0,
                width: f64::NEG_INFINITY,
                height: 4.0,
                outline_thickness: 1,
                outline_color_argb: 0xFF_00_00_FF,
                shape_param: 0,
            },
        ];
        let buf = unsafe { export_image(png.as_ptr(), png.len(), rects.as_ptr(), rects.len(), 80) };
        assert!(
            !buf.data.is_null(),
            "non-finite coords must be silently dropped, not crash"
        );
        unsafe { free_bytes(buf.data, buf.length) };
    }

    #[test]
    fn rounded_rect_at_clamp_ceiling_circle_case_does_not_panic() {
        // Square rect with radius == width/2 — the clamp ceiling. Path geometry has 4 zero-
        // length edges between full quarter arcs (the inscribed circle). tiny-skia must accept
        // this degenerate-edge path; if `pb.finish()` ever returns None for it, the
        // `.expect("rounded-rect path is well-formed by construction")` panics.
        let mut pixmap = opaque_black_pixmap(20, 20);
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            0.0,
            20.0,
            20.0,
            &RectStyle {
                outline_thickness: 2,
                outline_color_argb: 0xFF_FF_FF_FF,
                fill_color_argb: 0xFF_FF_00_00,
                corner_radius_px: 10, // == width/2 == height/2 → exact circle
            },
        );
        // Center pixel must be inside the inscribed circle and therefore filled.
        let center = (10 * 20 + 10) * 4;
        assert_eq!(
            pixmap.data()[center],
            255,
            "center of inscribed circle must be filled red"
        );
    }

    #[test]
    fn rounded_rect_with_non_square_clamp_pill_case_does_not_panic() {
        // 60×20 rect with radius >> max_r (10). Clamp produces a pill (semi-circular ends).
        // Edge cases: top/bottom edges are non-degenerate (60 - 2*10 = 40 long); left/right
        // edges have zero length (20 - 2*10 = 0). Path must still finalize cleanly.
        let mut pixmap = opaque_black_pixmap(60, 20);
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            0.0,
            60.0,
            20.0,
            &RectStyle {
                outline_thickness: 1,
                outline_color_argb: 0xFF_FF_FF_FF,
                fill_color_argb: 0xFF_00_FF_00,
                corner_radius_px: 99_999,
            },
        );
        // Centerline must be solid green inside the pill body.
        let center = (10 * 60 + 30) * 4;
        assert_eq!(
            pixmap.data()[center + 1],
            255,
            "pill interior centerline must be filled green"
        );
    }

    #[test]
    fn export_image_with_max_u32_corner_radius_clamps_safely() {
        // Dart-side assertion blocks negative cornerRadius (which would marshal to u32::MAX-ish
        // via `Uint32` 2's-complement wrapping), but a direct-FFI caller could still pass it.
        // Rust must clamp to `min(w, h) / 2` and render a pill without panicking.
        let png = tiny_red_png();
        let rect = FfiRectElement {
            x: 0.0,
            y: 0.0,
            width: 4.0,
            height: 4.0,
            outline_thickness: 0,
            outline_color_argb: 0,
            shape_param: u32::MAX,
        };
        let buf = unsafe { export_image(png.as_ptr(), png.len(), &rect, 1, 80) };
        assert!(
            !buf.data.is_null(),
            "u32::MAX corner radius must clamp safely, not panic"
        );
        unsafe { free_bytes(buf.data, buf.length) };
    }

    #[test]
    fn one_pixel_image_does_not_panic_through_to_pixmap() {
        use image::ImageEncoder;
        // 1×1 PNG is the smallest non-zero image. canvas::to_pixmap requires non-zero dims;
        // 1×1 must be accepted.
        let img = image::RgbaImage::from_pixel(1, 1, image::Rgba([255, 0, 0, 255]));
        let mut buf = std::io::Cursor::new(Vec::new());
        image::codecs::png::PngEncoder::new(&mut buf)
            .write_image(img.as_raw(), 1, 1, image::ExtendedColorType::Rgba8)
            .unwrap();
        let png = buf.into_inner();
        let rects_ptr = std::ptr::NonNull::<FfiRectElement>::dangling().as_ptr();
        let result = unsafe { export_image(png.as_ptr(), png.len(), rects_ptr, 0, 80) };
        assert!(
            !result.data.is_null(),
            "1×1 image should round-trip without panic"
        );
        unsafe { free_bytes(result.data, result.length) };
    }

    // --- FfiRectElement layout invariant --------------------------------------------------------

    #[test]
    fn ffi_rect_element_is_48_bytes() {
        // 4 × f64 (32) + 3 × u32 (12) = 44 content; padded to 48 for 8-byte alignment.
        assert_eq!(std::mem::size_of::<FfiRectElement>(), 48);
    }

    #[test]
    fn ffi_rect_element_shape_param_round_trip() {
        // Verify the field actually round-trips through a struct literal — catches accidental
        // field reordering on the Rust side.
        let r = FfiRectElement {
            x: 1.0,
            y: 2.0,
            width: 3.0,
            height: 4.0,
            outline_thickness: 5,
            outline_color_argb: 0xFF112233,
            shape_param: 7,
        };
        assert_eq!(r.shape_param, 7);
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

    // --- draw_rect_on_pixmap (tiny-skia path) ---------------------------------------------------

    fn opaque_black_pixmap(w: u32, h: u32) -> Pixmap {
        let img = image::RgbaImage::from_pixel(w, h, image::Rgba([0, 0, 0, 255]));
        canvas::to_pixmap(&img)
    }

    fn assert_pixmap_unchanged(pixmap: &Pixmap, baseline: &Pixmap, reason: &str) {
        assert_eq!(pixmap.data(), baseline.data(), "{reason}");
    }

    /// Test-only constructor that mirrors the old `(thickness, outline, fill)` positional
    /// args so the existing test bodies stay readable. Sharp-corner shorthand.
    fn style(outline_thickness: u32, outline_color_argb: u32, fill_color_argb: u32) -> RectStyle {
        RectStyle {
            outline_thickness,
            outline_color_argb,
            fill_color_argb,
            corner_radius_px: 0,
        }
    }

    // --- RectStyle::paints_anything (the visibility short-circuit) ----------------------------

    #[test]
    fn paints_anything_is_false_for_zero_alpha_fill_and_zero_thickness() {
        // The "totally invisible rect" — every alpha channel is zero, no stroke band.
        assert!(!style(0, 0x00_FF_FF_FF, 0x00_FF_FF_FF).paints_anything());
    }

    #[test]
    fn paints_anything_is_false_for_zero_alpha_outline_with_no_fill() {
        // Stroke thickness > 0 alone is not enough — outline alpha must also be > 0.
        assert!(!style(5, 0x00_FF_00_00, 0).paints_anything());
    }

    #[test]
    fn paints_anything_is_true_for_visible_outline_only() {
        assert!(style(1, 0xFF_00_FF_00, 0).paints_anything());
    }

    #[test]
    fn paints_anything_is_true_for_fill_only_with_zero_thickness() {
        assert!(style(0, 0, 0xFF_FF_00_00).paints_anything());
    }

    #[test]
    fn paints_anything_is_true_for_translucent_fill() {
        // Even alpha=1 counts as "would paint something".
        assert!(style(0, 0, 0x01_FF_00_00).paints_anything());
    }

    #[test]
    fn draw_rect_on_pixmap_zero_thickness_is_noop() {
        let baseline = opaque_black_pixmap(8, 8);
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(&mut pixmap, 1.0, 1.0, 4.0, 4.0, &style(0, 0xFFFF0000, 0));
        assert_pixmap_unchanged(&pixmap, &baseline, "thickness=0 must not draw");
    }

    #[test]
    fn draw_rect_on_pixmap_zero_size_is_noop() {
        let baseline = opaque_black_pixmap(8, 8);
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(&mut pixmap, 0.0, 0.0, 0.0, 0.0, &style(1, 0xFFFF0000, 0));
        assert_pixmap_unchanged(&pixmap, &baseline, "0×0 rect must not draw");
    }

    #[test]
    fn draw_rect_on_pixmap_negative_size_is_noop() {
        let baseline = opaque_black_pixmap(8, 8);
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(&mut pixmap, 0.0, 0.0, -5.0, -5.0, &style(1, 0xFFFF0000, 0));
        assert_pixmap_unchanged(&pixmap, &baseline, "negative dims short-circuit");
    }

    #[test]
    fn draw_rect_on_pixmap_nonfinite_coords_are_noop() {
        // FFI exposes `x`/`y`/`width`/`height` as f64 — Dart doubles. NaN/Inf must not panic.
        let baseline = opaque_black_pixmap(8, 8);
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(
            &mut pixmap,
            f64::NAN,
            0.0,
            4.0,
            4.0,
            &style(1, 0xFFFF0000, 0),
        );
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            f64::INFINITY,
            4.0,
            4.0,
            &style(1, 0xFFFF0000, 0),
        );
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            0.0,
            f64::NAN,
            4.0,
            &style(1, 0xFFFF0000, 0),
        );
        assert_pixmap_unchanged(&pixmap, &baseline, "non-finite coords must not draw");
    }

    #[test]
    fn draw_rect_on_pixmap_offscreen_is_noop() {
        let baseline = opaque_black_pixmap(8, 8);
        let mut pixmap = opaque_black_pixmap(8, 8);
        // Far off the right/bottom edge — fully outside the pixmap, must paint nothing.
        draw_rect_on_pixmap(
            &mut pixmap,
            100.0,
            100.0,
            4.0,
            4.0,
            &style(1, 0xFFFF0000, 0),
        );
        assert_pixmap_unchanged(
            &pixmap,
            &baseline,
            "fully off-screen must not affect pixels",
        );
    }

    #[test]
    fn draw_rect_on_pixmap_actually_draws() {
        // Sanity check: a normal rect leaves *some* changes. Don't assert pixel positions
        // (AA + sub-pixel positioning makes that brittle); just confirm the renderer ran.
        let baseline = opaque_black_pixmap(16, 16);
        let mut pixmap = opaque_black_pixmap(16, 16);
        draw_rect_on_pixmap(&mut pixmap, 4.0, 4.0, 8.0, 8.0, &style(2, 0xFFFF0000, 0));
        assert_ne!(
            pixmap.data(),
            baseline.data(),
            "a visible rect must change at least one pixel"
        );
        // Some red channel must show up somewhere — covers the ARGB unpacking too.
        let any_red = pixmap.data().chunks_exact(4).any(|px| px[0] > 0);
        assert!(any_red, "outline color must reach the buffer (R channel)");
    }

    #[test]
    fn draw_rect_on_pixmap_handles_u32_max_thickness_without_panic() {
        // The clamp to min(width, height) is what protects tiny-skia's path stroker from
        // building absurdly large geometry. Without the clamp, a u32::MAX from Dart could
        // OOM or take seconds — with the clamp this completes instantly.
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            0.0,
            8.0,
            8.0,
            &style(u32::MAX, 0xFF00FF00, 0),
        );
        // Just survival — no panic, no hang. Some green should land somewhere.
        let any_green = pixmap.data().chunks_exact(4).any(|px| px[1] > 0);
        assert!(any_green, "clamped giant stroke should still paint");
    }

    #[test]
    fn draw_rect_on_pixmap_handles_huge_floating_dimensions_without_panic() {
        // Dart can pass any f64. Values past f32::MAX or near it must not crash tiny-skia.
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(&mut pixmap, 0.0, 0.0, 1e15, 1e15, &style(1, 0xFFFF0000, 0));
    }

    #[test]
    fn draw_rect_on_pixmap_transparent_fill_does_not_paint_interior() {
        // Dart sends 0x00_RR_GG_BB (alpha = 0) when "no fill" is intended. The interior of
        // the rect must remain unchanged in that case — even if the RGB bits look colorful.
        let mut pixmap = opaque_black_pixmap(16, 16);
        draw_rect_on_pixmap(
            &mut pixmap,
            4.0,
            4.0,
            8.0,
            8.0,
            // outline alpha=0, fill RGB looks red but alpha=0 means "no fill"
            &style(0, 0, 0x00_FF_00_00),
        );
        // Center pixel (8, 8) is well inside the rect — must still be black.
        let off = (8 * 16 + 8) * 4;
        assert_eq!(
            &pixmap.data()[off..off + 4],
            &[0, 0, 0, 255],
            "alpha=0 fill must not deposit color even though RGB bits are nonzero"
        );
    }

    #[test]
    fn draw_rect_on_pixmap_opaque_fill_paints_interior() {
        let mut pixmap = opaque_black_pixmap(16, 16);
        draw_rect_on_pixmap(&mut pixmap, 4.0, 4.0, 8.0, 8.0, &style(0, 0, 0xFF_00_FF_00));
        // Well inside the rect — should be solid green (no AA edge effects this far in).
        let off = (8 * 16 + 8) * 4;
        let px = &pixmap.data()[off..off + 4];
        assert_eq!(px, &[0, 255, 0, 255], "opaque fill paints interior solid");
    }

    #[test]
    fn draw_rect_on_pixmap_fill_only_with_zero_thickness_still_works() {
        // Without the `has_outline || has_fill` short-circuit in `draw_rect_element`, a
        // fill-only call with thickness=0 used to be eaten by the early return. Verify the
        // helper itself paints fill regardless of thickness.
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(&mut pixmap, 0.0, 0.0, 8.0, 8.0, &style(0, 0, 0xFF_00_00_FF));
        let any_blue = pixmap.data().chunks_exact(4).any(|p| p[2] > 0);
        assert!(any_blue, "fill-only call (thickness=0) must still paint");
    }

    #[test]
    fn draw_rect_on_pixmap_translucent_fill_blends_over_background() {
        // Premultiplied src-over compositing of 50% red onto opaque black:
        //   src (premul) = (128, 0, 0, 128)
        //   dst          = (0, 0, 0, 255)
        //   out.r = src.r + dst.r * (1 - src.a/255) = 128
        //   out.a = src.a + dst.a * (1 - src.a/255) = 128 + 255 * 127/255 = 255
        // So R lands ~128 and A stays at 255 (background was already opaque).
        let mut pixmap = opaque_black_pixmap(16, 16);
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            0.0,
            16.0,
            16.0,
            &style(0, 0, 0x80_FF_00_00),
        );
        let off = (8 * 16 + 8) * 4;
        let px = &pixmap.data()[off..off + 4];
        assert!(
            (110..=145).contains(&px[0]),
            "R should be ~128 from src-over blend, got {}",
            px[0]
        );
        assert_eq!(
            px[3], 255,
            "alpha onto opaque background stays 255, got {}",
            px[3]
        );
    }

    #[test]
    fn draw_rect_on_pixmap_stroke_renders_on_top_of_fill() {
        // Order matters when fill and stroke colors differ. tiny-skia's stroke is centered
        // on the path edge — at the rect's edge the stroke color must dominate the fill.
        let mut pixmap = opaque_black_pixmap(16, 16);
        draw_rect_on_pixmap(
            &mut pixmap,
            2.0,
            2.0,
            12.0,
            12.0,
            // blue stroke, red fill
            &style(2, 0xFF_00_00_FF, 0xFF_FF_00_00),
        );
        // Inside the fill region (away from the stroked edge) → red dominates.
        let inside_off = (8 * 16 + 8) * 4;
        let inside = &pixmap.data()[inside_off..inside_off + 4];
        assert_eq!(inside[0], 255, "interior is the fill color (red)");
        assert_eq!(inside[2], 0, "interior has no blue from the stroke");
        // On the rect's top edge → blue stroke should be visible.
        let edge_off = (2 * 16 + 8) * 4;
        let edge = &pixmap.data()[edge_off..edge_off + 4];
        assert!(
            edge[2] > 0,
            "stroke at the rect edge must contribute blue, got {edge:?}"
        );
    }

    // --- rounded corners --------------------------------------------------------------------

    #[test]
    fn build_rect_path_zero_radius_is_axis_aligned_rect() {
        // A radius of 0 must produce identical geometry to the legacy rect path. We can't
        // directly diff Path objects, so render both and compare pixmaps.
        let rect = Rect::from_xywh(2.0, 2.0, 12.0, 12.0).unwrap();
        let mut a = opaque_black_pixmap(16, 16);
        let mut b = opaque_black_pixmap(16, 16);
        let mut paint = Paint::default();
        paint.set_color(tiny_skia::Color::from_rgba8(255, 0, 0, 255));
        paint.anti_alias = true;
        a.fill_path(
            &PathBuilder::from_rect(rect),
            &paint,
            tiny_skia::FillRule::Winding,
            Transform::identity(),
            None,
        );
        b.fill_path(
            &build_rect_path(rect, 0),
            &paint,
            tiny_skia::FillRule::Winding,
            Transform::identity(),
            None,
        );
        assert_eq!(
            a.data(),
            b.data(),
            "radius=0 must match the sharp-corner path exactly"
        );
    }

    #[test]
    fn rounded_rect_clears_corner_pixels() {
        // With a meaningful corner radius, the literal corner pixel of the bounding rect must
        // NOT be painted by the fill — that's the whole point of rounded corners.
        let mut sharp = opaque_black_pixmap(32, 32);
        let mut rounded = opaque_black_pixmap(32, 32);
        draw_rect_on_pixmap(
            &mut sharp,
            0.0,
            0.0,
            32.0,
            32.0,
            &RectStyle {
                outline_thickness: 0,
                outline_color_argb: 0,
                fill_color_argb: 0xFF_FF_00_00,
                corner_radius_px: 0,
            },
        );
        draw_rect_on_pixmap(
            &mut rounded,
            0.0,
            0.0,
            32.0,
            32.0,
            &RectStyle {
                outline_thickness: 0,
                outline_color_argb: 0,
                fill_color_argb: 0xFF_FF_00_00,
                corner_radius_px: 8,
            },
        );
        // (0, 0) corner: sharp is fully red, rounded must be background black (or at most
        // partial AA).
        let sharp_corner = &sharp.data()[..4];
        let rounded_corner = &rounded.data()[..4];
        assert_eq!(sharp_corner[0], 255, "sharp corner is fully red");
        assert!(
            rounded_corner[0] < 128,
            "rounded corner must be mostly background (R={}), not the fill",
            rounded_corner[0]
        );
    }

    #[test]
    fn rounded_rect_clamps_radius_to_half_min_side() {
        // Radius >> min(w, h)/2 must clamp without panicking. With width == height we get
        // a circle (or pill); the center pixel is solidly filled, the corners are clear.
        let mut pixmap = opaque_black_pixmap(32, 32);
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            0.0,
            32.0,
            32.0,
            &RectStyle {
                outline_thickness: 0,
                outline_color_argb: 0,
                fill_color_argb: 0xFF_00_FF_00,
                corner_radius_px: 9999, // way past the cap
            },
        );
        // Center is filled (it's the inscribed circle).
        let center = (16 * 32 + 16) * 4;
        assert_eq!(
            pixmap.data()[center + 1],
            255,
            "center of inscribed circle must be solid green"
        );
        // Corner is clear.
        assert!(
            pixmap.data()[1] < 128,
            "(0,0) is outside the inscribed circle, must remain mostly background"
        );
    }

    #[test]
    fn rounded_rect_extreme_radius_does_not_panic() {
        // u32::MAX radius from Dart must clamp safely with no panic.
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(
            &mut pixmap,
            0.0,
            0.0,
            8.0,
            8.0,
            &RectStyle {
                outline_thickness: 1,
                outline_color_argb: 0xFF_FF_FF_FF,
                fill_color_argb: 0xFF_00_00_FF,
                corner_radius_px: u32::MAX,
            },
        );
    }

    // --- AA on/off contract: sharp corners must be pixel-perfect, rounded corners must AA ----

    /// Fill the pixmap with a sharp-corner red rectangle at INTEGER coords. Every pixel inside
    /// must be exactly red (255,0,0,255), every pixel outside must be untouched. No fractional
    /// alpha anywhere — that's the whole point of the AA-off branch.
    #[test]
    fn sharp_corner_rect_paints_pixel_aligned_fill_without_aa_bleed() {
        let mut pixmap = opaque_black_pixmap(16, 16);
        draw_rect_on_pixmap(&mut pixmap, 4.0, 4.0, 8.0, 8.0, &style(0, 0, 0xFF_FF_00_00));
        // Inside the rect: every pixel exactly red.
        for y in 4..12 {
            for x in 4..12 {
                let off = (y * 16 + x) * 4;
                let px = &pixmap.data()[off..off + 4];
                assert_eq!(
                    px,
                    &[255, 0, 0, 255],
                    "inside ({x},{y}) should be solid red, got {px:?}"
                );
            }
        }
        // Just outside the rect: every pixel exactly the original black. Without disabling AA,
        // tiny-skia would smear partial-alpha red onto the boundary pixels (e.g. (3,4), (12,4)).
        for &(x, y) in &[
            (3, 4),
            (3, 8),
            (12, 4),
            (12, 11),
            (4, 3),
            (11, 12),
            (8, 3),
            (8, 12),
        ] {
            let off = (y * 16 + x) * 4;
            let px = &pixmap.data()[off..off + 4];
            assert_eq!(
                px,
                &[0, 0, 0, 255],
                "boundary-adjacent pixel ({x},{y}) must remain background — no AA bleed"
            );
        }
    }

    /// 1px sharp-corner stroke at integer coords must paint exactly the perimeter pixels at
    /// full opacity, leaving everything else unchanged.
    #[test]
    fn sharp_corner_rect_pixel_perfect_one_px_stroke() {
        let mut pixmap = opaque_black_pixmap(8, 8);
        draw_rect_on_pixmap(&mut pixmap, 1.0, 1.0, 6.0, 6.0, &style(1, 0xFF_00_FF_00, 0));
        for y in 0..8 {
            for x in 0..8 {
                let off = (y * 8 + x) * 4;
                let px = &pixmap.data()[off..off + 4];
                // Cells along the inset rect's perimeter — tiny-skia centers a 1px stroke on
                // the path edge, so the stroke band lands at integer pixel rows/cols 0..=1
                // and 6..=7 along each side. Inner cells (2..=5 on both axes) stay black.
                let inner = (2..=5).contains(&x) && (2..=5).contains(&y);
                if inner {
                    assert_eq!(
                        px,
                        &[0, 0, 0, 255],
                        "interior ({x},{y}) of a 1px stroke must remain background"
                    );
                } else {
                    // No AA: every channel is integer (no partial alpha values like 64 or 192).
                    assert!(
                        px[0] == 0 && (px[1] == 0 || px[1] == 255) && px[2] == 0,
                        "perimeter pixel ({x},{y}) has fractional channels = AA bleed: {px:?}"
                    );
                }
            }
        }
    }

    /// Rounded-corner rect MUST have anti-aliased corner pixels — there's no way to make a
    /// curve look smooth without partial-alpha pixels around it. Asserts at least one pixel
    /// in the corner region falls in the partial-alpha range.
    #[test]
    fn rounded_corner_rect_has_aa_bleed_at_corner_pixels() {
        let mut pixmap = opaque_black_pixmap(32, 32);
        draw_rect_on_pixmap(
            &mut pixmap,
            2.0,
            2.0,
            28.0,
            28.0,
            &RectStyle {
                outline_thickness: 0,
                outline_color_argb: 0,
                fill_color_argb: 0xFF_FF_00_00,
                corner_radius_px: 8,
            },
        );
        // Sample a 6x6 region around the top-left corner of the round-rect bounding box.
        // Without AA there would be only fully-red or fully-black pixels here. With AA, at
        // least a few pixels in the curve must show partial red (1..=254 in the R channel).
        let mut found_partial = false;
        for y in 0..10 {
            for x in 0..10 {
                let off = (y * 32 + x) * 4;
                let r = pixmap.data()[off];
                if (1..=254).contains(&r) {
                    found_partial = true;
                    break;
                }
            }
        }
        assert!(
            found_partial,
            "rounded-corner fill must produce at least one partial-alpha pixel in the corner \
             region — otherwise the curve looks jagged"
        );
    }

    /// Sharp-corner rect must NOT produce any partial-alpha pixels. A negative counterpart to
    /// the rounded-corner test above — proves the two paths actually behave differently.
    #[test]
    fn sharp_corner_rect_produces_no_partial_alpha_anywhere() {
        let mut pixmap = opaque_black_pixmap(32, 32);
        draw_rect_on_pixmap(
            &mut pixmap,
            5.0,
            7.0,
            17.0,
            13.0,
            &style(2, 0xFF_FF_00_00, 0xFF_00_00_FF),
        );
        // Walk every pixel; any R/G/B channel in (0, 255) means AA was applied.
        for (i, chunk) in pixmap.data().chunks_exact(4).enumerate() {
            for (c, &v) in chunk[..3].iter().enumerate() {
                assert!(
                    v == 0 || v == 255,
                    "pixel idx={i} channel={c} has partial value {v} — sharp-corner rect leaked AA"
                );
            }
        }
    }

    #[test]
    fn draw_rect_element_short_circuits_when_neither_outline_nor_fill_will_paint() {
        // Both outline and fill have alpha=0 → no work should hit the pixmap. Verify by
        // ensuring the buffer is bit-identical (which also means we skipped the round-trip
        // conversion that would otherwise lossily premultiply/unpremultiply).
        let original = image::RgbaImage::from_pixel(4, 4, image::Rgba([10, 20, 30, 255]));
        let mut img = original.clone();
        let mut el = make_rect_element();
        el.width = 4.0;
        el.height = 4.0;
        el.outline_thickness = 5;
        el.outline_color_argb = 0x00_FF_FF_FF; // alpha=0
        el.fill_color_argb = 0x00_FF_00_00; // alpha=0
        draw_rect_element(&mut img, &el);
        assert_eq!(
            img.as_raw(),
            original.as_raw(),
            "no visible-paint case must skip work entirely"
        );
    }

    // --- Surface (lazy RGBA <-> Pixmap state machine) ------------------------------------------

    #[test]
    fn surface_starts_in_rgba_and_no_op_as_rgba_keeps_it() {
        let img = image::RgbaImage::from_pixel(2, 2, image::Rgba([1, 2, 3, 255]));
        let mut surface = Surface::Rgba(img);
        // Calling `as_rgba` when already Rgba must be a no-op (no conversion drift).
        let snap = surface.as_rgba().clone();
        let again = surface.as_rgba().clone();
        assert_eq!(snap.as_raw(), again.as_raw(), "as_rgba is idempotent");
    }

    #[test]
    fn surface_starts_in_pixmap_and_no_op_as_pixmap_keeps_it() {
        let pixmap = opaque_black_pixmap(2, 2);
        let mut surface = Surface::Pixmap(pixmap);
        let snap = surface.as_pixmap().data().to_vec();
        let again = surface.as_pixmap().data().to_vec();
        assert_eq!(snap, again, "as_pixmap is idempotent");
    }

    #[test]
    fn surface_round_trip_preserves_opaque_pixels_exactly() {
        // The lazy conversion sits on the same code path Dart's exports do — must not
        // smear color when alpha is fully opaque.
        let mut img = image::RgbaImage::new(4, 4);
        for (i, p) in img.pixels_mut().enumerate() {
            p.0 = [(i * 16) as u8, (i * 8) as u8, (i * 4) as u8, 255];
        }
        let original = img.clone();
        let mut surface = Surface::Rgba(img);
        // Force RGBA -> Pixmap -> RGBA via the surface API.
        let _ = surface.as_pixmap();
        let _ = surface.as_rgba();
        let final_img = surface.into_rgba();
        assert_eq!(
            original.as_raw(),
            final_img.as_raw(),
            "opaque round-trip through Surface must be lossless"
        );
    }

    #[test]
    fn surface_into_rgba_from_pixmap_state_works() {
        // into_rgba consumes the surface — verify it converts when currently Pixmap.
        let pixmap = opaque_black_pixmap(3, 3);
        let surface = Surface::Pixmap(pixmap);
        let img = surface.into_rgba();
        assert_eq!(
            img.dimensions(),
            (3, 3),
            "dimensions preserved on terminal conversion"
        );
    }

    // --- end-to-end via draw_rect_element (FfiElement entry point) -----------------------------

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
        assert!(matches!(
            element_text(&el, buf),
            Err(RenderError::BadUtf8Text)
        ));
    }

    #[test]
    fn element_text_rejects_offset_overflow() {
        let buf = b"hi";
        let mut el = make_rect_element();
        el.text_offset = u32::MAX;
        el.text_length = 1;
        assert!(matches!(
            element_text(&el, buf),
            Err(RenderError::BadUtf8Text)
        ));
    }

    #[test]
    fn element_text_rejects_invalid_utf8() {
        // 0xFF on its own is not a valid UTF-8 start byte.
        let buf: &[u8] = &[0xFF];
        let mut el = make_rect_element();
        el.text_offset = 0;
        el.text_length = 1;
        assert!(matches!(
            element_text(&el, buf),
            Err(RenderError::BadUtf8Text)
        ));
    }

    // --- u32-field audit: prove every wire field that's `u32` survives the worst legal value
    // --- without panicking inside Rust. Runs through draw_rect_element / draw_text_element so
    // --- it covers the exact code paths the FFI uses.

    #[test]
    fn draw_rect_element_survives_u32_max_outline_thickness() {
        let mut img = image::RgbaImage::from_pixel(8, 8, image::Rgba([0, 0, 0, 255]));
        let mut el = make_rect_element();
        el.width = 8.0;
        el.height = 8.0;
        el.outline_thickness = u32::MAX;
        el.outline_color_argb = 0xFF00FF00;
        // Must not panic. With thickness clamped to min(w, h), tiny-skia's stroked geometry
        // stays bounded. Every pixel ends up touched by green to some degree.
        draw_rect_element(&mut img, &el);
        let any_green = img.pixels().any(|p| p.0[1] > 0);
        assert!(
            any_green,
            "clamped giant stroke must paint green into the buffer"
        );
    }

    #[test]
    fn draw_rect_element_survives_huge_floating_dimensions() {
        // width/height arrive as f64 from Dart. A user passing 1e15 (way outside any image)
        // must not crash — tiny-skia accepts any finite f32 path; clipping is its job.
        let mut img = image::RgbaImage::from_pixel(8, 8, image::Rgba([0, 0, 0, 255]));
        let mut el = make_rect_element();
        el.width = 1e15;
        el.height = 1e15;
        el.outline_thickness = 1;
        el.outline_color_argb = 0xFF_FF_00_00;
        draw_rect_element(&mut img, &el);
        // Don't assert specific pixels — at this scale the stroke is sub-image-edge and may
        // not land on integer pixel coords. Survival without panic is the contract.
    }

    #[test]
    fn draw_rect_element_short_circuits_on_zero_thickness_without_pixmap_round_trip() {
        // The zero-thickness early-return matters: without it we'd pay
        // canvas::to_pixmap+from_pixmap for a no-op draw. The invariant we can check is that
        // the bytes round-trip identically.
        let original = image::RgbaImage::from_pixel(4, 4, image::Rgba([10, 20, 30, 255]));
        let mut img = original.clone();
        let mut el = make_rect_element();
        el.width = 4.0;
        el.height = 4.0;
        el.outline_thickness = 0;
        el.outline_color_argb = 0xFFFFFFFF;
        draw_rect_element(&mut img, &el);
        assert_eq!(
            img.as_raw(),
            original.as_raw(),
            "thickness=0 must leave the image bit-identical (no round-trip drift)"
        );
    }

    #[test]
    fn argb_to_tiny_color_matches_image_rgba_unpacking() {
        // tiny-skia helper must agree with the image-crate helper used by text rendering;
        // any drift here means rect outlines and text fills with the same ARGB look different.
        let argb = 0xCC_11_22_33;
        let img_rgba = argb_to_rgba(argb);
        let tiny = argb_to_tiny_color(argb);
        // Color::to_color_u8() returns non-premultiplied RGBA in 0..=255.
        let tiny_rgba = tiny.to_color_u8();
        assert_eq!(
            (
                tiny_rgba.red(),
                tiny_rgba.green(),
                tiny_rgba.blue(),
                tiny_rgba.alpha()
            ),
            (img_rgba.0[0], img_rgba.0[1], img_rgba.0[2], img_rgba.0[3]),
            "ARGB unpack must agree across the two color helpers"
        );
    }

    #[test]
    fn argb_to_rgba_handles_u32_max() {
        // The packed-color fields are pure bit shifts — u32::MAX must produce all-FF channels.
        assert_eq!(argb_to_rgba(u32::MAX).0, [0xFF, 0xFF, 0xFF, 0xFF]);
    }

    #[test]
    fn element_text_handles_u32_max_offset_safely() {
        // text_offset/text_length are `u32` on the wire. A pathological offset that overflows
        // when added to length must surface BadUtf8Text, never panic.
        let buf: &[u8] = b"hello";
        let mut el = make_rect_element();
        el.text_offset = u32::MAX;
        el.text_length = 5;
        assert!(matches!(
            element_text(&el, buf),
            Err(RenderError::BadUtf8Text)
        ));
    }

    #[test]
    fn element_text_handles_u32_max_length_safely() {
        let buf: &[u8] = b"hello";
        let mut el = make_rect_element();
        el.text_offset = 0;
        el.text_length = u32::MAX;
        assert!(matches!(
            element_text(&el, buf),
            Err(RenderError::BadUtf8Text)
        ));
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
            shape_param: 0,
        }
    }
}
