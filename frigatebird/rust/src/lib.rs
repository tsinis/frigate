#![deny(improper_ctypes_definitions, improper_ctypes)]

use safer_ffi::prelude::*;
use std::path::Path;
use std::slice;

use tiny_skia::{Paint, PathBuilder, Pixmap, Rect, Stroke, Transform};

mod canvas;
mod ffi;
mod ffi_element;
pub mod io;
pub mod text;

pub use ffi::{FfiArena, FfiError, FfiErrorCode, write_error_to_arena, write_panic_to_arena};
pub use ffi_element::{
    FfiElement, FfiPayload, OvalPayload, RectanglePayload, Shape, ShapeBuilder, TextPayload,
};

// Rust-side layout anchors: if these ever change, the Dart Struct declarations must be updated.
#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ByteBuffer {
    pub data: *mut u8,
    pub length: usize,
}

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

#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn sizeof_ffi_element() -> usize {
    core::mem::size_of::<FfiElement>()
}
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn sizeof_ffi_payload() -> usize {
    core::mem::size_of::<FfiPayload>()
}
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn sizeof_ffi_arena() -> usize {
    core::mem::size_of::<FfiArena>()
}
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn sizeof_ffi_error() -> usize {
    core::mem::size_of::<FfiError>()
}
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn sizeof_image_info() -> usize {
    core::mem::size_of::<ImageInformation>()
}

// --- Drop Hooks ---

/// Drop hook for `NativeFinalizer`.
///
/// # Safety
///
/// `arena` must be a valid pointer to an `FfiArena` allocated with the C allocator (e.g. `calloc`).
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ffi_arena_drop(arena: *mut FfiArena) {
    if arena.is_null() {
        return;
    }
    // SAFETY: Caller guarantees `arena` is valid.

    unsafe {
        let a = &mut *arena;
        if !a.error_buf.is_null() {
            libc::free(a.error_buf.cast());
        }
        // text_buf and image_buf are owned by Dart handles (FfiElementsHandle etc.)
        // and must be freed there, not here.
        libc::free(arena.cast());
    }
}

/// Drop hook for `NativeFinalizer` on `ByteBuffer`s.
///
/// # Safety
///
/// `buf` must be a valid pointer to a `ByteBuffer` allocated by Rust (e.g. via `merge`).
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn free_byte_buffer(buf: *mut ByteBuffer) {
    if buf.is_null() {
        return;
    }
    // SAFETY: Caller guarantees `buf` is valid.
    unsafe {
        let b = &mut *buf;
        if !b.data.is_null() && b.length > 0 {
            // ByteBuffer.data was allocated via `Box::into_raw(Vec::into_boxed_slice())`.
            let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(b.data, b.length));
        }
        // If the ByteBuffer struct itself was malloc'ed by Dart, we should free it too.
        // The Dart caller attaches a NativeFinalizer using `outPtr.cast()`, so we are freeing the `ByteBuffer` struct pointer.
        libc::free(buf.cast());
    }
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
            9 => FfiErrorCode::Unknown,
            _ => FfiErrorCode::Success,
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
pub unsafe extern "C" fn ffi_one_element(out: *mut FfiElement) {
    if !out.is_null() {
        unsafe { std::ptr::write_bytes(out, 0xAA, 1) };
    }
}

fn handle_panic(arena: Option<&mut FfiArena>, payload: Box<dyn std::any::Any + Send>) -> u8 {
    let msg = if let Some(s) = payload.downcast_ref::<&'static str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "panic with non-string payload".to_string()
    };
    write_panic_to_arena(arena, &msg).code
}

/// Returns oriented dimensions and metadata for an image without decoding full pixel data.
/// Returns a `u8` status code. Result info is written to `*out`.
///
/// # Safety
///
/// `path` must be a valid null-terminated C string. `arena` and `out` must be valid
/// pointers for the duration of the call.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn get_image_info(
    path: *const std::ffi::c_char,
    arena: *mut FfiArena,
    out: *mut ImageInformation,
) -> u8 {
    let mut arena_opt = unsafe { arena.as_mut() };

    if out.is_null() {
        return write_error_to_arena(
            arena_opt.as_deref_mut(),
            FfiErrorCode::InvalidArg,
            "Missing output ImageInformation pointer",
        )
        .code;
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<ImageInformation, (FfiErrorCode, String)> = (|| {
            let p_str = if path.is_null() {
                return Err((FfiErrorCode::InvalidArg, "Missing path".to_string()));
            } else {
                unsafe { std::ffi::CStr::from_ptr(path) }
                    .to_str()
                    .map_err(|_| (FfiErrorCode::Utf8, "Invalid UTF-8 in path".to_string()))?
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
            unsafe { *out = info };
            FfiErrorCode::Success as u8
        }
        Ok(Err((code, msg))) => {
            unsafe { *out = ImageInformation::default() };
            write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code
        }
        Err(payload) => {
            unsafe { *out = ImageInformation::default() };
            handle_panic(arena_opt, payload)
        }
    }
}

/// Bytes-in / path-in merge: composites `foreground_png` bytes over the image at `background_path`
/// and returns the result as a byte buffer owned by Rust.
///
/// Returns a `u8` status code (`FfiErrorCode` cast to `u8`). Result buffer is written to `*out`.
/// (Previously returned i32; now returns u8/FfiErrorCode.)
///
/// # Safety
///
/// `background_path` must be a valid null-terminated C string. `foreground_png_ptr` must
/// point to at least `foreground_png_len` bytes. `arena` and `out` must be valid
/// pointers for the duration of the call.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn merge(
    background_path: *const std::ffi::c_char,
    foreground_png_ptr: *const u8,
    foreground_png_len: usize,
    dx: i32,
    dy: i32,
    out_format: u8,
    image_quality: u8,
    arena: *mut FfiArena,
    out: *mut ByteBuffer,
) -> u8 {
    let mut arena_opt = unsafe { arena.as_mut() };

    if out.is_null() {
        return write_error_to_arena(
            arena_opt.as_deref_mut(),
            FfiErrorCode::InvalidArg,
            "Missing output buffer pointer",
        )
        .code;
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<Vec<u8>, (FfiErrorCode, String)> = (|| {
            let bg_p = if background_path.is_null() {
                return Err((
                    FfiErrorCode::InvalidArg,
                    "Missing background path".to_string(),
                ));
            } else {
                unsafe { std::ffi::CStr::from_ptr(background_path) }
                    .to_str()
                    .map_err(|_| {
                        (
                            FfiErrorCode::Utf8,
                            "Invalid UTF-8 in background path".to_string(),
                        )
                    })?
            };

            let fg_bytes = if !foreground_png_ptr.is_null() && foreground_png_len > 0 {
                // SAFETY: Pointer and length are checked for non-null/non-zero and provided by
                // the caller as a valid slice for the duration of the call.
                unsafe { slice::from_raw_parts(foreground_png_ptr, foreground_png_len) }
            } else {
                return Err((
                    FfiErrorCode::InvalidArg,
                    "Missing foreground bytes".to_string(),
                ));
            };

            let mut bg_img = io::read_image(Path::new(bg_p)).map_err(|_| {
                (
                    FfiErrorCode::Decode,
                    "Failed to decode background image".to_string(),
                )
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
            let boxed = bytes.into_boxed_slice();
            let length = boxed.len();
            // SAFETY: `out` was checked to be `Some` at the start of the function.
            // We're converting a Rust-owned Boxed slice to a raw pointer and writing it to the
            // caller-supplied output pointer. The caller is responsible for calling `free_bytes`.
            unsafe {
                *out = ByteBuffer {
                    data: Box::into_raw(boxed).cast::<u8>(),
                    length,
                };
            }
            FfiErrorCode::Success as u8
        }
        Ok(Err((code, msg))) => {
            unsafe {
                *out = ByteBuffer {
                    data: std::ptr::null_mut(),
                    length: 0,
                };
            }
            write_error_to_arena(arena_opt.as_deref_mut(), code, &msg).code
        }
        Err(payload) => {
            unsafe {
                *out = ByteBuffer {
                    data: std::ptr::null_mut(),
                    length: 0,
                };
            }
            handle_panic(arena_opt, payload)
        }
    }
}

/// Free a Rust-allocated byte buffer. Null-safe.
///
/// # Safety
///
/// `ptr` must be null or have been returned by a function that allocates memory for FFI.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        unsafe {
            let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len));
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
            unsafe { slice::from_raw_parts(elements_ptr, elements_count) }
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
                unsafe { slice::from_raw_parts(a.text_buf, a.text_len) }
            }
        };

        draw_elements_safe(
            img_p,
            out_p,
            font_path,
            elements,
            text_buffer,
            image_quality,
        )
    }));

    match result {
        Ok(Ok(())) => FfiErrorCode::Success as u8,
        Ok(Err((code, msg))) => write_error_to_arena(arena_opt, code, &msg).code,
        Err(payload) => handle_panic(arena_opt, payload),
    }
}

#[allow(unsafe_code)]
fn draw_elements_safe(
    image_path: &str,
    output_path: &str,
    font_path: *const std::ffi::c_char,
    elements: &[FfiElement],
    text_buffer: &[u8],
    image_quality: u8,
) -> Result<(), (FfiErrorCode, String)> {
    let needs_font = elements.iter().any(|e| matches!(e, FfiElement::Text(_)));
    let font_bytes_holder;
    let font: Option<ab_glyph::FontRef<'_>> = if needs_font {
        let f_path = if font_path.is_null() {
            return Err((FfiErrorCode::InvalidArg, "Missing font path".to_string()));
        } else {
            unsafe { std::ffi::CStr::from_ptr(font_path) }
                .to_str()
                .map_err(|_| (FfiErrorCode::Utf8, "Invalid UTF-8 in font path".to_string()))?
        };

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
        .map_err(|_| (FfiErrorCode::Decode, "Failed to decode image".to_string()))?
        .into_rgba8();

    let mut surface = Surface::Rgba(img);

    for element in elements {
        draw_element_on_surface(&mut surface, element, font.as_ref(), text_buffer)?;
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
    element: &FfiElement,
    font: Option<&ab_glyph::FontRef<'_>>,
    text_buffer: &[u8],
) -> Result<(), (FfiErrorCode, String)> {
    match element {
        FfiElement::Rectangle(p) => {
            let style: ShapeStyle = p.into();
            if style.paints_anything() {
                draw_rect_on_pixmap(surface.as_pixmap(), p, &style)?;
            }
        }
        FfiElement::Oval(p) => {
            let style: ShapeStyle = p.into();
            if style.paints_anything() {
                draw_oval_on_pixmap(surface.as_pixmap(), p, &style)?;
            }
        }
        FfiElement::Text(p) => {
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
    }
    Ok(())
}

pub fn draw_element(
    img: &mut image::RgbaImage,
    element: &FfiElement,
    font: Option<&ab_glyph::FontRef<'_>>,
    text_buffer: &[u8],
) {
    let mut surface = Surface::Rgba(std::mem::take(img));
    let _ = draw_element_on_surface(&mut surface, element, font, text_buffer);
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
) -> Result<(), (FfiErrorCode, String)> {
    let mut pb = PathBuilder::new();

    let x = p.x as f32;
    let y = p.y as f32;
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
        p.x,
        p.y,
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
) -> Result<(), (FfiErrorCode, String)> {
    let mut pb = PathBuilder::new();
    let x = p.x as f32;
    let y = p.y as f32;
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
        p.x,
        p.y,
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
    let paint = Paint {
        anti_alias: true,
        ..Default::default()
    };

    let ts = if rotation_deg != 0 {
        Transform::from_translate((x + width / 2.0) as f32, (y + height / 2.0) as f32)
            .pre_rotate(rotation_deg as f32)
            .pre_translate(-(x + width / 2.0) as f32, -(y + height / 2.0) as f32)
    } else {
        Transform::identity()
    };

    if let Some(color) = style.fill_color {
        let mut p = paint.clone();
        p.set_color(color);
        pixmap.fill_path(path, &p, tiny_skia::FillRule::Winding, ts, None);
    }

    if let Some(color) = style.outline_color {
        let mut p = paint.clone();
        p.set_color(color);
        let stroke = Stroke {
            width: style.thickness,
            ..Default::default()
        };
        pixmap.stroke_path(path, &p, &stroke, ts, None);
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
        let fg_bytes = tiny_red_png();
        let mut out = ByteBuffer {
            data: std::ptr::null_mut(),
            length: 0,
        };

        let status = unsafe {
            merge(
                std::ptr::null(),
                fg_bytes.as_ptr(),
                fg_bytes.len(),
                0,
                0,
                1,
                90,
                std::ptr::null_mut(),
                &raw mut out,
            )
        };
        // It should return InvalidArg (2) because background_path is None.
        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }

    #[test]
    #[cfg(not(miri))]
    fn merge_rejects_missing_output_buffer() {
        let fg_bytes = tiny_red_png();
        let path = std::ffi::CString::new("fake.jpg").unwrap();

        let status = unsafe {
            merge(
                path.as_ptr(),
                fg_bytes.as_ptr(),
                fg_bytes.len(),
                0,
                0,
                1,
                90,
                std::ptr::null_mut(),
                std::ptr::null_mut(), // Output buffer is missing!
            )
        };
        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }

    #[test]
    #[cfg(not(miri))]
    fn merge_rejects_null_foreground_bytes() {
        let path = std::ffi::CString::new("fake.jpg").unwrap();
        let mut arena = FfiArena {
            text_buf: std::ptr::null(),
            text_len: 0,
            image_buf: std::ptr::null(),
            image_len: 0,
            error_buf: std::ptr::null_mut(),
            error_cap: 0,
        };
        let mut out = ByteBuffer {
            data: std::ptr::null_mut(),
            length: 0,
        };

        let status = unsafe {
            merge(
                path.as_ptr(),
                std::ptr::null(),
                10,
                0,
                0,
                0,
                90,
                &raw mut arena,
                &raw mut out,
            )
        };
        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }

    #[test]
    #[cfg(not(miri))]
    fn merge_rejects_empty_foreground_bytes() {
        let path = std::ffi::CString::new("fake.jpg").unwrap();
        let mut fg = vec![0u8; 10];
        let mut out = ByteBuffer {
            data: std::ptr::null_mut(),
            length: 0,
        };

        let status = unsafe {
            merge(
                path.as_ptr(),
                fg.as_mut_ptr(),
                0,
                0,
                0,
                0,
                90,
                std::ptr::null_mut(),
                &raw mut out,
            )
        };
        assert_eq!(status, FfiErrorCode::InvalidArg as u8);
    }

    #[test]
    #[cfg(not(miri))]
    fn merge_handles_invalid_png_foreground() {
        let path = std::ffi::CString::new("fake.jpg").unwrap();
        let mut fg = vec![1, 2, 3, 4, 5]; // invalid PNG
        let mut out = ByteBuffer {
            data: std::ptr::null_mut(),
            length: 0,
        };

        let status = unsafe {
            merge(
                path.as_ptr(),
                fg.as_mut_ptr(),
                fg.len(),
                0,
                0,
                0,
                90,
                std::ptr::null_mut(),
                &raw mut out,
            )
        };
        // "fake.jpg" does not exist so read_image fails with Decode or Io error
        assert!(status != FfiErrorCode::Success as u8);
    }

    #[test]
    #[allow(unsafe_code)]
    fn draw_elements_propagates_error_to_arena() {
        let mut error_buf = [0u8; 256];
        let mut arena = FfiArena {
            text_buf: std::ptr::null(),
            text_len: 0,
            image_buf: std::ptr::null(),
            image_len: 0,
            error_buf: error_buf.as_mut_ptr(),
            error_cap: error_buf.len(),
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
        let msg = unsafe { std::ffi::CStr::from_ptr(error_buf.as_ptr().cast()) };
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
