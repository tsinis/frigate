use image::{DynamicImage, RgbaImage};
use std::fs::File;
use std::io::{Cursor, Write};

fn main() {
    let dir = "tests/fixtures/orientation";
    std::fs::create_dir_all(dir).unwrap();

    let img = RgbaImage::from_pixel(128, 64, image::Rgba([255, 0, 0, 255]));
    let mut jpeg_bytes = Vec::new();
    DynamicImage::ImageRgba8(img)
        .write_to(&mut Cursor::new(&mut jpeg_bytes), image::ImageFormat::Jpeg)
        .unwrap();

    for tag in 1..=8 {
        let mut out_bytes = Vec::new();
        // SOI (FF D8)
        out_bytes.extend_from_slice(&jpeg_bytes[0..2]);

        // APP1 (EXIF)
        let mut exif = Vec::new();
        exif.extend_from_slice(b"Exif\0\0");
        exif.extend_from_slice(b"MM\0*"); // Big Endian
        exif.extend_from_slice(&[0x00, 0x00, 0x00, 0x08]); // Offset to IFD0

        exif.extend_from_slice(&[0x00, 0x01]); // 1 entry
        exif.extend_from_slice(&[0x01, 0x12]); // Tag: Orientation
        exif.extend_from_slice(&[0x00, 0x03]); // Type: Short
        exif.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]); // Count: 1
        exif.extend_from_slice(&[0x00, tag as u8, 0x00, 0x00]); // Value
        exif.extend_from_slice(&[0x00, 0x00, 0x00, 0x00]); // Next IFD offset

        let app1_len = (exif.len() + 2) as u16;
        out_bytes.extend_from_slice(&[0xFF, 0xE1]);
        out_bytes.extend_from_slice(&app1_len.to_be_bytes());
        out_bytes.extend(exif);

        // Rest of JPEG (skip SOI)
        out_bytes.extend_from_slice(&jpeg_bytes[2..]);

        let path = format!("{}/exif_{}.jpg", dir, tag);
        let mut file = File::create(path).unwrap();
        file.write_all(&out_bytes).unwrap();
    }
    println!("Generated 8 EXIF orientation fixtures in {}", dir);
}
