#![no_main]

use arbitrary::Arbitrary;
use frigate::{ByteBuffer, FfiArena};
use libfuzzer_sys::fuzz_target;

#[derive(Arbitrary, Debug)]
struct FuzzInput {
    fg_bytes: Vec<u8>,
    dx: i32,
    dy: i32,
    out_format: u8,
    image_quality: u8,
}

fuzz_target!(|input: FuzzInput| {
    let mut error_buf = [0u8; 256];
    let mut arena = FfiArena {
        text_buf: std::ptr::null(),
        text_len: 0,
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };

    let mut out_buffer = ByteBuffer {
        data: std::ptr::null_mut(),
        length: 0,
    };

    // SAFETY: Vec::as_ptr() is non-null even for empty Vecs, so safer_ffi::ptr::NonNull::new
    // on input.fg_bytes.as_ptr() is sound. We create this NonNull ptr only to pass it
    // into frigate::merge, which performs slice::from_raw_parts and does not mutate or
    // retain it. The empty-vec case is safe because the FFI boundary guards on length > 0.
    let ptr = safer_ffi::ptr::NonNull::new(input.fg_bytes.as_ptr() as *mut u8);

    unsafe {
        let _ = frigate::merge(
            None,
            ptr,
            input.fg_bytes.len(),
            input.dx,
            input.dy,
            input.out_format,
            input.image_quality,
            Some(&mut arena),
            Some(&mut out_buffer),
        );

        if !out_buffer.data.is_null() {
            frigate::free_bytes(out_buffer.data, out_buffer.length);
        }
    }
});
