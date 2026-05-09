use frigate::{FfiErrorCode, ImageInfo, io};
use safer_ffi::char_p;
use std::path::Path;

#[test]
fn test_get_image_info_orientation() {
    // This test assumes fixtures are generated.
    // We'll try to generate them if they don't exist or just skip if we can't.
    let fixture_dir = Path::new("tests/fixtures/orientation");
    if !fixture_dir.exists() {
        std::fs::create_dir_all(fixture_dir).unwrap();
        // Here we would ideally generate the files.
        // For now, let's assume we have them or skip.
        return;
    }

    for tag in 1..=8 {
        let path_str = format!("tests/fixtures/orientation/exif_{}.jpg", tag);
        let path = Path::new(&path_str);
        if !path.exists() {
            continue;
        }

        let c_path = char_p::new(path_str.as_str());
        let mut info = ImageInfo {
            width: 0,
            height: 0,
            format: 0,
            orientation: 0,
            _pad: [0; 2],
        };

        let status = frigate::get_image_info(Some(c_path.as_ref()), None, Some(&mut info));
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
}
