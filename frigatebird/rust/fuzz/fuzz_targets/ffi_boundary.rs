#![no_main]

use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;

#[derive(Arbitrary, Debug)]
struct FuzzInput {
    quality: u8,
    rects: Vec<frigate::FfiRectElement>,
    img_bytes: Vec<u8>,
}

fuzz_target!(|input: FuzzInput| {
    let buf = unsafe {
        frigate::export_image(
            input.img_bytes.as_ptr(),
            input.img_bytes.len(),
            input.rects.as_ptr(),
            input.rects.len(),
            input.quality,
        )
    };

    if !buf.data.is_null() {
        unsafe { frigate::free_bytes(buf.data, buf.length) };
    }
});
