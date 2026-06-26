use frigate::{ByteBuffer, FfiErrorCode, ImageInformation, io};
use std::path::Path;

#[test]
fn test_get_image_info_orientation() {
    let fixture_dir = Path::new("tests/fixtures/orientation");
    if !fixture_dir.exists() {
        panic!(
            "SETUP: required test fixtures missing: tests/fixtures/orientation. Run 'cargo run --example gen_fixtures' to generate them."
        );
    }

    let mut exercised_count = 0;
    for tag in 1..=8 {
        let path_str = format!("tests/fixtures/orientation/exif_{tag}.jpg");
        let path = Path::new(&path_str);
        if !path.exists() {
            continue;
        }
        exercised_count += 1;

        let c_path = safer_ffi::char_p::new(path_str.as_str());
        let mut info = ImageInformation {
            width: 0,
            height: 0,
            format: 0,
            orientation: 0,
            _pad: [0; 2],
        };

        let status = frigate::get_image_info(Some(c_path.as_ref()), None, &mut info);
        assert_eq!(status, FfiErrorCode::Success as u8);
        assert_eq!(info.orientation, tag);

        // Original image is 128x64 (landscape)
        // Tags 1-4: landscape (128x64)
        // Tags 5-8: portrait (64x128)
        if tag <= 4 {
            assert_eq!(info.width, 128);
            assert_eq!(info.height, 64);
        } else {
            assert_eq!(info.width, 64);
            assert_eq!(info.height, 128);
        }

        // Test read_image produces oriented pixels
        let img = io::read_image(path).unwrap();
        if tag <= 4 {
            assert_eq!(img.width(), 128);
            assert_eq!(img.height(), 64);
        } else {
            assert_eq!(img.width(), 64);
            assert_eq!(img.height(), 128);
        }
    }
    assert!(
        exercised_count > 0,
        "SETUP: no fixtures were exercised. Run 'cargo run --example gen_fixtures' to generate them."
    );
}

#[test]
fn oriented_bytes_bakes_in_exif_orientation() {
    let fixture_dir = Path::new("tests/fixtures/orientation");
    if !fixture_dir.exists() {
        panic!(
            "SETUP: required test fixtures missing: tests/fixtures/orientation. Run 'cargo run --example gen_fixtures' to generate them."
        );
    }

    // exif_6.jpg: 128×64 landscape, orientation tag 6 → decoded → 64×128 portrait pixels.
    let path_str = "tests/fixtures/orientation/exif_6.jpg";
    let c_path = safer_ffi::char_p::new(path_str);

    // PNG output (out_format = 0).
    let mut out_png = ByteBuffer::default();
    let status = frigate::oriented_bytes(Some(c_path.as_ref()), 0, 85, None, &mut out_png);
    assert_eq!(
        status,
        FfiErrorCode::Success as u8,
        "PNG oriented_bytes must succeed"
    );
    assert!(
        !out_png.as_slice().is_empty(),
        "PNG output must be non-empty"
    );

    // Verify PNG magic (8-byte signature: 0x89 'P' 'N' 'G' …).
    let bytes = out_png.as_slice();
    assert_eq!(bytes[0], 0x89, "PNG signature byte 0");
    assert_eq!(bytes[1], 0x50, "PNG signature byte 1 (P)");

    // Decode the returned bytes: orientation must be physically baked in, so the 128×64 landscape
    // source with tag 6 yields 64×128 portrait pixels (not the original 128×64).
    let decoded_png = image::load_from_memory(bytes).expect("PNG output must decode");
    assert_eq!(decoded_png.width(), 64, "PNG width: orientation baked in");
    assert_eq!(
        decoded_png.height(),
        128,
        "PNG height: orientation baked in"
    );
    drop(out_png); // releases Rust-owned Vec<u8>

    // JPEG output (out_format = 1).
    let c_path2 = safer_ffi::char_p::new(path_str);
    let mut out_jpg = ByteBuffer::default();
    let status2 = frigate::oriented_bytes(Some(c_path2.as_ref()), 1, 85, None, &mut out_jpg);
    assert_eq!(
        status2,
        FfiErrorCode::Success as u8,
        "JPEG oriented_bytes must succeed"
    );
    assert!(
        !out_jpg.as_slice().is_empty(),
        "JPEG output must be non-empty"
    );

    // Verify JPEG SOI marker (0xFF 0xD8).
    let jbytes = out_jpg.as_slice();
    assert_eq!(jbytes[0], 0xFF, "JPEG SOI marker byte 0");
    assert_eq!(jbytes[1], 0xD8, "JPEG SOI marker byte 1");

    // Same orientation contract for the JPEG branch: 64×128 portrait pixels.
    let decoded_jpg = image::load_from_memory(jbytes).expect("JPEG output must decode");
    assert_eq!(decoded_jpg.width(), 64, "JPEG width: orientation baked in");
    assert_eq!(
        decoded_jpg.height(),
        128,
        "JPEG height: orientation baked in"
    );
    drop(out_jpg);
}

#[test]
fn oriented_bytes_returns_error_for_null_path() {
    let mut out = ByteBuffer::default();
    let status = frigate::oriented_bytes(None, 0, 85, None, &mut out);
    assert_ne!(status, FfiErrorCode::Success as u8, "null path must fail");
    drop(out);
}

#[test]
fn oriented_bytes_returns_error_for_missing_file() {
    let c_path = safer_ffi::char_p::new("/no/such/file.jpg");
    let mut out = ByteBuffer::default();
    let status = frigate::oriented_bytes(Some(c_path.as_ref()), 0, 85, None, &mut out);
    assert_ne!(
        status,
        FfiErrorCode::Success as u8,
        "missing file must fail"
    );
    drop(out);
}
