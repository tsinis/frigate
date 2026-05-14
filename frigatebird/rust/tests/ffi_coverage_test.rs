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
fn test_ffi_arena_drop_null() {
    frigate::ffi_arena_free(Box::new(FfiArena::default()).into()); // should not panic but is effectively doing nothing
}

#[test]
fn test_ffi_arena_drop_valid() {
    let arena = frigate::ffi_arena_create(100);
    frigate::ffi_arena_free(arena); // Should free error_buf and arena
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
