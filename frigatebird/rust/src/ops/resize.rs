//! Image resizing with selectable filter algorithms.
//!
//! # Filter types
//!
//! | Wire value | Name        | Use case                              |
//! |------------|-------------|---------------------------------------|
//! | 0          | Nearest     | Pixel art, fastest, blocky            |
//! | 1          | Triangle    | Bilinear — good default, fast         |
//! | 2          | `CatmullRom`  | Bicubic — sharper than bilinear       |
//! | 3          | Lanczos3    | Highest quality, slowest              |
//!
//! Wire value 1 (Triangle/bilinear) is the default, matching `OpenCV` default interpolation.

use std::path::Path;

use image::imageops::FilterType;

use crate::io::{self, IoError};

/// Resizes an image to exact `width × height` dimensions.
pub struct Resize {
    pub width: u32,
    pub height: u32,
    /// Filter algorithm (wire encoding: 0..3).
    pub filter: ResizeFilter,
    /// JPEG quality for output (0..=100). Ignored for PNG output.
    pub quality: u8,
}

/// Resize interpolation filter, encoded as u8 for FFI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ResizeFilter {
    Nearest = 0,
    Triangle = 1,   // bilinear
    CatmullRom = 2, // bicubic
    Lanczos3 = 3,
}

impl ResizeFilter {
    /// Convert from wire value. Returns `None` for unknown values.
    pub fn from_wire(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Nearest),
            1 => Some(Self::Triangle),
            2 => Some(Self::CatmullRom),
            3 => Some(Self::Lanczos3),
            _ => None,
        }
    }

    /// Convert to `image` crate's `FilterType`.
    pub fn to_image_filter(self) -> FilterType {
        match self {
            Self::Nearest => FilterType::Nearest,
            Self::Triangle => FilterType::Triangle,
            Self::CatmullRom => FilterType::CatmullRom,
            Self::Lanczos3 => FilterType::Lanczos3,
        }
    }
}

/// Sentinel error for invalid resize dimensions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResizeError {
    /// Width or height is zero.
    ZeroDimension,
    /// I/O error from the underlying read/write layer.
    Io(IoError),
}

impl From<IoError> for ResizeError {
    fn from(e: IoError) -> Self {
        Self::Io(e)
    }
}

impl Resize {
    /// Read image from `input`, resize to `self.width × self.height`, write to `output`.
    pub fn apply(&self, input: &Path, output: &Path) -> Result<(), ResizeError> {
        if self.width == 0 || self.height == 0 {
            return Err(ResizeError::ZeroDimension);
        }

        let img = io::read_image(input)?;
        let resized = img.resize_exact(self.width, self.height, self.filter.to_image_filter());
        let rgba = resized.into_rgba8();
        io::write_image(output, &rgba, self.quality)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filter_from_wire_valid() {
        assert_eq!(ResizeFilter::from_wire(0), Some(ResizeFilter::Nearest));
        assert_eq!(ResizeFilter::from_wire(1), Some(ResizeFilter::Triangle));
        assert_eq!(ResizeFilter::from_wire(2), Some(ResizeFilter::CatmullRom));
        assert_eq!(ResizeFilter::from_wire(3), Some(ResizeFilter::Lanczos3));
    }

    #[test]
    fn filter_from_wire_invalid() {
        assert_eq!(ResizeFilter::from_wire(4), None);
        assert_eq!(ResizeFilter::from_wire(255), None);
    }

    #[cfg(not(miri))]
    mod fs_tests {
        use super::*;
        use image::{Rgba, RgbaImage};
        use std::path::PathBuf;

        fn tmp_path(name: &str) -> PathBuf {
            let path = std::env::temp_dir().join(name);
            let _ = std::fs::remove_file(&path);
            path
        }

        fn create_test_png(name: &str, w: u32, h: u32) -> PathBuf {
            let path = tmp_path(name);
            let mut img = RgbaImage::new(w, h);
            for y in 0..h {
                for x in 0..w {
                    let r = ((x * 255) / w.max(1)) as u8;
                    let g = ((y * 255) / h.max(1)) as u8;
                    img.put_pixel(x, y, Rgba([r, g, 128, 255]));
                }
            }
            img.save(&path).unwrap();
            path
        }

        #[test]
        fn resize_downscale_nearest() {
            let input = create_test_png("frigate_resize_down_nearest.png", 100, 100);
            let output = tmp_path("frigate_resize_down_nearest_out.png");
            let result = Resize {
                width: 50,
                height: 50,
                filter: ResizeFilter::Nearest,
                quality: 80,
            }
            .apply(&input, &output);
            assert!(result.is_ok());
            let decoded = image::open(&output).unwrap();
            assert_eq!(decoded.width(), 50);
            assert_eq!(decoded.height(), 50);
            std::fs::remove_file(&input).ok();
            std::fs::remove_file(&output).ok();
        }

        #[test]
        fn resize_upscale_bilinear() {
            let input = create_test_png("frigate_resize_up_bilinear.png", 10, 10);
            let output = tmp_path("frigate_resize_up_bilinear_out.png");
            let result = Resize {
                width: 40,
                height: 40,
                filter: ResizeFilter::Triangle,
                quality: 80,
            }
            .apply(&input, &output);
            assert!(result.is_ok());
            let decoded = image::open(&output).unwrap();
            assert_eq!(decoded.width(), 40);
            assert_eq!(decoded.height(), 40);
            std::fs::remove_file(&input).ok();
            std::fs::remove_file(&output).ok();
        }

        #[test]
        fn resize_catmullrom() {
            let input = create_test_png("frigate_resize_catmull.png", 64, 64);
            let output = tmp_path("frigate_resize_catmull_out.png");
            let result = Resize {
                width: 32,
                height: 48,
                filter: ResizeFilter::CatmullRom,
                quality: 80,
            }
            .apply(&input, &output);
            assert!(result.is_ok());
            let decoded = image::open(&output).unwrap();
            assert_eq!(decoded.width(), 32);
            assert_eq!(decoded.height(), 48);
            std::fs::remove_file(&input).ok();
            std::fs::remove_file(&output).ok();
        }

        #[test]
        fn resize_lanczos3() {
            let input = create_test_png("frigate_resize_lanczos.png", 64, 64);
            let output = tmp_path("frigate_resize_lanczos_out.jpg");
            let result = Resize {
                width: 16,
                height: 16,
                filter: ResizeFilter::Lanczos3,
                quality: 90,
            }
            .apply(&input, &output);
            assert!(result.is_ok());
            let decoded = image::open(&output).unwrap();
            assert_eq!(decoded.width(), 16);
            assert_eq!(decoded.height(), 16);
            std::fs::remove_file(&input).ok();
            std::fs::remove_file(&output).ok();
        }

        #[test]
        fn error_on_zero_width() {
            let input = create_test_png("frigate_resize_zero_w.png", 10, 10);
            let output = tmp_path("frigate_resize_zero_w_out.png");
            let err = Resize {
                width: 0,
                height: 50,
                filter: ResizeFilter::Triangle,
                quality: 80,
            }
            .apply(&input, &output)
            .unwrap_err();
            assert_eq!(err, ResizeError::ZeroDimension);
            std::fs::remove_file(&input).ok();
        }

        #[test]
        fn error_on_zero_height() {
            let input = create_test_png("frigate_resize_zero_h.png", 10, 10);
            let output = tmp_path("frigate_resize_zero_h_out.png");
            let err = Resize {
                width: 50,
                height: 0,
                filter: ResizeFilter::Triangle,
                quality: 80,
            }
            .apply(&input, &output)
            .unwrap_err();
            assert_eq!(err, ResizeError::ZeroDimension);
            std::fs::remove_file(&input).ok();
        }

        #[test]
        fn error_on_both_zero() {
            let input = create_test_png("frigate_resize_both_zero.png", 10, 10);
            let output = tmp_path("frigate_resize_both_zero_out.png");
            let err = Resize {
                width: 0,
                height: 0,
                filter: ResizeFilter::Triangle,
                quality: 80,
            }
            .apply(&input, &output)
            .unwrap_err();
            assert_eq!(err, ResizeError::ZeroDimension);
            std::fs::remove_file(&input).ok();
        }

        #[test]
        fn error_on_missing_input() {
            let output = tmp_path("frigate_resize_missing_out.png");
            let err = Resize {
                width: 50,
                height: 50,
                filter: ResizeFilter::Triangle,
                quality: 80,
            }
            .apply(Path::new("/tmp/frigate_resize_nonexistent.png"), &output)
            .unwrap_err();
            assert_eq!(err, ResizeError::Io(IoError::Read));
        }

        #[test]
        fn identity_resize_preserves_pixels() {
            let input = create_test_png("frigate_resize_identity.png", 8, 8);
            let output = tmp_path("frigate_resize_identity_out.png");
            Resize {
                width: 8,
                height: 8,
                filter: ResizeFilter::Nearest,
                quality: 80,
            }
            .apply(&input, &output)
            .unwrap();

            let original = image::open(&input).unwrap().into_rgba8();
            let resized = image::open(&output).unwrap().into_rgba8();
            assert_eq!(
                original.as_raw(),
                resized.as_raw(),
                "identity resize should preserve pixels"
            );
            std::fs::remove_file(&input).ok();
            std::fs::remove_file(&output).ok();
        }

        #[test]
        fn non_square_resize() {
            let input = create_test_png("frigate_resize_nonsquare.png", 100, 50);
            let output = tmp_path("frigate_resize_nonsquare_out.png");
            Resize {
                width: 200,
                height: 25,
                filter: ResizeFilter::Triangle,
                quality: 80,
            }
            .apply(&input, &output)
            .unwrap();
            let decoded = image::open(&output).unwrap();
            assert_eq!(decoded.width(), 200);
            assert_eq!(decoded.height(), 25);
            std::fs::remove_file(&input).ok();
            std::fs::remove_file(&output).ok();
        }
    }
}
