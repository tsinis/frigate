#![expect(unsafe_code, reason = "Integration tests exercise FFI boundary")]

use frigate::{FfiErrorCode, ImageInformation, get_image_info};
use std::ffi::CString;

#[test]
fn test_get_image_info_errors() {
    let mut info = ImageInformation {
        width: 0,
        height: 0,
        format: 0,
        orientation: 0,
        _pad: [0; 2],
    };

    // 1. Missing path
    let status = unsafe { get_image_info(std::ptr::null(), std::ptr::null_mut(), &raw mut info) };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Missing output pointer
    let path = CString::new("tests/fixtures/orientation/exif_1.jpg").unwrap();
    let status =
        unsafe { get_image_info(path.as_ptr(), std::ptr::null_mut(), std::ptr::null_mut()) };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 3. Non-existent file
    let bad_path = CString::new("non_existent.jpg").unwrap();
    let status = unsafe { get_image_info(bad_path.as_ptr(), std::ptr::null_mut(), &raw mut info) };
    assert_eq!(status, FfiErrorCode::Io as u8);

    // 4. Not an image (use a text file if available or just a random file)
    let cargo_toml = CString::new("Cargo.toml").unwrap();
    let status =
        unsafe { get_image_info(cargo_toml.as_ptr(), std::ptr::null_mut(), &raw mut info) };
    assert_eq!(status, FfiErrorCode::Decode as u8);
}

#[test]
fn test_get_image_info_clears_out_on_error() {
    let mut info = ImageInformation {
        width: 123,
        height: 456,
        format: 0,
        orientation: 6,
        _pad: [0; 2],
    };
    let bad_path = CString::new("non_existent.jpg").unwrap();
    let _ = unsafe { get_image_info(bad_path.as_ptr(), std::ptr::null_mut(), &raw mut info) };
    assert_eq!(info.width, 0);
    assert_eq!(info.height, 0);
    assert_eq!(info.format, 255);
    assert_eq!(info.orientation, 1);
}

#[test]
fn test_draw_elements_errors() {
    // 1. Missing image path
    let status = unsafe {
        frigate::draw_elements(
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Missing elements pointer when count > 0
    let path = CString::new("tests/fixtures/orientation/exif_1.jpg").unwrap();
    let status = unsafe {
        frigate::draw_elements(
            path.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            1,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn test_draw_elements_font_errors() {
    let path = CString::new("tests/fixtures/orientation/exif_1.jpg").unwrap();
    // 1. Missing font path when TEXT element is present
    let element = frigate::FfiElement::Text(frigate::TextPayload {
        x: 0.0,
        y: 0.0,
        height: 20.0,
        rotation_deg: 0,
        fill_color_argb: 0,
        blur: 0,
        font_id: 0,
        text_offset: 0,
        text_len: 0,
        _pad: [0; 3],
    });
    let status = unsafe {
        frigate::draw_elements(
            path.as_ptr(),
            std::ptr::null(),
            std::ptr::null(), // Missing font path
            &raw const element,
            1,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Non-existent font file
    let bad_font = CString::new("non_existent.ttf").unwrap();
    let status = unsafe {
        frigate::draw_elements(
            path.as_ptr(),
            std::ptr::null(),
            bad_font.as_ptr(),
            &raw const element,
            1,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Io as u8);

    // 3. Invalid font file (using a JPEG as font)
    let status = unsafe {
        frigate::draw_elements(
            path.as_ptr(),
            std::ptr::null(),
            path.as_ptr(), // Using image as font
            &raw const element,
            1,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Font as u8);
}

#[test]
fn test_merge_errors() {
    // 1. Missing output buffer
    let status = unsafe {
        frigate::merge(
            std::ptr::null(),
            std::ptr::null(),
            0,
            0,
            0,
            0,
            90,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Missing background path
    let mut out = frigate::ByteBuffer {
        data: std::ptr::null_mut(),
        length: 0,
    };
    let status = unsafe {
        frigate::merge(
            std::ptr::null(),
            std::ptr::null(),
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

    // 3. Missing foreground bytes
    let path = CString::new("tests/fixtures/orientation/exif_1.jpg").unwrap();
    let status = unsafe {
        frigate::merge(
            path.as_ptr(),
            std::ptr::null(),
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

    // 4. Decode failure background
    let fg_bytes = tiny_red_png();
    let cargo_toml = CString::new("Cargo.toml").unwrap();
    let status = unsafe {
        frigate::merge(
            cargo_toml.as_ptr(),
            fg_bytes.as_ptr(),
            fg_bytes.len(),
            0,
            0,
            0,
            90,
            std::ptr::null_mut(),
            &raw mut out,
        )
    };
    assert_eq!(status, FfiErrorCode::Decode as u8);
}

fn tiny_red_png() -> Vec<u8> {
    use image::{DynamicImage, RgbaImage};
    let img = RgbaImage::from_pixel(1, 1, image::Rgba([255, 0, 0, 255]));
    let mut buf = std::io::Cursor::new(Vec::new());
    DynamicImage::ImageRgba8(img)
        .write_to(&mut buf, image::ImageFormat::Png)
        .unwrap();
    buf.into_inner()
}

#[test]
fn test_draw_elements_more_errors() {
    let cargo_toml = CString::new("Cargo.toml").unwrap();
    // 1. Decode failure image
    let status = unsafe {
        frigate::draw_elements(
            cargo_toml.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Decode as u8);
}
