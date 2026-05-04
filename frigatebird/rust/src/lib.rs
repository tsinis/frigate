#![deny(improper_ctypes_definitions, improper_ctypes)]

use safer_ffi::prelude::*;
use std::ffi::{CStr, c_char};
use std::path::Path;
use std::slice;

use tiny_skia::{Paint, PathBuilder, Pixmap, Rect, Stroke, Transform};

mod canvas;
mod ffi;
mod ffi_element;
pub mod io;
pub mod text;

pub use ffi::{
    FfiArena, FfiError, FfiErrorCode, FfiResultUnit, write_error_to_arena, write_panic_to_arena,
};
pub use ffi_element::{FfiElement, OvalPayload, RectanglePayload, TextPayload};

// Rust-side layout anchors: if these ever change, the Dart Struct declarations must be updated.
#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct FfiRectElement {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub outline_thickness: u8,
    pub outline_color_argb: u32,
    pub shape_param: u32,
}

const _: () = assert!(std::mem::size_of::<FfiRectElement>() == 48);

#[derive_ReprC]
#[repr(C)]
pub struct ByteBuffer {
    pub data: *mut u8,
    pub length: usize,
}

/// Bytes-in / path-in merge: composites `foreground_png` bytes over the image at `background_path`
/// and returns the result as a byte buffer owned by Rust.
///
/// Returns a `u8` status code. Result buffer is written to `*out`.
#[expect(unsafe_code, reason = "FFI entry point")]
#[unsafe(no_mangle)] // TODO!: Why not #[ffi_export]? It was working before!
pub unsafe extern "C" fn merge(
    background_path: *const c_char,
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

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let inner: Result<Vec<u8>, FfiError> = (|| {
            let bg_p = c_str_to_str(background_path, arena_opt.as_deref_mut(), "background path")?;
            let fg_bytes = if foreground_png_len == 0 || foreground_png_ptr.is_null() {
                return Err(write_error_to_arena(
                    arena_opt.as_deref_mut(),
                    FfiErrorCode::InvalidArg,
                    "Missing foreground bytes",
                ));
            } else {
                unsafe { slice::from_raw_parts(foreground_png_ptr, foreground_png_len) }
            };

            let mut bg_img = io::read_image(Path::new(bg_p)).map_err(|_| {
                write_error_to_arena(
                    arena_opt.as_deref_mut(),
                    FfiErrorCode::Decode,
                    "Failed to decode background image",
                )
            })?;

            let fg_img = image::load_from_memory(fg_bytes).map_err(|_| {
                write_error_to_arena(
                    arena_opt.as_deref_mut(),
                    FfiErrorCode::Decode,
                    "Failed to decode foreground image",
                )
            })?;

            image::imageops::overlay(&mut bg_img, &fg_img, dx as i64, dy as i64);

            let mut buf = std::io::Cursor::new(Vec::new());
            if out_format == 0 {
                // PNG
                bg_img
                    .write_to(&mut buf, image::ImageFormat::Png)
                    .map_err(|_| {
                        write_error_to_arena(
                            arena_opt.as_deref_mut(),
                            FfiErrorCode::Encode,
                            "Failed to encode PNG",
                        )
                    })?;
            } else {
                // JPEG
                let rgb_img = bg_img.into_rgb8();
                image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, image_quality)
                    .encode_image(&rgb_img)
                    .map_err(|_| {
                        write_error_to_arena(
                            arena_opt.as_deref_mut(),
                            FfiErrorCode::Encode,
                            "Failed to encode JPEG",
                        )
                    })?;
            }

            Ok(buf.into_inner())
        })();
        inner
    }));

    match result {
        Ok(Ok(bytes)) => {
            let boxed = bytes.into_boxed_slice();
            let length = boxed.len();
            unsafe {
                out.write(ByteBuffer {
                    data: Box::into_raw(boxed).cast::<u8>(),
                    length,
                });
            }
            FfiErrorCode::Success as u8
        }
        Ok(Err(e)) => e.code,
        Err(payload) => {
            let msg = if let Some(s) = payload.downcast_ref::<&'static str>() {
                (*s).to_string()
            } else if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "panic with non-string payload".to_string()
            };
            write_panic_to_arena(arena_opt, &msg).code
        }
    }
}

/// Free a Rust-allocated byte buffer. Null-safe.
///
/// Named `free_bytes` to match the Dart `@Native` declaration and avoid shadowing the C stdlib
/// `free` symbol.
#[ffi_export]
pub fn free_bytes(ptr: Option<safer_ffi::ptr::NonNull<u8>>, len: usize) {
    if let Some(p) = ptr {
        #[expect(unsafe_code, reason = "FFI entry point")]
        unsafe {
            drop(Vec::from_raw_parts(p.as_ptr(), len, len))
        };
    }
}

#[cfg(any(test, feature = "ffi-echo"))]
#[expect(unsafe_code, reason = "FFI entry point")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ffi_echo_element(ptr: *const FfiElement) -> *const FfiElement {
    ptr
}

/// Unified render call: reads the image from `image_path`, composites all `FfiElement`s
/// (rectangles, text, future shapes), writes the result to `output_path`.
///
/// Returns a `u8` status code (0 for success, see `FfiStatus`).
///
/// # Safety
///
/// All pointer arguments must be valid for the duration of the call.
#[expect(
    unsafe_code,
    reason = "FFI entry point with payload enum limitation in safer_ffi"
)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn draw_elements(
    image_path: *const c_char,
    output_path: *const c_char,
    font_path: *const c_char,
    elements_ptr: *const FfiElement,
    elements_count: usize,
    image_quality: u8,
    arena: *mut FfiArena,
    out: *mut FfiResultUnit,
) {
    let mut arena_opt = unsafe { arena.as_mut() };

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let img_p = c_str_to_str(image_path, arena_opt.as_deref_mut(), "image path")?;
        let out_p = if output_path.is_null() {
            img_p
        } else {
            c_str_to_str(output_path, arena_opt.as_deref_mut(), "output path")?
        };

        let elements: &[FfiElement] = if elements_count == 0 {
            &[]
        } else {
            if elements_ptr.is_null() {
                return Err(FfiError::new(FfiErrorCode::InvalidArg));
            }
            unsafe { slice::from_raw_parts(elements_ptr, elements_count) }
        };

        let text_buffer: &[u8] = match arena_opt.as_deref() {
            None => &[],
            Some(a) if a.text_len == 0 => &[],
            Some(a) => {
                if a.text_buf.is_null() {
                    return Err(FfiError::new(FfiErrorCode::InvalidArg));
                }
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
            arena_opt.as_deref_mut(),
        )
    }));

    let ffi_result = match result {
        Ok(Ok(())) => FfiResultUnit::ok(0),
        Ok(Err(e)) => FfiResultUnit::err(e),
        Err(payload) => {
            let msg = if let Some(s) = payload.downcast_ref::<&'static str>() {
                (*s).to_string()
            } else if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "panic with non-string payload".to_string()
            };
            FfiResultUnit::err(write_panic_to_arena(arena_opt, &msg))
        }
    };
    if !out.is_null() {
        #[expect(unsafe_code, reason = "writing FFI result to caller-allocated pointer")]
        unsafe {
            out.write(ffi_result);
        }
    }
}

fn draw_elements_safe(
    image_path: &str,
    output_path: &str,
    font_path: *const c_char,
    elements: &[FfiElement],
    text_buffer: &[u8],
    image_quality: u8,
    mut arena: Option<&mut FfiArena>,
) -> Result<(), FfiError> {
    let needs_font = elements.iter().any(|e| matches!(e, FfiElement::Text(_)));
    let font_bytes_holder;
    let font: Option<ab_glyph::FontRef<'_>> = if needs_font {
        let f_path = if font_path.is_null() {
            return Err(write_error_to_arena(
                arena,
                FfiErrorCode::InvalidArg,
                "Missing font path",
            ));
        } else {
            c_str_to_str(font_path, arena.as_deref_mut(), "font path")?
        };

        font_bytes_holder = io::read_font(Path::new(f_path)).map_err(|_| {
            write_error_to_arena(
                arena.as_deref_mut(),
                FfiErrorCode::Io,
                "Failed to read font",
            )
        })?;
        Some(
            ab_glyph::FontRef::try_from_slice(&font_bytes_holder).map_err(|_| {
                write_error_to_arena(
                    arena.as_deref_mut(),
                    FfiErrorCode::Font,
                    "Failed to parse font",
                )
            })?,
        )
    } else {
        None
    };

    let img = io::read_image(Path::new(image_path))
        .map_err(|_| {
            write_error_to_arena(
                arena.as_deref_mut(),
                FfiErrorCode::Decode,
                "Failed to decode image",
            )
        })?
        .into_rgba8();

    let mut surface = Surface::Rgba(img);

    for element in elements {
        draw_element_on_surface(
            &mut surface,
            element,
            font.as_ref(),
            text_buffer,
            arena.as_deref_mut(),
        )?;
    }

    let img = surface.into_rgba();
    io::write_image(Path::new(output_path), &img, image_quality).map_err(|_| {
        write_error_to_arena(
            arena.as_deref_mut(),
            FfiErrorCode::Encode,
            "Failed to encode image",
        )
    })?;

    Ok(())
}

fn draw_element_on_surface(
    surface: &mut Surface,
    element: &FfiElement,
    font: Option<&ab_glyph::FontRef<'_>>,
    text_buffer: &[u8],
    arena: Option<&mut FfiArena>,
) -> Result<(), FfiError> {
    match element {
        FfiElement::Rectangle(p) => {
            let style: ShapeStyle = p.into();
            if style.paints_anything() {
                draw_rect_on_pixmap(surface.as_pixmap(), p, &style);
            }
        }
        FfiElement::Oval(p) => {
            let style: ShapeStyle = p.into();
            if style.paints_anything() {
                draw_oval_on_pixmap(surface.as_pixmap(), p, &style);
            }
        }
        FfiElement::Text(p) => {
            let text_slice = element_text(p, text_buffer).map_err(|e| match e {
                ElementTextError::Bounds => write_error_to_arena(
                    arena,
                    FfiErrorCode::InvalidArg,
                    "Text element slice out of bounds",
                ),
                ElementTextError::Utf8 => {
                    write_error_to_arena(arena, FfiErrorCode::Utf8, "Invalid UTF-8 in text element")
                }
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
    let _ = draw_element_on_surface(&mut surface, element, font, text_buffer, None);
    *img = surface.into_rgba();
}

fn c_str_to_str<'a>(
    ptr: *const c_char,
    arena: Option<&mut FfiArena>,
    field_name: &str,
) -> Result<&'a str, FfiError> {
    if ptr.is_null() {
        return Err(write_error_to_arena(
            arena,
            FfiErrorCode::InvalidArg,
            &format!("Missing {field_name}"),
        ));
    }
    // SAFETY: Caller guarantees ptr is a valid null-terminated C string for the duration of the
    // call. All callers (draw_elements, draw_elements_safe) satisfy this via the Dart FFI contract.
    #[expect(unsafe_code, reason = "converting caller-supplied C string pointer")]
    let cstr = unsafe { CStr::from_ptr(ptr) };
    cstr.to_str().map_err(|_| {
        write_error_to_arena(
            arena,
            FfiErrorCode::InvalidArg,
            &format!("Invalid UTF-8 in {field_name}"),
        )
    })
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
        if let Self::Pixmap(p) = self {
            *self = Self::Rgba(canvas::from_pixmap(p));
        }
        match self {
            Self::Rgba(img) => img,
            Self::Pixmap(_) => unreachable!(),
        }
    }

    fn as_pixmap(&mut self) -> &mut Pixmap {
        if let Self::Rgba(img) = self {
            *self = Self::Pixmap(canvas::to_pixmap(img));
        }
        match self {
            Self::Pixmap(p) => p,
            Self::Rgba(_) => unreachable!(),
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
    p: &TextPayload,
    text_str: &str,
) {
    let params = text::TextParams {
        text: text_str,
        x: p.x as f32,
        y: p.y as f32,
        font_size_px: p.height as f32,
        rotation_rad: (p.rotation_deg as f32).to_radians(),
        color: argb_to_rgba(p.fill_color_argb),
    };
    text::render_text_overlay(img, font, &params);
}

#[inline]
fn argb_unpack(argb: u32) -> [u8; 4] {
    [
        ((argb >> 16) & 0xFF) as u8,
        ((argb >> 8) & 0xFF) as u8,
        (argb & 0xFF) as u8,
        ((argb >> 24) & 0xFF) as u8,
    ]
}

#[inline]
fn argb_to_tiny_color(argb: u32) -> tiny_skia::Color {
    let [r, g, b, a] = argb_unpack(argb);
    tiny_skia::Color::from_rgba8(r, g, b, a)
}

fn argb_to_rgba(argb: u32) -> image::Rgba<u8> {
    image::Rgba(argb_unpack(argb))
}

#[inline]
fn argb_alpha(argb: u32) -> u8 {
    ((argb >> 24) & 0xFF) as u8
}

pub(crate) struct ShapeStyle {
    pub(crate) outline_thickness: u8,
    pub(crate) outline_color_argb: u32,
    pub(crate) fill_color_argb: u32,
    pub(crate) corner_radius_px: u32,
}

impl ShapeStyle {
    pub(crate) fn paints_anything(&self) -> bool {
        let has_outline = self.outline_thickness > 0 && argb_alpha(self.outline_color_argb) > 0;
        let has_fill = argb_alpha(self.fill_color_argb) > 0;
        has_outline || has_fill
    }
}

impl From<&RectanglePayload> for ShapeStyle {
    fn from(p: &RectanglePayload) -> Self {
        Self {
            outline_thickness: p.outline_thickness,
            outline_color_argb: p.outline_color_argb,
            fill_color_argb: p.fill_color_argb,
            corner_radius_px: u32::from(p.corner_radius),
        }
    }
}

impl From<&OvalPayload> for ShapeStyle {
    fn from(p: &OvalPayload) -> Self {
        Self {
            outline_thickness: p.outline_thickness,
            outline_color_argb: p.outline_color_argb,
            fill_color_argb: p.fill_color_argb,
            corner_radius_px: 0,
        }
    }
}

impl From<&FfiRectElement> for ShapeStyle {
    fn from(r: &FfiRectElement) -> Self {
        Self {
            outline_thickness: r.outline_thickness,
            outline_color_argb: r.outline_color_argb,
            fill_color_argb: 0,
            corner_radius_px: r.shape_param,
        }
    }
}

fn draw_rect_on_pixmap(pixmap: &mut Pixmap, p: &RectanglePayload, style: &ShapeStyle) {
    if p.width <= 0.0 || p.height <= 0.0 || !p.x.is_finite() || !p.y.is_finite() {
        return;
    }
    let Some(rect) = Rect::from_xywh(p.x as f32, p.y as f32, p.width as f32, p.height as f32)
    else {
        return;
    };
    let path = build_rect_path(rect, style.corner_radius_px);
    draw_shape_path(
        pixmap,
        &path,
        style,
        p.rotation_deg,
        p.x,
        p.y,
        p.width,
        p.height,
    );
}

fn draw_oval_on_pixmap(pixmap: &mut Pixmap, p: &OvalPayload, style: &ShapeStyle) {
    if p.width <= 0.0 || p.height <= 0.0 || !p.x.is_finite() || !p.y.is_finite() {
        return;
    }
    let Some(rect) = Rect::from_xywh(p.x as f32, p.y as f32, p.width as f32, p.height as f32)
    else {
        return;
    };
    let Some(path) = PathBuilder::from_oval(rect) else {
        return;
    };
    draw_shape_path(
        pixmap,
        &path,
        style,
        p.rotation_deg,
        p.x,
        p.y,
        p.width,
        p.height,
    );
}

fn draw_shape_path(
    pixmap: &mut Pixmap,
    path: &tiny_skia::Path,
    style: &ShapeStyle,
    rotation_deg: i32,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
) {
    let transform = if rotation_deg != 0 {
        Transform::from_rotate_at(
            rotation_deg as f32,
            (x + width / 2.0) as f32,
            (y + height / 2.0) as f32,
        )
    } else {
        Transform::identity()
    };

    let anti_alias = true;

    if argb_alpha(style.fill_color_argb) > 0 {
        let mut paint = Paint::default();
        paint.set_color(argb_to_tiny_color(style.fill_color_argb));
        paint.anti_alias = anti_alias;
        pixmap.fill_path(path, &paint, tiny_skia::FillRule::Winding, transform, None);
    }

    if style.outline_thickness > 0 && argb_alpha(style.outline_color_argb) > 0 {
        let mut paint = Paint::default();
        paint.set_color(argb_to_tiny_color(style.outline_color_argb));
        paint.anti_alias = anti_alias;
        let stroke = Stroke {
            width: style.outline_thickness as f32,
            ..Stroke::default()
        };
        pixmap.stroke_path(path, &paint, &stroke, transform, None);
    }
}

fn build_rect_path(rect: Rect, corner_radius_px: u32) -> tiny_skia::Path {
    if corner_radius_px == 0 {
        return PathBuilder::from_rect(rect);
    }
    let max_r = rect.width().min(rect.height()) * 0.5;
    let r = (corner_radius_px as f32).min(max_r);
    if r <= 0.0 {
        return PathBuilder::from_rect(rect);
    }
    const KAPPA: f32 = 0.552_284_8;
    let c = r * KAPPA;

    let l = rect.left();
    let t = rect.top();
    let ri = rect.right();
    let b = rect.bottom();

    let mut pb = PathBuilder::new();
    pb.move_to(l + r, t);
    pb.line_to(ri - r, t);
    pb.cubic_to(ri - r + c, t, ri, t + r - c, ri, t + r);
    pb.line_to(ri, b - r);
    pb.cubic_to(ri, b - r + c, ri - r + c, b, ri - r, b);
    pb.line_to(l + r, b);
    pb.cubic_to(l + r - c, b, l, b - r + c, l, b - r);
    pb.line_to(l, t + r);
    pb.cubic_to(l, t + r - c, l + r - c, t, l + r, t);
    pb.close();
    pb.finish().unwrap()
}

#[cfg(test)]
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

        #[expect(unsafe_code, reason = "FFI pointer write test")]
        unsafe {
            merge(
                std::ptr::null(),
                fg_bytes.as_ptr(),
                fg_bytes.len(),
                0,
                0,
                1,
                90,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            );
        }
    }
}
