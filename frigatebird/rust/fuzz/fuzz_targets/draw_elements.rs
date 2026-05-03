#![no_main]

use arbitrary::Arbitrary;
use frigate::{FfiArena, FfiElement, FfiResultUnit};
use libfuzzer_sys::fuzz_target;
use safer_ffi::char_p;
use std::path::Path;

#[derive(Arbitrary, Debug)]
struct FuzzInput {
    elements: Vec<FfiElement>,
    text_buffer: Vec<u8>,
    image_quality: u8,
}

fuzz_target!(|input: FuzzInput| {
    // We use a fixed temp path for fuzzing to avoid disk bloat,
    // but this means multiple fuzzers might collide if run in parallel.
    // For libFuzzer it's fine as it's single-threaded per process.
    let temp_dir = std::env::temp_dir();
    let image_path = temp_dir.join("fuzz_input.jpg");
    let output_path = temp_dir.join("fuzz_output.jpg");
    let font_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("tests")
        .join("assets")
        .join("RobotoMono-VariableFont_wght.ttf");

    // Create a dummy 1x1 JPEG if it doesn't exist
    if !image_path.exists() {
        let img = image::RgbaImage::new(1, 1);
        img.save(&image_path).ok();
    }

    let image_path_cs = char_p::new(image_path.to_str().unwrap());
    let output_path_cs = char_p::new(output_path.to_str().unwrap());
    let font_path_cs = char_p::new(font_path.to_str().unwrap());

    let mut error_buf = [0u8; 256];
    let mut arena = FfiArena {
        text_buf: input.text_buffer.as_ptr(),
        text_len: input.text_buffer.len(),
        image_buf: std::ptr::null(),
        image_len: 0,
        error_buf: error_buf.as_mut_ptr(),
        error_cap: error_buf.len(),
    };

    let mut out = FfiResultUnit::Ok(());

    unsafe {
        frigate::draw_elements(
            Some(image_path_cs.as_ref()),
            Some(output_path_cs.as_ref()),
            Some(font_path_cs.as_ref()),
            input.elements.as_ptr(),
            input.elements.len(),
            input.image_quality,
            &raw mut arena,
            &raw mut out,
        );
    }

    // Cleanup output
    std::fs::remove_file(output_path).ok();
});
