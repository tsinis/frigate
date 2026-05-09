#![expect(unsafe_code, reason = "Integration tests exercise FFI boundary")]

use frigate::{FfiErrorCode, ImageInfo, get_image_info};
use safer_ffi::char_p;

#[test]
fn test_get_image_info_errors() {
    let mut info = ImageInfo {
        width: 0,
        height: 0,
        format: 0,
        orientation: 0,
        _pad: [0; 2],
    };

    // 1. Missing path
    let status = get_image_info(None, None, Some(&mut info));
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Missing output pointer
    let path = char_p::new("tests/fixtures/orientation/exif_1.jpg");
    let status = get_image_info(Some(path.as_ref()), None, None);
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 3. Non-existent file
    let bad_path = char_p::new("non_existent.jpg");
    let status = get_image_info(Some(bad_path.as_ref()), None, Some(&mut info));
    assert_eq!(status, FfiErrorCode::Io as u8);

    // 4. Not an image (use a text file if available or just a random file)
    let cargo_toml = char_p::new("Cargo.toml");
    let status = get_image_info(Some(cargo_toml.as_ref()), None, Some(&mut info));
    assert_eq!(status, FfiErrorCode::Decode as u8);
}

#[test]
fn test_get_image_info_clears_out_on_error() {
    let mut info = ImageInfo {
        width: 123,
        height: 456,
        format: 0,
        orientation: 6,
        _pad: [0; 2],
    };
    let bad_path = char_p::new("non_existent.jpg");
    let _ = get_image_info(Some(bad_path.as_ref()), None, Some(&mut info));
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
            None,
            None,
            None,
            std::ptr::null(),
            0,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Missing elements pointer when count > 0
    let path = char_p::new("tests/fixtures/orientation/exif_1.jpg");
    let status = unsafe {
        frigate::draw_elements(
            Some(path.as_ref()),
            None,
            None,
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
    let path = char_p::new("tests/fixtures/orientation/exif_1.jpg");
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
            Some(path.as_ref()),
            None,
            None, // Missing font path
            &raw const element,
            1,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Non-existent font file
    let bad_font = char_p::new("non_existent.ttf");
    let status = unsafe {
        frigate::draw_elements(
            Some(path.as_ref()),
            None,
            Some(bad_font.as_ref()),
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
            Some(path.as_ref()),
            None,
            Some(path.as_ref()), // Using image as font
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
    let status = frigate::merge(None, None, 0, 0, 0, 0, 90, None, None);
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 2. Missing background path
    let mut out = frigate::ByteBuffer {
        data: std::ptr::null_mut(),
        length: 0,
    };
    let status = frigate::merge(None, None, 0, 0, 0, 0, 90, None, Some(&mut out));
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 3. Missing foreground bytes
    let path = char_p::new("tests/fixtures/orientation/exif_1.jpg");
    let status = frigate::merge(
        Some(path.as_ref()),
        None,
        0,
        0,
        0,
        0,
        90,
        None,
        Some(&mut out),
    );
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);

    // 4. Decode failure background
    let fg_bytes = tiny_red_png();
    let fg_ptr = safer_ffi::ptr::NonNull::new(fg_bytes.as_ptr() as *mut u8).unwrap();
    let cargo_toml = char_p::new("Cargo.toml");
    let status = frigate::merge(
        Some(cargo_toml.as_ref()),
        Some(fg_ptr),
        fg_bytes.len(),
        0,
        0,
        0,
        90,
        None,
        Some(&mut out),
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
    let cargo_toml = char_p::new("Cargo.toml");
    // 1. Decode failure image
    let status = unsafe {
        frigate::draw_elements(
            Some(cargo_toml.as_ref()),
            None,
            None,
            std::ptr::null(),
            0,
            90,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, FfiErrorCode::Decode as u8);
}
