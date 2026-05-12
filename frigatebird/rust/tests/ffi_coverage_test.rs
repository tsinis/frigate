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

    let path = CString::new(tmp.to_str().unwrap()).unwrap();
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
    let _ = std::fs::remove_file(&tmp);
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

#[test]
fn test_sizeof_oracles() {
    assert_eq!(sizeof_ffi_element(), std::mem::size_of::<FfiElement>());
    assert_eq!(sizeof_ffi_payload(), std::mem::size_of::<FfiPayload>());
    assert_eq!(sizeof_ffi_arena(), std::mem::size_of::<FfiArena>());
    assert_eq!(sizeof_ffi_error(), std::mem::size_of::<FfiError>());
    assert_eq!(sizeof_image_info(), std::mem::size_of::<ImageInformation>());
}

#[test]
fn test_ffi_arena_drop_null() {
    unsafe { ffi_arena_drop(std::ptr::null_mut()) }; // Should not panic
}

#[test]
fn test_ffi_arena_drop_valid() {
    unsafe {
        let arena = libc::calloc(1, std::mem::size_of::<FfiArena>()).cast::<FfiArena>();
        assert!(!arena.is_null());
        (*arena).error_buf = libc::calloc(1, 100).cast::<u8>();
        (*arena).error_cap = 100;

        ffi_arena_drop(arena); // Should free error_buf and arena
    }
}

#[test]
fn test_free_byte_buffer_null() {
    unsafe { free_byte_buffer(std::ptr::null_mut()) }; // Should not panic
}

#[test]
fn test_free_byte_buffer_valid() {
    unsafe {
        let buf = libc::calloc(1, std::mem::size_of::<ByteBuffer>()).cast::<ByteBuffer>();
        assert!(!buf.is_null());

        let data = vec![1u8, 2, 3].into_boxed_slice();
        (*buf).length = data.len();
        (*buf).data = Box::into_raw(data).cast::<u8>();
        free_byte_buffer(buf); // Should free data and buf
    }
}

#[test]
fn test_free_bytes_null() {
    unsafe { free_bytes(std::ptr::null_mut(), 0) }; // Should not panic
    unsafe { free_bytes(std::ptr::null_mut(), 10) }; // Should not panic
}

#[test]
fn test_free_bytes_valid() {
    unsafe {
        let data = vec![1u8, 2, 3].into_boxed_slice();
        let len = data.len();
        let ptr = Box::into_raw(data).cast::<u8>();
        free_bytes(ptr, len); // Should free data
    }
}
