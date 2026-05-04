//! Golden image tests for oval rendering.

use std::path::{Path, PathBuf};

use image::RgbaImage;

use frigate::{FfiElement, OvalPayload};

fn assets_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/assets")
}

fn golden_path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("golden")
        .join(name)
}

fn base_image() -> RgbaImage {
    let path = assets_dir().join("paint.jpg");
    image::open(&path)
        .unwrap_or_else(|_| panic!("failed to decode {path:?}"))
        .into_rgba8()
}

fn make_oval(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u8,
    outline_color_argb: u32,
) -> FfiElement {
    make_oval_with_fill(
        x,
        y,
        width,
        height,
        outline_thickness,
        outline_color_argb,
        0,
    )
}

fn make_oval_with_fill(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outline_thickness: u8,
    outline_color_argb: u32,
    fill_color_argb: u32,
) -> FfiElement {
    FfiElement::Oval(OvalPayload {
        x,
        y,
        width,
        height,
        rotation_deg: 0,
        fill_color_argb,
        outline_color_argb,
        outline_thickness,
        blur: 0,
        _pad: [0; 2],
    })
}

fn render_ovals(ovals: &[FfiElement]) -> RgbaImage {
    let mut img = base_image();
    for o in ovals {
        frigate::draw_element(&mut img, o, None, &[]);
    }
    img
}

fn assert_golden(actual: &RgbaImage, path: &Path) {
    let base = base_image();
    assert_ne!(
        actual.as_raw(),
        base.as_raw(),
        "{path:?}: rendered output is byte-identical to the unmodified base image."
    );

    if !path.exists() {
        actual
            .save(path)
            .unwrap_or_else(|e| panic!("failed to write new golden to {path:?}: {e}"));
        panic!(
            "Golden did not exist; wrote new golden to {path:?}. Inspect visually, commit it, then re-run."
        );
    }
    let expected = image::open(path)
        .unwrap_or_else(|_| panic!("failed to decode golden {path:?}"))
        .into_rgba8();
    assert_eq!(
        actual.dimensions(),
        expected.dimensions(),
        "golden dimension mismatch at {path:?}"
    );
    for (x, y, px) in actual.enumerate_pixels() {
        let ex = expected.get_pixel(x, y);
        if px != ex {
            panic!(
                "pixel mismatch at ({x}, {y}) in {path:?}: got {:?}, expected {:?}",
                px.0, ex.0
            );
        }
    }
}

#[test]
fn golden_oval_solid_outline() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let oval = make_oval(
        0.20 * w,
        0.20 * h,
        0.60 * w,
        0.40 * h,
        4,
        0xFFFF_0000, // opaque red
    );
    let img = render_ovals(&[oval]);
    assert_golden(&img, &golden_path("oval_solid.png"));
}

#[test]
fn golden_oval_filled() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let oval = make_oval_with_fill(
        0.10 * w,
        0.10 * h,
        0.80 * w,
        0.80 * h,
        6,
        0xFF_FF_FF_FF, // opaque white outline
        0x80_00_00_FF, // 50% blue fill
    );
    let img = render_ovals(&[oval]);
    assert_golden(&img, &golden_path("oval_filled.png"));
}

#[test]
fn golden_oval_clipped() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);
    let oval = make_oval(
        -0.20 * w,
        -0.20 * h,
        0.60 * w,
        0.60 * h,
        4,
        0xFF00_FF00, // opaque green
    );
    let img = render_ovals(&[oval]);
    assert_golden(&img, &golden_path("oval_clipped.png"));
}
