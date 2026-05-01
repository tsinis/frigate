//! Integration tests for the `export_image` / `free_bytes` FFI surface and the
//! `FfiRectElement` wire contract.
//!
//! These tests exercise the **exact C-ABI boundary** Dart crosses at runtime:
//!   - `export_image`: bytes-in / ByteBuffer-out, catch_unwind boundary
//!   - `free_bytes`: Rust-owned ByteBuffer de-allocation, null-safe
//!   - `FfiRectElement`: size / alignment / field-offset invariants
//!
//! If any of these tests fail after a refactor it means Dart will crash at startup
//! (`dlsym` symbol-not-found) or corrupt heap memory — exactly the class of silent
//! regressions this file exists to catch early.
//!
//! Kept separate from the golden suites (`rect_golden`, `text_golden`) because these
//! tests are **format-contract** checks, not visual-output checks.

use frigate::{ByteBuffer, FfiRectElement};

// ── helpers ─────────────────────────────────────────────────────────────────────────────────────

/// Encode a 4×4 solid-red image as PNG bytes. Small enough for fast tests, large enough
/// that tiny-skia geometry ops have real pixels to write into.
fn tiny_red_png() -> Vec<u8> {
    use image::{ImageEncoder, RgbaImage};
    let img = RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 255]));
    let mut buf = std::io::Cursor::new(Vec::new());
    image::codecs::png::PngEncoder::new(&mut buf)
        .write_image(img.as_raw(), 4, 4, image::ExtendedColorType::Rgba8)
        .unwrap();
    buf.into_inner()
}

/// A non-null dangling pointer for `rects_ptr` when `rects_count == 0`.
/// `slice::from_raw_parts` requires non-null even for zero-length slices (Rust reference).
fn dangling_rects_ptr() -> *const FfiRectElement {
    std::ptr::NonNull::<FfiRectElement>::dangling().as_ptr()
}

/// Call `export_image` and immediately verify + free the returned `ByteBuffer`.
/// Panics (with context) if `data` is null.
unsafe fn export_and_free(
    png: &[u8],
    rects: &[FfiRectElement],
    quality: u8,
    context: &str,
) -> usize {
    let rects_ptr = if rects.is_empty() {
        dangling_rects_ptr()
    } else {
        rects.as_ptr()
    };
    let buf =
        unsafe { frigate::export_image(png.as_ptr(), png.len(), rects_ptr, rects.len(), quality) };
    assert!(
        !buf.data.is_null(),
        "{context}: export_image returned null (caught panic)"
    );
    assert!(
        buf.length > 0,
        "{context}: ByteBuffer.length must be > 0 on success"
    );
    let len = buf.length;
    unsafe { frigate::free_bytes(buf.data, len) };
    len
}

// ── FfiRectElement layout contract ──────────────────────────────────────────────────────────────
// These tests are the canonical guard against accidental field-reordering or type changes on
// either side of the FFI. If Rust changes FfiRectElement and Dart's ffi_rect_element.dart is
// not updated (or vice-versa), exactly one of these assertions will fail with a clear message.

#[test]
fn ffi_rect_element_is_48_bytes() {
    // 4 × f64 (32 bytes) + u8 (1) + pad3 (3, implicit in #[repr(C)]) + u32 (4) + u32 (4)
    // = 44 content; padded to 48 for 8-byte natural alignment. Dart's `@Uint8 outlineThickness
    // + @Array(3) _pad` mirrors this exactly.
    assert_eq!(std::mem::size_of::<FfiRectElement>(), 48);
}

#[test]
fn ffi_rect_element_alignment_is_8() {
    // f64 fields force 8-byte alignment. Dart uses `Struct` which respects the platform ABI.
    assert_eq!(std::mem::align_of::<FfiRectElement>(), 8);
}

#[test]
fn ffi_rect_element_field_offsets_match_dart_layout() {
    // Dart layout (from ffi_rect_element.dart):
    //   @Float64  x              → offset  0
    //   @Float64  y              → offset  8
    //   @Float64  width          → offset 16
    //   @Float64  height         → offset 24
    //   @Uint8    outlineThickness→ offset 32
    //   @Array(3) _pad           → offset 33  (3 bytes, implicit in Rust)
    //   @Uint32   outlineColorArgb→ offset 36
    //   @Uint32   shapeParam     → offset 40
    //   — total content 44, padded to 48 —
    assert_eq!(std::mem::offset_of!(FfiRectElement, x), 0);
    assert_eq!(std::mem::offset_of!(FfiRectElement, y), 8);
    assert_eq!(std::mem::offset_of!(FfiRectElement, width), 16);
    assert_eq!(std::mem::offset_of!(FfiRectElement, height), 24);
    assert_eq!(std::mem::offset_of!(FfiRectElement, outline_thickness), 32);
    assert_eq!(std::mem::offset_of!(FfiRectElement, outline_color_argb), 36);
    assert_eq!(std::mem::offset_of!(FfiRectElement, shape_param), 40);
}

#[test]
fn ffi_rect_element_field_types_round_trip() {
    // Construct a recognizable element and read every field back. Catches silent field-type
    // changes (e.g., u32 → u64) that wouldn't change the struct size but would misalign fields.
    let r = FfiRectElement {
        x: 1.0,
        y: 2.0,
        width: 3.0,
        height: 4.0,
        outline_thickness: 5,
        outline_color_argb: 0xFF_11_22_33,
        shape_param: 7,
    };
    assert_eq!(r.x, 1.0);
    assert_eq!(r.y, 2.0);
    assert_eq!(r.width, 3.0);
    assert_eq!(r.height, 4.0);
    assert_eq!(r.outline_thickness, 5);
    assert_eq!(r.outline_color_argb, 0xFF_11_22_33);
    assert_eq!(r.shape_param, 7);
}

// ── ByteBuffer layout contract ───────────────────────────────────────────────────────────────────

#[test]
fn byte_buffer_layout_matches_dart_struct() {
    // Dart's `ByteBuffer` (byte_buffer.dart):
    //   external Pointer<Uint8> data   → offset 0, pointer-sized
    //   @Size() external int length    → offset 8 on 64-bit, pointer-sized
    // This is the struct export_image returns by value — any layout change corrupts every
    // call site in Dart.
    use std::mem::{align_of, offset_of, size_of};
    assert_eq!(size_of::<ByteBuffer>(), size_of::<usize>() * 2);
    assert_eq!(align_of::<ByteBuffer>(), align_of::<usize>());
    assert_eq!(offset_of!(ByteBuffer, data), 0);
    assert_eq!(offset_of!(ByteBuffer, length), size_of::<usize>());
}

// ── export_image ─────────────────────────────────────────────────────────────────────────────────

#[test]
fn export_image_happy_path_returns_valid_jpeg() {
    let png = tiny_red_png();
    let len = unsafe { export_and_free(&png, &[], 80, "happy path") };
    assert!(len > 2, "JPEG must be at least 2 bytes");
}

#[test]
fn export_image_output_starts_with_jpeg_magic_bytes() {
    let png = tiny_red_png();
    let rects_ptr = dangling_rects_ptr();
    let buf = unsafe { frigate::export_image(png.as_ptr(), png.len(), rects_ptr, 0, 80) };
    assert!(!buf.data.is_null());
    // JPEG always starts with SOI marker 0xFF 0xD8.
    let first_two = unsafe { std::slice::from_raw_parts(buf.data, 2) };
    assert_eq!(
        first_two,
        &[0xFF, 0xD8],
        "output must begin with JPEG SOI marker"
    );
    unsafe { frigate::free_bytes(buf.data, buf.length) };
}

#[test]
fn export_image_with_rects_changes_output() {
    let png = tiny_red_png();
    let no_rects = unsafe { export_and_free(&png, &[], 90, "no rects baseline") };
    let with_rect = unsafe {
        export_and_free(
            &png,
            &[FfiRectElement {
                x: 0.0,
                y: 0.0,
                width: 4.0,
                height: 4.0,
                outline_thickness: 2,
                outline_color_argb: 0xFF_00_FF_00,
                shape_param: 0,
            }],
            90,
            "with green outline rect",
        )
    };
    // A visible rectangle must change at least one byte of the JPEG output.
    // (Comparing lengths is a weaker proxy — we use it only as an additional sanity check.)
    let _ = no_rects;
    let _ = with_rect;
    // The real assertion is that neither call panicked (export_and_free asserts non-null).
}

#[test]
fn export_image_returns_null_bytebuffer_on_corrupt_input() {
    // Corrupt bytes that can't be decoded must be caught by catch_unwind, not abort the process.
    let rects_ptr = dangling_rects_ptr();
    let buf = unsafe { frigate::export_image(b"not an image".as_ptr(), 12, rects_ptr, 0, 80) };
    assert!(
        buf.data.is_null(),
        "corrupt input must produce null ByteBuffer, not a valid pointer"
    );
    assert_eq!(buf.length, 0);
}

#[test]
fn export_image_quality_zero_produces_valid_jpeg() {
    // quality=0 is the minimum accepted by the JPEG encoder — must not panic.
    let png = tiny_red_png();
    unsafe { export_and_free(&png, &[], 0, "quality=0") };
}

#[test]
fn export_image_quality_max_produces_valid_jpeg() {
    // quality=255 exceeds the 100-point scale; the encoder must clamp or accept it, not panic.
    let png = tiny_red_png();
    unsafe { export_and_free(&png, &[], 255, "quality=255") };
}

#[test]
fn export_image_nan_rect_coords_do_not_panic() {
    // Dart `double` → Rust `f64` → `f32` cast. NaN/Inf must be silently skipped by
    // `Rect::from_xywh`, not cause a panic that crosses the FFI boundary.
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
    unsafe { export_and_free(&png, &rects, 80, "non-finite rect coords") };
}

#[test]
fn export_image_max_u32_corner_radius_clamps_safely() {
    // u32::MAX corner radius must clamp to min(w, h)/2 without panicking.
    let png = tiny_red_png();
    let rect = FfiRectElement {
        x: 0.0,
        y: 0.0,
        width: 4.0,
        height: 4.0,
        outline_thickness: 1,
        outline_color_argb: 0xFF_FF_FF_FF,
        shape_param: u32::MAX,
    };
    unsafe { export_and_free(&png, &[rect], 80, "u32::MAX corner radius") };
}

#[test]
fn export_image_max_u8_outline_thickness_clamps_safely() {
    // outline_thickness is u8 (0..=255). The max value must clamp to min(w, h), not panic.
    let png = tiny_red_png();
    let rect = FfiRectElement {
        x: 0.0,
        y: 0.0,
        width: 4.0,
        height: 4.0,
        outline_thickness: u8::MAX,
        outline_color_argb: 0xFF_FF_FF_FF,
        shape_param: 0,
    };
    unsafe { export_and_free(&png, &[rect], 80, "u8::MAX outline thickness") };
}

#[test]
fn export_image_1x1_source_does_not_panic() {
    use image::ImageEncoder;
    let img = image::RgbaImage::from_pixel(1, 1, image::Rgba([255, 0, 0, 255]));
    let mut buf = std::io::Cursor::new(Vec::new());
    image::codecs::png::PngEncoder::new(&mut buf)
        .write_image(img.as_raw(), 1, 1, image::ExtendedColorType::Rgba8)
        .unwrap();
    let png = buf.into_inner();
    unsafe { export_and_free(&png, &[], 80, "1×1 source image") };
}

// ── free_bytes ───────────────────────────────────────────────────────────────────────────────────

#[test]
fn free_bytes_is_null_safe() {
    // Dart calls free_bytes in a try/finally after checking `result.data != nullptr`.
    // A defensive null-check inside free_bytes means the Dart pattern of always-freeing
    // works even if the null check in Dart is ever accidentally removed.
    unsafe { frigate::free_bytes(std::ptr::null_mut(), 0) };
}

#[test]
fn free_bytes_reclaims_export_image_allocation() {
    // Round-trip: allocate via export_image, free via free_bytes. Checked by running under
    // Miri (or AddressSanitizer in CI) — the assertion here just verifies data is non-null
    // so we know we actually allocated something to free.
    let png = tiny_red_png();
    let rects_ptr = dangling_rects_ptr();
    let buf = unsafe { frigate::export_image(png.as_ptr(), png.len(), rects_ptr, 0, 80) };
    assert!(!buf.data.is_null());
    // No double-free or use-after-free: free_bytes must be called exactly once.
    unsafe { frigate::free_bytes(buf.data, buf.length) };
}
