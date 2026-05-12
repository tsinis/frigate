#![allow(unsafe_code)]
use frigate::*;
use std::ffi::CString;

#[test]
fn get_image_info_null_path() {
    let mut out = ImageInformation::default();
    let status = unsafe { get_image_info(std::ptr::null(), std::ptr::null_mut(), &raw mut out) };
    assert_eq!(status, FfiErrorCode::InvalidArg as u8);
}

#[test]
fn get_image_info_missing_path() {
    let path = CString::new("non_existent_file.jpg").unwrap();
    let mut out = ImageInformation::default();
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: std::ptr::null_mut(),
        error_cap: 0,
    };
    let status = unsafe { get_image_info(path.as_ptr(), &raw mut arena, &raw mut out) };
    assert_eq!(status, FfiErrorCode::Io as u8);
}

#[test]
fn get_image_info_truncated() {
    let path = CString::new("../test/assets/truncated.jpg").unwrap();
    std::fs::write("../test/assets/truncated.jpg", b"not an image").unwrap();
    let mut out = ImageInformation::default();
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: std::ptr::null_mut(),
        error_cap: 0,
    };
    let status = unsafe { get_image_info(path.as_ptr(), &raw mut arena, &raw mut out) };
    assert_eq!(status, FfiErrorCode::Decode as u8);
    let _ = std::fs::remove_file("../test/assets/truncated.jpg");
}

#[test]
fn get_image_info_exif_rotated() {
    for i in 1..=8 {
        let path_str = format!("../test/assets/paint_orient_{}.jpg", i);
        let path = CString::new(path_str).unwrap();
        let mut out = ImageInformation::default();
        let status = unsafe { get_image_info(path.as_ptr(), std::ptr::null_mut(), &raw mut out) };
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
