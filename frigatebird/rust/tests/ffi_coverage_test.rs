#![allow(unsafe_code)]
use frigate::*;

#[test]
fn get_image_info_null_path() {
    let mut out = ImageInformation::default();
    let status = get_image_info(None, None, &mut out);
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn get_image_info_missing_path() {
    let path = safer_ffi::char_p::new("non_existent_file.jpg");
    let mut out = ImageInformation::default();
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 0].into_boxed_slice().into(),
    };
    let status = get_image_info(Some(path.as_ref()), Some(&mut arena), &mut out);
    assert_eq!(status, FfiErrorCode::Io as u8);
}

#[test]
fn get_image_info_truncated() {
    let mut tmp = std::env::temp_dir();
    tmp.push(format!(
        "frigate_truncated_{}_{}.jpg",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::write(&tmp, b"not an image").unwrap();

    let path = safer_ffi::char_p::new(tmp.to_str().unwrap());
    let mut out = ImageInformation::default();
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error: vec![0u8; 0].into_boxed_slice().into(),
    };
    let status = get_image_info(Some(path.as_ref()), Some(&mut arena), &mut out);
    assert_eq!(status, FfiErrorCode::Decode as u8);
    let _ = std::fs::remove_file(&tmp);
}

#[test]
fn get_image_info_exif_rotated() {
    for i in 1..=8 {
        let path_str = format!("../test/assets/paint_orient_{}.jpg", i);
        let path = safer_ffi::char_p::new(path_str.as_str());
        let mut out = ImageInformation::default();
        let status = get_image_info(Some(path.as_ref()), None, &mut out);
        assert_eq!(status, FfiErrorCode::Success as u8);

        // Base image is 725x1080
        if (5..=8).contains(&i) {
            assert_eq!(out.width, 1080);
            assert_eq!(out.height, 725);
        } else {
            assert_eq!(out.width, 725);
            assert_eq!(out.height, 1080);
        }
    }
}

#[test]
fn test_sizeof_oracles() {
    assert_eq!(sizeof_ffi_element(), std::mem::size_of::<FfiElement>());
    assert_eq!(sizeof_ffi_payload(), std::mem::size_of::<FfiPayload>());
    assert_eq!(sizeof_ffi_arena(), std::mem::size_of::<FfiArena>());
    assert_eq!(sizeof_ffi_error(), std::mem::size_of::<FfiError>());
    assert_eq!(sizeof_image_info(), std::mem::size_of::<ImageInformation>());
}

#[test]
fn test_ffi_arena_drop_default() {
    frigate::ffi_arena_free(Box::new(FfiArena::default()).into()); // should not panic but is effectively freeing a default heap arena
}

#[test]
fn test_ffi_arena_drop_valid() {
    let arena = frigate::ffi_arena_create(100);
    frigate::ffi_arena_free(arena); // Should free error and arena
}

#[test]
fn test_free_byte_buffer_empty() {
    free_byte_buffer(ByteBuffer::default()); // Should not panic
}

#[test]
fn test_free_byte_buffer_valid() {
    let data = vec![1u8, 2, 3].into_boxed_slice();
    let buf = ByteBuffer::from(data);
    free_byte_buffer(buf); // Should free data
}

#[test]
fn test_ffi_rotate_null_path() {
    let mut arena = FfiArena::default();
    let res = rotate(None, None, 1, 100, Some(&mut arena));
    assert_eq!(res, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn test_ffi_rotate_invalid_path() {
    let mut arena = FfiArena::default();
    let img = safer_ffi::char_p::new("invalid/path/that/does/not/exist.png");
    let res = rotate(Some(img.as_ref()), None, 1, 100, Some(&mut arena));
    assert_eq!(res, FfiErrorCode::Io as u8);
}

#[test]
fn test_ffi_to_jpg_null_path() {
    let mut arena = FfiArena::default();
    let res = to_jpg(None, None, 100, Some(&mut arena));
    assert_eq!(res, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn test_ffi_to_jpg_invalid_path() {
    let mut arena = FfiArena::default();
    let img = safer_ffi::char_p::new("invalid/path.png");
    let res = to_jpg(Some(img.as_ref()), None, 100, Some(&mut arena));
    assert_eq!(res, FfiErrorCode::Io as u8);
}

#[test]
fn test_ffi_resize_null_path() {
    let mut arena = FfiArena::default();
    let res = resize(None, None, 100, 100, 1, 100, Some(&mut arena));
    assert_eq!(res, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn test_ffi_resize_invalid_path() {
    let mut arena = FfiArena::default();
    let img = safer_ffi::char_p::new("invalid/path.png");
    let res = resize(Some(img.as_ref()), None, 100, 100, 1, 100, Some(&mut arena));
    assert_eq!(res, FfiErrorCode::Io as u8);
}

#[test]
fn test_ffi_resize_invalid_filter() {
    let mut arena = FfiArena::default();
    let img = safer_ffi::char_p::new("invalid/path.png");
    let res = resize(
        Some(img.as_ref()),
        None,
        100,
        100,
        99,
        100,
        Some(&mut arena),
    );
    assert_eq!(res, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn test_ffi_rotate_success() {
    let path = std::env::temp_dir().join("ffi_rotate.png");
    let img = image::RgbaImage::from_pixel(2, 2, image::Rgba([255, 0, 0, 255]));
    img.save(&path).unwrap();
    let p = safer_ffi::char_p::new(path.to_str().unwrap());
    let res = rotate(Some(p.as_ref()), None, 1, 100, None);
    assert_eq!(res, FfiErrorCode::Success as u8);
    std::fs::remove_file(&path).ok();
}

#[test]
fn test_ffi_to_jpg_success() {
    let path = std::env::temp_dir().join("ffi_to_jpg.png");
    let out = path.with_extension("jpg");
    let img = image::RgbaImage::from_pixel(2, 2, image::Rgba([255, 0, 0, 255]));
    img.save(&path).unwrap();
    let p_in = safer_ffi::char_p::new(path.to_str().unwrap());
    let p_out = safer_ffi::char_p::new(out.to_str().unwrap());
    let res = to_jpg(Some(p_in.as_ref()), Some(p_out.as_ref()), 100, None);
    assert_eq!(res, FfiErrorCode::Success as u8);
    assert!(out.exists());
    std::fs::remove_file(&path).ok();
    std::fs::remove_file(&out).ok();
}

#[test]
fn test_ffi_resize_success() {
    let path = std::env::temp_dir().join("ffi_resize.png");
    let img = image::RgbaImage::from_pixel(2, 2, image::Rgba([255, 0, 0, 255]));
    img.save(&path).unwrap();
    let p = safer_ffi::char_p::new(path.to_str().unwrap());
    let res = resize(Some(p.as_ref()), None, 1, 1, 0, 100, None);
    assert_eq!(res, FfiErrorCode::Success as u8);
    std::fs::remove_file(&path).ok();
}

#[test]
fn test_ffi_resize_zero_dimensions() {
    let path = std::env::temp_dir().join("ffi_resize_zero.png");
    let img = image::RgbaImage::from_pixel(2, 2, image::Rgba([255, 0, 0, 255]));
    img.save(&path).unwrap();
    let p = safer_ffi::char_p::new(path.to_str().unwrap());
    let mut arena = FfiArena::default();
    let res = resize(Some(p.as_ref()), None, 0, 0, 0, 100, Some(&mut arena));
    assert_eq!(res, FfiErrorCode::InvalidArg as u8);
    std::fs::remove_file(&path).ok();
}

/// Builds a truncated JPEG in a temp file and returns its path.
/// Encodes in-memory, then cuts to 60 % of the encoded length so the EOI is stripped.
fn write_truncated_jpeg(name: &str) -> std::path::PathBuf {
    let mut img = image::RgbaImage::new(64, 64);
    for (x, y, px) in img.enumerate_pixels_mut() {
        *px = image::Rgba([(x % 256) as u8, (y % 64) as u8, 128, 255]);
    }
    let (w, h) = img.dimensions();
    let rgb: Vec<u8> = img
        .as_raw()
        .chunks_exact(4)
        .flat_map(|c| [c[0], c[1], c[2]])
        .collect();
    let mut jpeg = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg, 85)
        .encode(&rgb, w, h, image::ExtendedColorType::Rgb8)
        .expect("encode must succeed");
    jpeg.truncate(jpeg.len() * 6 / 10);
    let path = std::env::temp_dir().join(name);
    std::fs::write(&path, &jpeg).unwrap();
    path
}

#[test]
fn test_ffi_to_jpg_truncated_input_returns_truncated_code() {
    let path = write_truncated_jpeg("ffi_to_jpg_truncated.jpg");
    let out = path.with_extension("out.jpg");
    let p_in = safer_ffi::char_p::new(path.to_str().unwrap());
    let p_out = safer_ffi::char_p::new(out.to_str().unwrap());
    let mut arena = FfiArena {
        error: vec![0u8; 512].into_boxed_slice().into(),
        ..FfiArena::default()
    };
    let res = to_jpg(
        Some(p_in.as_ref()),
        Some(p_out.as_ref()),
        100,
        Some(&mut arena),
    );
    assert_eq!(
        res,
        FfiErrorCode::Truncated as u8,
        "ffi_to_jpg must return Truncated for a torn JPEG, not silently produce a grey image"
    );
    // The error message must name the truncation cause so consumers can identify it as retryable.
    let msg = unsafe { std::ffi::CStr::from_ptr(arena.error.as_ptr().cast()) };
    let msg_str = msg.to_str().expect("arena error must be valid UTF-8");
    assert!(
        msg_str.contains("truncated") || msg_str.contains("EOI"),
        "ffi_to_jpg Truncated message must explain the cause, got: {msg_str:?}"
    );
    std::fs::remove_file(&path).ok();
}

#[test]
fn test_ffi_resize_truncated_input_returns_truncated_code() {
    let path = write_truncated_jpeg("ffi_resize_truncated.jpg");
    let p = safer_ffi::char_p::new(path.to_str().unwrap());
    let mut arena = FfiArena {
        error: vec![0u8; 512].into_boxed_slice().into(),
        ..FfiArena::default()
    };
    let res = resize(Some(p.as_ref()), None, 32, 32, 0, 100, Some(&mut arena));
    assert_eq!(
        res,
        FfiErrorCode::Truncated as u8,
        "ffi_resize must return Truncated for a torn JPEG, not silently produce a grey image"
    );
    let msg = unsafe { std::ffi::CStr::from_ptr(arena.error.as_ptr().cast()) };
    let msg_str = msg.to_str().expect("arena error must be valid UTF-8");
    assert!(
        msg_str.contains("truncated") || msg_str.contains("EOI"),
        "ffi_resize Truncated message must explain the cause, got: {msg_str:?}"
    );
    std::fs::remove_file(&path).ok();
}

#[cfg(feature = "ffi-test-helpers")]
#[test]
fn test_ffi_helpers() {
    let mut arena = FfiArena::default();
    let mut el = FfiElement::Rectangle(frigate::RectanglePayload::new(0.0, 0.0, 0.0, 0.0, 0));
    unsafe {
        frigate::ffi_zero_element(&raw mut el);
        frigate::ffi_fill_element_0xAA(&raw mut el);
        frigate::ffi_force_error(3, b"error".as_ptr(), 5, &raw mut arena);
        frigate::ffi_force_error(1, b"error".as_ptr(), 5, &raw mut arena);
        frigate::ffi_force_error(99, std::ptr::null(), 0, &raw mut arena);
        frigate::ffi_echo_element(&raw const el);
    }
}
