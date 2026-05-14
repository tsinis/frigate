#![expect(unsafe_code, reason = "Integration tests exercise FFI boundary")]

use frigate::{FfiErrorCode, ImageInformation, get_image_info};
use std::ffi::CString;

#[test]
fn test_get_image_info_errors() {
    let mut info = ImageInformation::default();

    // 1. Missing path
    let status = get_image_info(None, None, &mut info);
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 3. Non-existent file
    let bad_path = safer_ffi::char_p::new("non_existent.jpg");
    let status = get_image_info(Some(bad_path.as_ref()), None, &mut info);
    assert_eq!(status, FfiErrorCode::Io as u8);

    // 4. Not an image (use a text file if available or just a random file)
    let cargo_toml = safer_ffi::char_p::new("Cargo.toml");
    let status = get_image_info(Some(cargo_toml.as_ref()), None, &mut info);
    assert_eq!(status, FfiErrorCode::Decode as u8);
}

#[test]
fn test_get_image_info_clears_out_on_error() {
    let mut info = ImageInformation::default();
    let bad_path = safer_ffi::char_p::new("non_existent.jpg");
    let _ = get_image_info(Some(bad_path.as_ref()), None, &mut info);
    let def = ImageInformation::default();
    assert_eq!(info.width, def.width);
    assert_eq!(info.height, def.height);
    assert_eq!(info.format, def.format);
    assert_eq!(info.orientation, def.orientation);
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
    // 2. Missing background path
    let mut out = frigate::ByteBuffer::default();
    let status = frigate::merge(None, (&[] as &[u8]).into(), 0, 0, 0, 90, None, &mut out);
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 3. Missing foreground bytes
    let path_str = "tests/fixtures/orientation/exif_1.jpg";
    let path = safer_ffi::char_p::new(path_str);
    let status = frigate::merge(
        Some(path.as_ref()),
        (&[] as &[u8]).into(),
        0,
        0,
        0,
        0,
        None,
        &mut out,
    );

    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 4. Decode failure background
    let fg_bytes = tiny_red_png();
    let cargo_toml_str = "Cargo.toml";
    let cargo_toml = safer_ffi::char_p::new(cargo_toml_str);
    let status = frigate::merge(
        Some(cargo_toml.as_ref()),
        fg_bytes.as_slice().into(),
        0,
        0,
        0,
        90,
        None,
        &mut out,
    );
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

#[test]
fn test_merge_with_exif_rotated_and_truncated() {
    let mut out = frigate::ByteBuffer::default();
    let fg_bytes = tiny_red_png();

    // EXIF rotated
    let exif_path_str = "tests/fixtures/orientation/exif_6.jpg";
    let exif_path = safer_ffi::char_p::new(exif_path_str);
    let status = frigate::merge(
        Some(exif_path.as_ref()),
        fg_bytes.as_slice().into(),
        0,
        0,
        0,
        90,
        None,
        &mut out,
    );
    assert_eq!(status, frigate::FfiErrorCode::Success as u8);
    // free buffer
    frigate::free_byte_buffer(out);

    // Truncated (non-image)
    let bad_path_str = "Cargo.toml";
    let bad_path = safer_ffi::char_p::new(bad_path_str);
    let mut out = frigate::ByteBuffer::default();
    let status = frigate::merge(
        Some(bad_path.as_ref()),
        fg_bytes.as_slice().into(),
        0,
        0,
        0,
        90,
        None,
        &mut out,
    );
    assert_eq!(status, frigate::FfiErrorCode::Decode as u8);
}

#[test]
fn test_draw_elements_with_exif_rotated_and_truncated() {
    let out_path = std::ffi::CString::new("tests/assets/out_draw_elements.jpg").unwrap();
    let elements = [frigate::FfiElement::Rectangle(frigate::RectanglePayload {
        x: 0.0,
        y: 0.0,
        width: 10.0,
        height: 10.0,
        rotation_deg: 0,
        fill_color_argb: 0xFFFFFFFF,
        outline_color_argb: 0,
        outline_thickness: 0,
        blur: 0,
        corner_radius: 0,
    })];

    // EXIF rotated
    let exif_path = std::ffi::CString::new("tests/fixtures/orientation/exif_6.jpg").unwrap();
    let status = unsafe {
        frigate::draw_elements(
            exif_path.as_ptr(),
            out_path.as_ptr(),
            std::ptr::null(),
            elements.as_ptr(),
            elements.len(),
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, frigate::FfiErrorCode::Success as u8);

    // Truncated (non-image)
    let bad_path = std::ffi::CString::new("Cargo.toml").unwrap();
    let status = unsafe {
        frigate::draw_elements(
            bad_path.as_ptr(),
            out_path.as_ptr(),
            std::ptr::null(),
            elements.as_ptr(),
            elements.len(),
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, frigate::FfiErrorCode::Decode as u8);
}
