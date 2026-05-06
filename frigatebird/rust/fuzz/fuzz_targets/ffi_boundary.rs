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

    // SAFETY: `as_ptr` on a `Vec` is guaranteed to return a non-null pointer,
    // even if the vector is empty, so `NonNull::new` is safe and will unwrap.
    // We create a `NonNull` only to pass a read-only pointer into `frigate::merge`.
    // The FFI boundary reconstructs a safe `&[u8]` using `slice::from_raw_parts`.
    // It does not mutate or retain the pointer after the function returns.
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
