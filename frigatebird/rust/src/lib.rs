#![deny(improper_ctypes_definitions, improper_ctypes)]

use safer_ffi::prelude::*;
use std::path::Path;

use tiny_skia::{Paint, PathBuilder, Pixmap, Rect, Stroke, Transform};

mod canvas;
mod ffi;
mod ffi_element;
pub mod io;
pub mod ops;
pub mod text;

pub use ffi::{
    FfiArena, FfiError, FfiErrorCode, ffi_arena_create, ffi_arena_free, write_error_to_arena,
    write_panic_to_arena,
};
pub use ffi_element::{
    FfiElement, FfiPayload, OvalPayload, PolygonPayload, RectanglePayload, Shape, ShapeBuilder,
    TextPayload,
};

// Rust-side layout anchors: if these ever change, the Dart Struct declarations must be updated.
pub type ByteBuffer = c_slice::Box<u8>;

#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ImageInformation {
    pub width: u32,      // oriented (post-EXIF)
    pub height: u32,     // oriented (post-EXIF)
    pub format: u8,      // 0 = PNG, 1 = JPEG, 255 = unknown
    pub orientation: u8, // raw EXIF tag 1..=8 for diagnostics
    pub _pad: [u8; 2],   // explicit C alignment padding
}

impl Default for ImageInformation {
    fn default() -> Self {
        Self {
            width: 0,
            height: 0,
            format: 255,
            orientation: 1,
            _pad: [0; 2],
        }
    }
}

// --- Size Oracles ---

#[ffi_export]
pub fn sizeof_ffi_element() -> usize {
    core::mem::size_of::<FfiElement>()
}
#[ffi_export]
pub fn sizeof_ffi_payload() -> usize {
    core::mem::size_of::<FfiPayload>()
}
#[ffi_export]
pub fn sizeof_ffi_arena() -> usize {
    core::mem::size_of::<FfiArena>()
}
#[ffi_export]
pub fn sizeof_ffi_error() -> usize {
    core::mem::size_of::<FfiError>()
}
#[ffi_export]
pub fn sizeof_image_info() -> usize {
    core::mem::size_of::<ImageInformation>()
}
#[ffi_export]
pub fn sizeof_polygon_payload() -> usize {
    core::mem::size_of::<PolygonPayload>()
}

// --- Drop Hooks ---

/// Free a Rust-allocated byte buffer.
#[ffi_export]
pub fn free_byte_buffer(buf: ByteBuffer) {
    drop(buf);
}

// --- Test Helpers ---

/// Test helper to force an error.
///
/// # Safety
/// `msg` must be a valid pointer to a UTF-8 string of length `len`. `arena` must be a valid pointer.
#[cfg(feature = "ffi-test-helpers")]
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ffi_force_error(
    code: u8,
    msg: *const u8,
    len: usize,
    arena: *mut FfiArena,
) -> u8 {
    unsafe {
        let arena_opt = arena.as_mut();
        let msg_str = if msg.is_null() || len == 0 {
            ""
        } else {
            std::str::from_utf8(std::slice::from_raw_parts(msg, len)).unwrap_or("Invalid UTF-8")
        };

        let ffi_code = match code {
            1 => FfiErrorCode::Panic,
            2 => FfiErrorCode::InvalidArg,
            3 => FfiErrorCode::Io,
            4 => FfiErrorCode::Decode,
            5 => FfiErrorCode::Encode,
            6 => FfiErrorCode::Font,
            7 => FfiErrorCode::Render,
            8 => FfiErrorCode::Utf8,
            0 => FfiErrorCode::Success,
            _ => FfiErrorCode::Unknown,
        };

        write_error_to_arena(arena_opt, ffi_code, msg_str).code
    }
}

/// Test helper to zero an element.
///
/// # Safety
/// `out` must be a valid pointer to an `FfiElement`.
#[cfg(feature = "ffi-test-helpers")]
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ffi_zero_element(out: *mut FfiElement) {
    if !out.is_null() {
        unsafe { std::ptr::write_bytes(out, 0, 1) };
    }
}

/// Test helper to fill an element with 0xAA.
///
/// # Safety
/// `out` must be a valid pointer to an `FfiElement`.
#[cfg(feature = "ffi-test-helpers")]
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ffi_fill_element_0xAA(out: *mut FfiElement) {
    if !out.is_null() {
        unsafe { std::ptr::write_bytes(out, 0xAA, 1) };
    }
}

fn handle_panic(arena: Option<&mut FfiArena>, payload: Box<dyn std::any::Any + Send>) -> u8 {
    // Extract message as &str without cloning. The downcast_ref borrows from the Box which
    // lives for the duration of this function — no allocation needed.
    let fallback;
    let msg: &str = if let Some(s) = payload.downcast_ref::<&'static str>() {
        s
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.as_str()
    } else {
        fallback = "panic with non-string payload";
        fallback
    };
    write_panic_to_arena(arena, msg).code
}

// PERMANENT EXCEPTIONS to #[ffi_export]:
//
// - `draw_elements`: takes `*const FfiElement` — safer_ffi 0.2.0-rc1 cannot derive
//   ReprC for #[repr(C, u8)] tagged-union enums. Tracked upstream.

/// Returns oriented dimensions and metadata for an image without decoding full pixel data.
/// Returns a `u8` status code. Result info is written to `*out`.
#[ffi_export]
pub fn get_image_info(
    path: Option<char_p::Ref<'_>>,
    arena: Option<&mut FfiArena>,
    out: &mut ImageInformation,
) -> u8 {
    let mut arena_opt = arena;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<ImageInformation, (FfiErrorCode, String)> = (|| {
            let p_str = if let Some(p) = path {
                p.to_str()
            } else {
                return Err((FfiErrorCode::InvalidArg, "Missing path".to_string()));
            };
            let path_ref = Path::new(p_str);

            let reader = image::ImageReader::open(path_ref).map_err(|_| {
                (
                    FfiErrorCode::Io,
                    "Failed to open image for info".to_string(),
                )
            })?;
            let reader = reader.with_guessed_format().map_err(|_| {
                (
                    FfiErrorCode::Decode,
                    "Failed to guess image format".to_string(),
                )
            })?;

            let format = match reader.format() {
                Some(image::ImageFormat::Png) => 0,
                Some(image::ImageFormat::Jpeg) => 1,
                _ => 255,
            };

            let (mut w, mut h) = reader.into_dimensions().map_err(|_| {
                (
                    FfiErrorCode::Decode,
                    "Failed to read image dimensions".to_string(),
                )
            })?;

            let orientation = io::read_orientation(path_ref);
            // Tags 5, 6, 7, 8 involve a 90 or 270 degree rotation, which swaps dimensions.
            if (5..=8).contains(&orientation) {
                std::mem::swap(&mut w, &mut h);
            }

            Ok(ImageInformation {
                width: w,
                height: h,
                format,
                orientation,
                _pad: [0; 2],
            })
        })();
        inner
    }));

    match result {
        Ok(Ok(info)) => {
            *out = info;
            FfiErrorCode::Success as u8
        }
        Ok(Err((code, msg))) => {
            *out = ImageInformation::default();
            write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code
        }
        Err(payload) => {
            *out = ImageInformation::default();
            handle_panic(arena_opt, payload)
        }
    }
}

/// Bytes-in / path-in merge: composites `foreground_png` bytes over the image at `background_path`
/// and returns the result as a byte buffer owned by Rust.
///
/// Returns a `u8` status code (`FfiErrorCode` cast to `u8`). Result buffer is written to `*out`.
/// (Previously returned i32; now returns u8/FfiErrorCode.)
#[allow(unsafe_code)]
#[ffi_export]
pub fn merge(
    background_path: Option<char_p::Ref<'_>>,
    foreground_png: c_slice::Ref<'_, u8>,
    dx: i32,
    dy: i32,
    out_format: u8,
    image_quality: u8,
    arena: Option<&mut FfiArena>,
    out: &mut ByteBuffer,
) -> u8 {
    let mut arena_opt = arena;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<Vec<u8>, (FfiErrorCode, String)> = (|| {
            let bg_p = if let Some(p) = background_path {
                p.to_str()
            } else {
                return Err((
                    FfiErrorCode::InvalidArg,
                    "Missing background path".to_string(),
                ));
            };

            let fg_bytes = if foreground_png.is_empty() {
                return Err((
                    FfiErrorCode::InvalidArg,
                    "Foreground length is zero".to_string(),
                ));
            } else {
                foreground_png.as_slice()
            };

            let mut bg_img = io::read_image(Path::new(bg_p)).map_err(|e| {
                let code = match e {
                    io::IoError::Read => FfiErrorCode::Io,
                    _ => FfiErrorCode::Decode,
                };
                (code, "Failed to read/decode background image".to_string())
            })?;

            let fg_img = image::load_from_memory(fg_bytes).map_err(|_| {
                (
                    FfiErrorCode::Decode,
                    "Failed to decode foreground image".to_string(),
                )
            })?;

            image::imageops::overlay(&mut bg_img, &fg_img, i64::from(dx), i64::from(dy));

            let mut buf = std::io::Cursor::new(Vec::new());
            if out_format == 0 {
                // PNG
                bg_img
                    .write_to(&mut buf, image::ImageFormat::Png)
                    .map_err(|_| (FfiErrorCode::Encode, "Failed to encode PNG".to_string()))?;
            } else {
                // JPEG
                let rgb_img = bg_img.into_rgb8();
                image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, image_quality)
                    .encode_image(&rgb_img)
                    .map_err(|_| (FfiErrorCode::Encode, "Failed to encode JPEG".to_string()))?;
            }

            Ok(buf.into_inner())
        })();
        inner
    }));

    match result {
        Ok(Ok(bytes)) => {
            unsafe { std::ptr::write(out, bytes.into_boxed_slice().into()) };
            FfiErrorCode::Success as u8
        }
        Ok(Err((code, msg))) => {
            unsafe { std::ptr::write(out, Vec::new().into_boxed_slice().into()) };
            write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code
        }
        Err(payload) => {
            unsafe { std::ptr::write(out, Vec::new().into_boxed_slice().into()) };
            handle_panic(arena_opt, payload)
        }
    }
}

/// # Safety
///
/// The `ptr` must be valid or null. This function just returns it back.
#[cfg(any(test, feature = "ffi-echo"))]
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ffi_echo_element(ptr: *const FfiElement) -> *const FfiElement {
    ptr
}

/// Unified render call: reads the image from `image_path`, composites all `FfiElement`s
/// (rectangles, text, future shapes), writes the result to `output_path`.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
///
/// # Safety
///
/// All pointer arguments must be valid for the duration of the call.
///
/// NOTE: We use `#[unsafe(no_mangle)]` rather than `#[ffi_export]` because `FfiElement`
/// is a `repr(C, u8)` enum with payloads, which `safer_ffi` 0.2.0-rc1 does not yet
/// support for `derive_ReprC`.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn draw_elements(
    image_path: *const std::ffi::c_char,
    output_path: *const std::ffi::c_char,
    font_path: *const std::ffi::c_char,
    elements_ptr: *const FfiElement,
    elements_count: usize,
    image_quality: u8,
    arena: *mut FfiArena,
) -> u8 {
    // SAFETY: Caller guarantees `arena` is a valid pointer to `FfiArena`.
    let arena_opt = unsafe { arena.as_mut() };

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let img_p = if image_path.is_null() {
            return Err((FfiErrorCode::InvalidArg, "Missing image path".to_string()));
        } else {
            unsafe { std::ffi::CStr::from_ptr(image_path) }
                .to_str()
                .map_err(|_| {
                    (
                        FfiErrorCode::Utf8,
                        "Invalid UTF-8 in image path".to_string(),
                    )
                })?
        };

        let out_p = if output_path.is_null() {
            img_p
        } else {
            unsafe { std::ffi::CStr::from_ptr(output_path) }
                .to_str()
                .map_err(|_| {
                    (
                        FfiErrorCode::Utf8,
                        "Invalid UTF-8 in output path".to_string(),
                    )
                })?
        };

        let elements = if elements_count == 0 {
            &[]
        } else if elements_ptr.is_null() {
            return Err((
                FfiErrorCode::InvalidArg,
                "Missing elements pointer".to_string(),
            ));
        } else {
            // SAFETY: Caller guarantees `elements_ptr` points to `elements_count` valid `FfiElement`s.
            unsafe { std::slice::from_raw_parts(elements_ptr, elements_count) }
        };

        let text_buffer = match arena_opt.as_deref() {
            None | Some(FfiArena { text_len: 0, .. }) => &[][..],
            Some(a) if a.text_buf.is_null() => {
                return Err((
                    FfiErrorCode::InvalidArg,
                    "Missing text buffer pointer".to_string(),
                ));
            }
            Some(a) => {
                // SAFETY: Caller guarantees `text_buf` points to `text_len` valid bytes.
                unsafe { std::slice::from_raw_parts(a.text_buf, a.text_len) }
            }
        };

        let font_p = if font_path.is_null() {
            None
        } else {
            Some(
                unsafe { std::ffi::CStr::from_ptr(font_path) }
                    .to_str()
                    .map_err(|_| (FfiErrorCode::Utf8, "Invalid UTF-8 in font path".to_string()))?,
            )
        };

        draw_elements_safe(img_p, out_p, font_p, elements, text_buffer, image_quality)
    }));

    match result {
        Ok(Ok(())) => FfiErrorCode::Success as u8,
        Ok(Err((code, msg))) => write_error_to_arena(arena_opt, code, &msg).code,
        Err(payload) => handle_panic(arena_opt, payload),
    }
}

fn get_rotated_aabb(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    rotation_deg: i32,
) -> RectanglePayload {
    if rotation_deg == 0 {
        return RectanglePayload::new(x, y, width, height, 0);
    }
    let rad = (rotation_deg as f64).to_radians();
    let cos_theta = rad.cos();
    let sin_theta = rad.sin();

    let cx = x + width / 2.0;
    let cy = y + height / 2.0;

    let dx1 = -width / 2.0;
    let dx2 = width / 2.0;
    let dy1 = -height / 2.0;
    let dy2 = height / 2.0;

    let pts = [
        (
            dx1 * cos_theta - dy1 * sin_theta,
            dx1 * sin_theta + dy1 * cos_theta,
        ),
        (
            dx2 * cos_theta - dy1 * sin_theta,
            dx2 * sin_theta + dy1 * cos_theta,
        ),
        (
            dx1 * cos_theta - dy2 * sin_theta,
            dx1 * sin_theta + dy2 * cos_theta,
        ),
        (
            dx2 * cos_theta - dy2 * sin_theta,
            dx2 * sin_theta + dy2 * cos_theta,
        ),
    ];

    let (mut min_x, mut max_x) = (pts[0].0, pts[0].0);
    let (mut min_y, mut max_y) = (pts[0].1, pts[0].1);
    for &(px, py) in &pts[1..] {
        if px < min_x {
            min_x = px;
        }
        if px > max_x {
            max_x = px;
        }
        if py < min_y {
            min_y = py;
        }
        if py > max_y {
            max_y = py;
        }
    }

    RectanglePayload::new(cx + min_x, cy + min_y, max_x - min_x, max_y - min_y, 0)
}

#[allow(unsafe_code)]
fn draw_elements_safe(
    image_path: &str,
    output_path: &str,
    font_path: Option<&str>,
    elements: &[FfiElement],
    text_buffer: &[u8],
    image_quality: u8,
) -> Result<(), (FfiErrorCode, String)> {
    let needs_font = elements.iter().any(|e| matches!(e, FfiElement::Text(_)));
    let font_bytes_holder;
    let font: Option<ab_glyph::FontRef<'_>> = if needs_font {
        let f_path =
            font_path.ok_or((FfiErrorCode::InvalidArg, "Missing font path".to_string()))?;

        font_bytes_holder = io::read_font(Path::new(f_path))
            .map_err(|_| (FfiErrorCode::Io, "Failed to read font".to_string()))?;
        Some(
            ab_glyph::FontRef::try_from_slice(&font_bytes_holder)
                .map_err(|_| (FfiErrorCode::Font, "Failed to parse font".to_string()))?,
        )
    } else {
        None
    };

    let img = io::read_image(Path::new(image_path))
        .map_err(|e| {
            let code = match e {
                io::IoError::Read => FfiErrorCode::Io,
                _ => FfiErrorCode::Decode,
            };
            (code, "Failed to read/decode image".to_string())
        })?
        .into_rgba8();

    // Conditional clone: only allocate a clean source when at least one element requires blur.
    // This avoids the full-image clone for the common case of no-blur elements.
    let mut clean_img: Option<image::RgbaImage> = None;
    let needs_clean_img = elements.iter().any(|e| match e {
        FfiElement::Rectangle(p) => p.blur > 0,
        FfiElement::Oval(p) => p.blur > 0,
        FfiElement::Polygon(p) => p.blur > 0,
        FfiElement::Text(_) => false,
    });
    if needs_clean_img {
        clean_img = Some(img.clone());
    }
    let mut surface = Surface::Rgba(img);

    for element in elements {
        draw_element_on_surface(
            &mut surface,
            clean_img.as_ref(),
            element,
            font.as_ref(),
            text_buffer,
        )?;
    }

    let img = surface.into_rgba();
    io::write_image(Path::new(output_path), &img, image_quality).map_err(|e| {
        let code = match e {
            io::IoError::UnsupportedFormat | io::IoError::Encode => FfiErrorCode::Encode,
            _ => FfiErrorCode::Io,
        };
        (code, "Failed to write image".to_string())
    })
}

fn draw_element_on_surface(
    surface: &mut Surface,
    clean_img: Option<&image::RgbaImage>,
    element: &FfiElement,
    font: Option<&ab_glyph::FontRef<'_>>,
    text_buffer: &[u8],
) -> Result<(), (FfiErrorCode, String)> {
    match element {
        FfiElement::Rectangle(p) => {
            if p.blur > 0 {
                let clean = clean_img.ok_or_else(|| {
                    (
                        FfiErrorCode::Panic,
                        "Missing clean source image for blur".to_string(),
                    )
                })?;
                let aabb = get_rotated_aabb(p.x, p.y, p.width, p.height, p.rotation_deg);
                let rect = *p;
                ops::blur::blur_shape_rgba_from_src(
                    surface.as_rgba(),
                    clean,
                    aabb,
                    p.blur,
                    |mask, dx, dy| {
                        let style = ShapeStyle {
                            fill_color: Some(tiny_skia::Color::from_rgba8(255, 255, 255, 255)),
                            outline_color: None,
                            thickness: 0.0,
                        };
                        draw_rect_on_pixmap(mask, &rect, &style, dx, dy)
                    },
                )?;
            }
            let style: ShapeStyle = p.into();
            if style.paints_anything() {
                draw_rect_on_pixmap(surface.as_pixmap(), p, &style, 0.0, 0.0)?;
            }
        }
        FfiElement::Oval(p) => {
            if p.blur > 0 {
                let clean = clean_img.ok_or_else(|| {
                    (
                        FfiErrorCode::Panic,
                        "Missing clean source image for blur".to_string(),
                    )
                })?;
                let aabb = get_rotated_aabb(p.x, p.y, p.width, p.height, p.rotation_deg);
                let oval = *p;
                ops::blur::blur_shape_rgba_from_src(
                    surface.as_rgba(),
                    clean,
                    aabb,
                    p.blur,
                    |mask, dx, dy| {
                        let style = ShapeStyle {
                            fill_color: Some(tiny_skia::Color::from_rgba8(255, 255, 255, 255)),
                            outline_color: None,
                            thickness: 0.0,
                        };
                        draw_oval_on_pixmap(mask, &oval, &style, dx, dy)
                    },
                )?;
            }
            let style: ShapeStyle = p.into();
            if style.paints_anything() {
                draw_oval_on_pixmap(surface.as_pixmap(), p, &style, 0.0, 0.0)?;
            }
        }
        FfiElement::Text(p) => {
            // Text elements intentionally ignore the blur field.
            let text_slice = element_text(p, text_buffer).map_err(|e| match e {
                ElementTextError::Bounds => (
                    FfiErrorCode::InvalidArg,
                    "Text element slice out of bounds".to_string(),
                ),
                ElementTextError::Utf8 => (
                    FfiErrorCode::Utf8,
                    "Invalid UTF-8 in text element".to_string(),
                ),
            })?;
            if let Some(font_ref) = font {
                draw_text_element(surface.as_rgba(), font_ref, p, text_slice);
            }
        }
        FfiElement::Polygon(p) => {
            if p.blur > 0 {
                let clean = clean_img.ok_or_else(|| {
                    (
                        FfiErrorCode::Panic,
                        "Missing clean source image for blur".to_string(),
                    )
                })?;
                let aabb = get_rotated_aabb(p.x, p.y, p.width, p.height, p.rotation_deg);
                let poly = *p;
                ops::blur::blur_shape_rgba_from_src(
                    surface.as_rgba(),
                    clean,
                    aabb,
                    p.blur,
                    |mask, dx, dy| {
                        let style = ShapeStyle {
                            fill_color: Some(tiny_skia::Color::from_rgba8(255, 255, 255, 255)),
                            outline_color: None,
                            thickness: 0.0,
                        };
                        draw_polygon_on_pixmap(mask, &poly, &style, dx, dy)
                    },
                )?;
            }
            let style: ShapeStyle = p.into();
            if style.paints_anything() {
                draw_polygon_on_pixmap(surface.as_pixmap(), p, &style, 0.0, 0.0)?;
            }
        }
    }
    Ok(())
}

pub fn draw_element(
    img: &mut image::RgbaImage,
    element: &FfiElement,
    font: Option<&ab_glyph::FontRef<'_>>,
    text_buffer: &[u8],
) {
    let clean_img = img.clone();
    let mut surface = Surface::Rgba(std::mem::take(img));
    let _ = draw_element_on_surface(&mut surface, Some(&clean_img), element, font, text_buffer);
    *img = surface.into_rgba();
}

#[derive(Debug)]
enum ElementTextError {
    Bounds,
    Utf8,
}

fn element_text<'b>(p: &TextPayload, text_buffer: &'b [u8]) -> Result<&'b str, ElementTextError> {
    let start = p.text_offset as usize;
    let len = p.text_len as usize;
    let end = start.checked_add(len).ok_or(ElementTextError::Bounds)?;
    if end > text_buffer.len() {
        return Err(ElementTextError::Bounds);
    }
    std::str::from_utf8(&text_buffer[start..end]).map_err(|_| ElementTextError::Utf8)
}

enum Surface {
    Rgba(image::RgbaImage),
    Pixmap(Pixmap),
}

impl Surface {
    fn as_rgba(&mut self) -> &mut image::RgbaImage {
        match self {
            Self::Rgba(img) => img,
            Self::Pixmap(p) => {
                *self = Self::Rgba(canvas::from_pixmap(p));
                match self {
                    Self::Rgba(img) => img,
                    _ => unreachable!("Surface must be Rgba after conversion from Pixmap"),
                }
            }
        }
    }

    fn as_pixmap(&mut self) -> &mut Pixmap {
        match self {
            Self::Pixmap(p) => p,
            Self::Rgba(img) => {
                *self = Self::Pixmap(canvas::to_pixmap(img));
                match self {
                    Self::Pixmap(p) => p,
                    _ => unreachable!("Surface must be Pixmap after conversion from Rgba"),
                }
            }
        }
    }

    fn into_rgba(self) -> image::RgbaImage {
        match self {
            Self::Rgba(img) => img,
            Self::Pixmap(p) => canvas::from_pixmap(&p),
        }
    }
}

struct ShapeStyle {
    fill_color: Option<tiny_skia::Color>,
    outline_color: Option<tiny_skia::Color>,
    thickness: f32,
}

impl ShapeStyle {
    fn paints_anything(&self) -> bool {
        self.fill_color.is_some() || (self.outline_color.is_some() && self.thickness > 0.0)
    }
}

impl From<&RectanglePayload> for ShapeStyle {
    fn from(p: &RectanglePayload) -> Self {
        Self {
            fill_color: ffi_color_to_skia(p.fill_color_argb),
            outline_color: ffi_color_to_skia(p.outline_color_argb),
            thickness: p.outline_thickness as f32,
        }
    }
}

impl From<&OvalPayload> for ShapeStyle {
    fn from(p: &OvalPayload) -> Self {
        Self {
            fill_color: ffi_color_to_skia(p.fill_color_argb),
            outline_color: ffi_color_to_skia(p.outline_color_argb),
            thickness: p.outline_thickness as f32,
        }
    }
}

impl From<&PolygonPayload> for ShapeStyle {
    fn from(p: &PolygonPayload) -> Self {
        Self {
            fill_color: ffi_color_to_skia(p.fill_color_argb),
            outline_color: ffi_color_to_skia(p.outline_color_argb),
            thickness: p.outline_thickness as f32,
        }
    }
}

/// Converts an ARGB u32 to a tiny-skia Color.
/// Returns `None` when `alpha == 0` (i.e. fully transparent), allowing rendering passes
/// like `paints_anything()` to skip purely-transparent shapes entirely instead of returning `Color::TRANSPARENT`.
fn ffi_color_to_skia(argb: u32) -> Option<tiny_skia::Color> {
    let a = (argb >> 24) as u8;
    if a == 0 {
        return None;
    }
    let r = ((argb >> 16) & 0xFF) as u8;
    let g = ((argb >> 8) & 0xFF) as u8;
    let b = (argb & 0xFF) as u8;
    Some(tiny_skia::Color::from_rgba8(r, g, b, a))
}

fn draw_rect_on_pixmap(
    pixmap: &mut Pixmap,
    p: &RectanglePayload,
    style: &ShapeStyle,
    dx: f64,
    dy: f64,
) -> Result<(), (FfiErrorCode, String)> {
    let mut pb = PathBuilder::new();

    let x = (p.x - dx) as f32;
    let y = (p.y - dy) as f32;
    let w = p.width as f32;
    let h = p.height as f32;

    if w <= 0.0 || h <= 0.0 {
        return Ok(());
    }

    if p.corner_radius > 0 {
        let max_r = (w.min(h) / 2.0).floor();
        let r = (p.corner_radius as f32).min(max_r);

        pb.move_to(x + r, y);
        pb.line_to(x + w - r, y);
        pb.quad_to(x + w, y, x + w, y + r);
        pb.line_to(x + w, y + h - r);
        pb.quad_to(x + w, y + h, x + w - r, y + h);
        pb.line_to(x + r, y + h);
        pb.quad_to(x, y + h, x, y + h - r);
        pb.line_to(x, y + r);
        pb.quad_to(x, y, x + r, y);
        pb.close();
    } else {
        pb.push_rect(Rect::from_xywh(x, y, w, h).ok_or_else(|| {
            (
                FfiErrorCode::InvalidArg,
                "Invalid rectangle dimensions".to_string(),
            )
        })?);
    }
    let path = pb
        .finish()
        .ok_or_else(|| (FfiErrorCode::Render, "Failed to finish path".to_string()))?;

    draw_shape_path(
        pixmap,
        &path,
        p.rotation_deg,
        p.x - dx,
        p.y - dy,
        p.width,
        p.height,
        style,
    );
    Ok(())
}

fn draw_oval_on_pixmap(
    pixmap: &mut Pixmap,
    p: &OvalPayload,
    style: &ShapeStyle,
    dx: f64,
    dy: f64,
) -> Result<(), (FfiErrorCode, String)> {
    let mut pb = PathBuilder::new();
    let x = (p.x - dx) as f32;
    let y = (p.y - dy) as f32;
    let w = p.width as f32;
    let h = p.height as f32;

    if w <= 0.0 || h <= 0.0 {
        return Ok(());
    }

    pb.push_oval(Rect::from_xywh(x, y, w, h).ok_or_else(|| {
        (
            FfiErrorCode::InvalidArg,
            "Invalid oval dimensions".to_string(),
        )
    })?);
    let path = pb
        .finish()
        .ok_or_else(|| (FfiErrorCode::Render, "Failed to finish path".to_string()))?;

    draw_shape_path(
        pixmap,
        &path,
        p.rotation_deg,
        p.x - dx,
        p.y - dy,
        p.width,
        p.height,
        style,
    );
    Ok(())
}

#[allow(unsafe_code)]
fn draw_polygon_on_pixmap(
    pixmap: &mut Pixmap,
    p: &PolygonPayload,
    style: &ShapeStyle,
    dx: f64,
    dy: f64,
) -> Result<(), (FfiErrorCode, String)> {
    if p.vertex_count < 3 {
        return Ok(()); // degenerate — skip silently
    }
    if p.vertices_ptr.is_null() {
        return Err((
            FfiErrorCode::InvalidArg,
            "Polygon vertices pointer is null".into(),
        ));
    }

    let len = (p.vertex_count as usize).checked_mul(2).ok_or_else(|| {
        (
            FfiErrorCode::InvalidArg,
            "Polygon vertex count calculation overflowed".into(),
        )
    })?;

    // SAFETY: Dart guarantees vertices_ptr points to the checked, safe length
    // of valid f64s for the duration of the draw_elements call.
    let verts: &[f64] = unsafe { std::slice::from_raw_parts(p.vertices_ptr, len) };

    let mut pb = PathBuilder::new();
    // tiny-skia uses f32; coordinates beyond ±16M lose sub-pixel precision
    pb.move_to((verts[0] - dx) as f32, (verts[1] - dy) as f32);
    for pair in verts[2..].chunks_exact(2) {
        pb.line_to((pair[0] - dx) as f32, (pair[1] - dy) as f32);
    }
    pb.close();

    let path = pb
        .finish()
        .ok_or_else(|| (FfiErrorCode::Render, "Failed to finish polygon path".into()))?;

    draw_shape_path(
        pixmap,
        &path,
        p.rotation_deg,
        p.x - dx,
        p.y - dy,
        p.width,
        p.height,
        style,
    );
    Ok(())
}

fn draw_shape_path(
    pixmap: &mut Pixmap,
    path: &tiny_skia::Path,
    rotation_deg: i32,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    style: &ShapeStyle,
) {
    let ts = if rotation_deg != 0 {
        Transform::from_translate((x + width / 2.0) as f32, (y + height / 2.0) as f32)
            .pre_rotate(rotation_deg as f32)
            .pre_translate(-(x + width / 2.0) as f32, -(y + height / 2.0) as f32)
    } else {
        Transform::identity()
    };

    if let Some(color) = style.fill_color {
        let mut paint = Paint {
            anti_alias: true,
            ..Default::default()
        };
        paint.set_color(color);
        pixmap.fill_path(path, &paint, tiny_skia::FillRule::Winding, ts, None);
    }

    if let Some(color) = style.outline_color {
        let mut paint = Paint {
            anti_alias: true,
            ..Default::default()
        };
        paint.set_color(color);
        let stroke = Stroke {
            width: style.thickness,
            ..Default::default()
        };
        pixmap.stroke_path(path, &paint, &stroke, ts, None);
    }
}

fn draw_text_element(
    img: &mut image::RgbaImage,
    font: &ab_glyph::FontRef<'_>,
    p: &TextPayload,
    text: &str,
) {
    let color = [
        ((p.fill_color_argb >> 16) & 0xFF) as u8,
        ((p.fill_color_argb >> 8) & 0xFF) as u8,
        (p.fill_color_argb & 0xFF) as u8,
        (p.fill_color_argb >> 24) as u8,
    ];

    let params = text::TextParams {
        text,
        x: p.x as f32,
        y: p.y as f32,
        font_size_px: p.height as f32,
        rotation_rad: (p.rotation_deg as f32).to_radians(),
        color: image::Rgba(color),
    };

    text::render_text_overlay(img, font, &params);
}

/// Applies Gaussian blur to a region of an image.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
#[ffi_export]
pub fn blur_region(
    image_path: Option<char_p::Ref<'_>>,
    output_path: Option<char_p::Ref<'_>>,
    region: RectanglePayload,
    image_quality: u8,
    arena: Option<&mut FfiArena>,
) -> u8 {
    let mut arena_opt = arena;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<(), (FfiErrorCode, String)> = (|| {
            let img_p = if let Some(p) = image_path {
                p.to_str()
            } else {
                return Err((FfiErrorCode::InvalidArg, "Missing image path".to_string()));
            };

            let out_p = if let Some(p) = output_path {
                p.to_str()
            } else {
                img_p
            };

            // If blur radius is 0, we can short-circuit immediate Success without reading the file.
            if region.blur == 0 {
                return Ok(());
            }

            // If width or height is zero, it's a zero-area region, which is a guaranteed no-op.
            // Short-circuit immediately without reading/writing the image file.
            if region.width == 0.0 || region.height == 0.0 {
                return Ok(());
            }

            let mut img = io::read_image(Path::new(img_p))
                .map_err(|e| {
                    let code = match e {
                        io::IoError::Read => FfiErrorCode::Io,
                        _ => FfiErrorCode::Decode,
                    };
                    (code, "Failed to read/decode image".to_string())
                })?
                .into_rgba8();

            // Run shape-masked blur on the rectangle region
            ops::blur::blur_shape_rgba(&mut img, region, region.blur, |mask, dx, dy| {
                let style = ShapeStyle {
                    fill_color: Some(tiny_skia::Color::from_rgba8(255, 255, 255, 255)),
                    outline_color: None,
                    thickness: 0.0,
                };
                draw_rect_on_pixmap(mask, &region, &style, dx, dy)
            })?;

            // Re-save image
            io::write_image(Path::new(out_p), &img, image_quality).map_err(|e| {
                let code = match e {
                    io::IoError::UnsupportedFormat | io::IoError::Encode => FfiErrorCode::Encode,
                    _ => FfiErrorCode::Io,
                };
                (code, "Failed to write image".to_string())
            })?;

            Ok(())
        })();
        inner
    }));

    match result {
        Ok(Ok(())) => FfiErrorCode::Success as u8,
        Ok(Err((code, msg))) => write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code,
        Err(payload) => handle_panic(arena_opt, payload),
    }
}

/// Applies Gaussian blur to the entire image.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
#[ffi_export]
pub fn blur(
    image_path: Option<char_p::Ref<'_>>,
    output_path: Option<char_p::Ref<'_>>,
    radius_px: u8,
    image_quality: u8,
    arena: Option<&mut FfiArena>,
) -> u8 {
    let mut arena_opt = arena;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<(), (FfiErrorCode, String)> = (|| {
            let img_p = if let Some(p) = image_path {
                p.to_str()
            } else {
                return Err((FfiErrorCode::InvalidArg, "Missing image path".to_string()));
            };

            let out_p = if let Some(p) = output_path {
                p.to_str()
            } else {
                img_p
            };

            if radius_px == 0 {
                return Ok(());
            }

            let img = io::read_image(Path::new(img_p))
                .map_err(|e| {
                    let code = match e {
                        io::IoError::Read => FfiErrorCode::Io,
                        _ => FfiErrorCode::Decode,
                    };
                    (code, "Failed to read/decode image".to_string())
                })?
                .into_rgba8();

            let sigma = radius_px as f32 / 3.0;
            let blurred = image::imageops::blur(&img, sigma);

            // Re-save image
            io::write_image(Path::new(out_p), &blurred, image_quality).map_err(|e| {
                let code = match e {
                    io::IoError::UnsupportedFormat | io::IoError::Encode => FfiErrorCode::Encode,
                    _ => FfiErrorCode::Io,
                };
                (code, "Failed to write image".to_string())
            })?;

            Ok(())
        })();
        inner
    }));

    match result {
        Ok(Ok(())) => FfiErrorCode::Success as u8,
        Ok(Err((code, msg))) => write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code,
        Err(payload) => handle_panic(arena_opt, payload),
    }
}

/// Rotates an image by 90° increments (quarter turns).
///
/// `quarter_turns`: 0 = no-op, 1 = 90° CW, 2 = 180°, 3 = 270° CW. Values ≥ 4 are mod 4.
/// If `output_path` is NULL, overwrites `image_path`.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
#[ffi_export]
pub fn rotate(
    image_path: Option<char_p::Ref<'_>>,
    output_path: Option<char_p::Ref<'_>>,
    quarter_turns: u8,
    image_quality: u8,
    arena: Option<&mut FfiArena>,
) -> u8 {
    let mut arena_opt = arena;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<(), (FfiErrorCode, String)> = (|| {
            let img_p = if let Some(p) = image_path {
                p.to_str()
            } else {
                return Err((FfiErrorCode::InvalidArg, "Missing image path".to_string()));
            };

            let out_p = if let Some(p) = output_path {
                p.to_str()
            } else {
                img_p
            };

            // 0 quarter turns (mod 4) is a no-op — skip file I/O entirely.
            if quarter_turns.is_multiple_of(4) {
                return Ok(());
            }

            let img = io::read_image(Path::new(img_p)).map_err(|e| {
                let code = match e {
                    io::IoError::Read => FfiErrorCode::Io,
                    _ => FfiErrorCode::Decode,
                };
                (code, "Failed to read/decode image".to_string())
            })?;

            let rotated = ops::rotate::Rotate { quarter_turns }.apply(img).unwrap();
            let rgba = rotated.into_rgba8();

            io::write_image(Path::new(out_p), &rgba, image_quality).map_err(|e| {
                let code = match e {
                    io::IoError::UnsupportedFormat | io::IoError::Encode => FfiErrorCode::Encode,
                    _ => FfiErrorCode::Io,
                };
                (code, "Failed to write rotated image".to_string())
            })?;

            Ok(())
        })();
        inner
    }));

    match result {
        Ok(Ok(())) => FfiErrorCode::Success as u8,
        Ok(Err((code, msg))) => write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code,
        Err(payload) => handle_panic(arena_opt, payload),
    }
}

/// Converts an image to JPEG format.
///
/// Reads any supported format, writes JPEG at `image_quality` (0..=100).
/// If `output_path` is NULL, overwrites `image_path` (which must then have a .jpg/.jpeg extension).
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
#[ffi_export]
pub fn to_jpg(
    image_path: Option<char_p::Ref<'_>>,
    output_path: Option<char_p::Ref<'_>>,
    image_quality: u8,
    arena: Option<&mut FfiArena>,
) -> u8 {
    let mut arena_opt = arena;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<(), (FfiErrorCode, String)> = (|| {
            let img_p = if let Some(p) = image_path {
                p.to_str()
            } else {
                return Err((FfiErrorCode::InvalidArg, "Missing image path".to_string()));
            };

            let out_p = if let Some(p) = output_path {
                p.to_str()
            } else {
                img_p
            };

            ops::to_jpg::ToJpg {
                quality: image_quality,
            }
            .apply(Path::new(img_p), Path::new(out_p))
            .map_err(|e| {
                let code = match e {
                    io::IoError::Read => FfiErrorCode::Io,
                    io::IoError::Decode => FfiErrorCode::Decode,
                    io::IoError::UnsupportedFormat | io::IoError::Encode => FfiErrorCode::Encode,
                    io::IoError::Write => FfiErrorCode::Io,
                };
                (code, "Failed to convert to JPEG".to_string())
            })?;

            Ok(())
        })();
        inner
    }));

    match result {
        Ok(Ok(())) => FfiErrorCode::Success as u8,
        Ok(Err((code, msg))) => write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code,
        Err(payload) => handle_panic(arena_opt, payload),
    }
}

/// Resizes an image to exact `width × height` dimensions.
///
/// `filter`: 0 = Nearest, 1 = Triangle (bilinear, default), 2 = `CatmullRom`, 3 = Lanczos3.
/// If `output_path` is NULL, overwrites `image_path`.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
#[ffi_export]
pub fn resize(
    image_path: Option<char_p::Ref<'_>>,
    output_path: Option<char_p::Ref<'_>>,
    width: u32,
    height: u32,
    filter: u8,
    image_quality: u8,
    arena: Option<&mut FfiArena>,
) -> u8 {
    let mut arena_opt = arena;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<(), (FfiErrorCode, String)> = (|| {
            let img_p = if let Some(p) = image_path {
                p.to_str()
            } else {
                return Err((FfiErrorCode::InvalidArg, "Missing image path".to_string()));
            };

            let out_p = if let Some(p) = output_path {
                p.to_str()
            } else {
                img_p
            };

            let resize_filter = ops::resize::ResizeFilter::from_wire(filter).ok_or_else(|| {
                (
                    FfiErrorCode::InvalidArg,
                    format!("Invalid resize filter: {filter}"),
                )
            })?;

            ops::resize::Resize {
                width,
                height,
                filter: resize_filter,
                quality: image_quality,
            }
            .apply(Path::new(img_p), Path::new(out_p))
            .map_err(|e| match e {
                ops::resize::ResizeError::ZeroDimension => (
                    FfiErrorCode::InvalidArg,
                    "Width and height must be > 0".to_string(),
                ),
                ops::resize::ResizeError::Io(io_err) => {
                    let code = match io_err {
                        io::IoError::Read => FfiErrorCode::Io,
                        io::IoError::Decode => FfiErrorCode::Decode,
                        io::IoError::UnsupportedFormat | io::IoError::Encode => {
                            FfiErrorCode::Encode
                        }
                        io::IoError::Write => FfiErrorCode::Io,
                    };
                    (code, "Failed to resize image".to_string())
                }
            })?;

            Ok(())
        })();
        inner
    }));

    match result {
        Ok(Ok(())) => FfiErrorCode::Success as u8,
        Ok(Err((code, msg))) => write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code,
        Err(payload) => handle_panic(arena_opt, payload),
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod merge_tests {
    use super::*;

    fn tiny_red_png() -> Vec<u8> {
        use image::{ImageEncoder, RgbaImage};
        let img = RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 255]));
        let mut buf = std::io::Cursor::new(Vec::new());
        image::codecs::png::PngEncoder::new(&mut buf)
            .write_image(img.as_raw(), 4, 4, image::ExtendedColorType::Rgba8)
            .unwrap();
        buf.into_inner()
    }

    #[test]
    fn null_arena_handled_in_merge() {
        let _fg_bytes = tiny_red_png();
        let mut out = Default::default();

        let status = merge(None, (&[] as &[u8]).into(), 0, 0, 1, 90, None, &mut out);
        // It should return InvalidArg (2) because background_path is None.
        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }

    #[test]
    #[cfg(not(miri))]
    fn merge_rejects_null_foreground_bytes() {
        let path_str = "fake.jpg";
        let path = safer_ffi::char_p::new(path_str);
        let mut arena = FfiArena {
            text_buf: std::ptr::null(),
            text_len: 0,
            image_buf: std::ptr::null(),
            image_len: 0,
            error: vec![0u8; 100].into_boxed_slice().into(),
        };
        let mut out = Default::default();

        let status = merge(
            Some(path.as_ref()),
            (&[] as &[u8]).into(),
            0,
            0,
            0,
            90,
            Some(&mut arena),
            &mut out,
        );
        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }

    #[test]
    #[cfg(not(miri))]
    fn merge_rejects_empty_foreground_bytes() {
        let path_str = "tests/fixtures/orientation/exif_1.jpg";
        let path = safer_ffi::char_p::new(path_str);
        let mut out = Default::default();

        let status = merge(
            Some(path.as_ref()),
            (&[] as &[u8]).into(),
            0,
            0,
            1,
            90,
            None,
            &mut out,
        );

        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }

    #[test]
    #[cfg(not(miri))]
    fn merge_handles_invalid_png_foreground() {
        let path_str = "tests/fixtures/orientation/exif_1.jpg";
        let path = safer_ffi::char_p::new(path_str);
        let fg = [1u8, 2, 3, 4, 5]; // invalid PNG
        let mut out = Default::default();

        let status = merge(
            Some(path.as_ref()),
            (&fg as &[u8]).into(),
            0,
            0,
            0,
            90,
            None,
            &mut out,
        );

        assert_eq!(status, FfiErrorCode::Decode as u8);
    }

    #[test]
    #[allow(unsafe_code)]
    fn draw_elements_propagates_error_to_arena() {
        let mut arena = FfiArena {
            text_buf: std::ptr::null(),
            text_len: 0,
            image_buf: std::ptr::null(),
            image_len: 0,
            error: vec![0u8; 100].into_boxed_slice().into(),
        };

        // Missing image path should trigger InvalidArg and write to arena.
        let status = unsafe {
            draw_elements(
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                0,
                90,
                &raw mut arena,
            )
        };

        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
        let msg = unsafe { std::ffi::CStr::from_ptr(arena.error.as_ptr().cast()) };
        assert!(
            msg.to_str().unwrap().contains("Missing image path"),
            "Expected 'Missing image path' in arena, got: {:?}",
            msg
        );
    }

    #[test]
    fn test_handle_panic_fallback() {
        let payload = Box::new(42i32); // Non-string payload
        let code = handle_panic(None, payload);
        assert_eq!(code, FfiErrorCode::Panic as u8);
    }
}

#[cfg(test)]
mod polygon_tests {
    use super::*;

    #[test]
    fn degenerate_polygon_skipped() {
        let mut pixmap = Pixmap::new(10, 10).unwrap();
        let p = PolygonPayload::new(
            0.0,
            0.0,
            10.0,
            10.0,
            std::ptr::null(),
            2,
            0xFFFF0000,
            0,
            0,
            0,
            0,
        );
        let style = ShapeStyle {
            fill_color: Some(tiny_skia::Color::from_rgba8(255, 0, 0, 255)),
            outline_color: None,
            thickness: 0.0,
        };
        // Should return Ok(()) without doing anything
        assert!(draw_polygon_on_pixmap(&mut pixmap, &p, &style, 0.0, 0.0).is_ok());
    }

    #[test]
    fn empty_polygon_skipped() {
        let mut pixmap = Pixmap::new(10, 10).unwrap();
        let p = PolygonPayload::new(
            0.0,
            0.0,
            10.0,
            10.0,
            std::ptr::null(),
            0,
            0xFFFF0000,
            0,
            0,
            0,
            0,
        );
        let style = ShapeStyle {
            fill_color: Some(tiny_skia::Color::from_rgba8(255, 0, 0, 255)),
            outline_color: None,
            thickness: 0.0,
        };
        assert!(draw_polygon_on_pixmap(&mut pixmap, &p, &style, 0.0, 0.0).is_ok());
    }

    #[test]
    fn single_vertex_polygon_skipped() {
        let mut pixmap = Pixmap::new(10, 10).unwrap();
        let p = PolygonPayload::new(
            0.0,
            0.0,
            10.0,
            10.0,
            std::ptr::null(),
            1,
            0xFFFF0000,
            0,
            0,
            0,
            0,
        );
        let style = ShapeStyle {
            fill_color: Some(tiny_skia::Color::from_rgba8(255, 0, 0, 255)),
            outline_color: None,
            thickness: 0.0,
        };
        assert!(draw_polygon_on_pixmap(&mut pixmap, &p, &style, 0.0, 0.0).is_ok());
    }

    #[test]
    fn null_vertices_ptr_errors() {
        let mut pixmap = Pixmap::new(10, 10).unwrap();
        let p = PolygonPayload::new(
            0.0,
            0.0,
            10.0,
            10.0,
            std::ptr::null(),
            3,
            0xFFFF0000,
            0,
            0,
            0,
            0,
        );
        let style = ShapeStyle {
            fill_color: Some(tiny_skia::Color::from_rgba8(255, 0, 0, 255)),
            outline_color: None,
            thickness: 0.0,
        };
        let res = draw_polygon_on_pixmap(&mut pixmap, &p, &style, 0.0, 0.0);
        assert!(res.is_err());
        assert_eq!(res.unwrap_err().0, FfiErrorCode::InvalidArg);
    }

    #[test]
    #[cfg_attr(miri, ignore)] // tiny-skia uses SIMD intrinsics unsupported by Miri
    fn valid_polygon_renders() {
        let mut pixmap = Pixmap::new(10, 10).unwrap();
        let verts = [0.0, 0.0, 10.0, 0.0, 5.0, 10.0];
        let p = PolygonPayload::new(
            0.0,
            0.0,
            10.0,
            10.0,
            verts.as_ptr(),
            3,
            0xFFFF0000,
            0,
            0,
            0,
            0,
        );
        let style = ShapeStyle {
            fill_color: Some(tiny_skia::Color::from_rgba8(255, 0, 0, 255)),
            outline_color: None,
            thickness: 0.0,
        };
        assert!(draw_polygon_on_pixmap(&mut pixmap, &p, &style, 0.0, 0.0).is_ok());
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod extra_coverage_tests {
    use super::*;

    #[test]
    fn handle_panic_string_payload() {
        let payload: Box<dyn std::any::Any + Send> = Box::new(String::from("string panic"));
        let code = handle_panic(None, payload);
        assert_eq!(code, FfiErrorCode::Panic as u8);
    }

    #[test]
    fn handle_panic_static_str_payload() {
        let payload: Box<dyn std::any::Any + Send> = Box::new("static str panic");
        let code = handle_panic(None, payload);
        assert_eq!(code, FfiErrorCode::Panic as u8);
    }

    // NOTE: This test exists purely for coverage of the Surface enum transition branches
    // and variant conversions, rather than verifying deep structural invariants.
    #[test]
    #[cfg(not(miri))]
    fn surface_rgba_to_pixmap_round_trip() {
        use image::RgbaImage;
        let img = RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 255]));
        let mut surface = Surface::Rgba(img);
        // Exercise the Rgba -> Pixmap branch in as_pixmap.
        let _ = surface.as_pixmap();
        // Exercise the Pixmap -> Rgba branch in into_rgba.
        let result = surface.into_rgba();
        assert_eq!(result.width(), 4);
        assert_eq!(result.height(), 4);
        assert_eq!(result.get_pixel(0, 0).0[0], 255, "red channel preserved");
    }

    // NOTE: This test exists purely for coverage of the Surface enum transition branches
    // and variant conversions, rather than verifying deep structural invariants.
    #[test]
    #[cfg(not(miri))]
    fn surface_pixmap_as_rgba_branch() {
        use image::RgbaImage;
        let img = RgbaImage::from_pixel(4, 4, image::Rgba([0, 255, 0, 255]));
        let mut surface = Surface::Rgba(img);
        // Force Rgba -> Pixmap so the variant is Pixmap.
        let _ = surface.as_pixmap();
        // Now call as_rgba on the Pixmap variant to cover that branch.
        let rgba = surface.as_rgba();
        assert_eq!(rgba.width(), 4);
        assert_eq!(rgba.height(), 4);
    }

    #[test]
    fn element_text_bounds_error() {
        // offset=10, len=5 -> end=15 > buf.len()=4.
        let p = TextPayload::new(0.0, 0.0, 12.0, 0, 0, 10, 5);
        let buf = b"hi!!";
        let result = element_text(&p, buf);
        assert!(result.is_err(), "out-of-bounds slice should return Err");
    }

    #[test]
    fn element_text_utf8_error() {
        // text_offset=0, text_len=3, buf is invalid UTF-8.
        let p = TextPayload::new(0.0, 0.0, 12.0, 0, 0, 0, 3);
        let buf: &[u8] = &[0xFF, 0xFE, 0xFD];
        let result = element_text(&p, buf);
        assert!(result.is_err(), "invalid UTF-8 should return Err");
    }

    #[test]
    fn element_text_success() {
        let p = TextPayload::new(0.0, 0.0, 12.0, 0, 0, 0, 5);
        let buf = b"hello world";
        let result = element_text(&p, buf);
        assert_eq!(result.unwrap(), "hello");
    }

    #[test]
    #[allow(unsafe_code)]
    fn draw_elements_missing_elements_ptr_errors() {
        let img_path = std::ffi::CString::new("nonexistent.png").unwrap();
        let out_path = std::ffi::CString::new("out.png").unwrap();
        let status = unsafe {
            draw_elements(
                img_path.as_ptr(),
                out_path.as_ptr(),
                std::ptr::null(),
                std::ptr::null(), // null elements_ptr with count > 0
                3,                // elements_count = 3 with null ptr -> InvalidArg
                90,
                std::ptr::null_mut(),
            )
        };
        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }
}
