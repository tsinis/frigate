#![no_main]

use libfuzzer_sys::fuzz_target;
use std::ptr::NonNull;

fuzz_target!(|data: &[u8]| {
    // We fuzz the image export boundary with raw bytes
    if data.len() < 10 { return; }
    
    let quality = data[0];
    let img_bytes = &data[1..];
    
    let buf = frigate::export_image(
        NonNull::new(img_bytes.as_ptr() as *mut u8),
        img_bytes.len(),
        None,
        0,
        quality
    );
    
    if !buf.data.is_null() {
        frigate::free_bytes(NonNull::new(buf.data), buf.length);
    }
});
