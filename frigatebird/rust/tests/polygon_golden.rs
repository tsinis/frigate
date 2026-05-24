//! Golden image tests for polygon rendering.

use std::path::{Path, PathBuf};

use image::RgbaImage;

use frigate::{FfiElement, PolygonPayload};

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

#[allow(clippy::too_many_arguments)]
fn make_polygon_full(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    vertices: &[f64],
    outline_thickness: u8,
    outline_color_argb: u32,
    fill_color_argb: u32,
    rotation_deg: i32,
) -> FfiElement {
    FfiElement::Polygon(PolygonPayload::new(
        x,
        y,
        width,
        height,
        vertices.as_ptr(),
        (vertices.len() / 2) as u32,
        fill_color_argb,
        outline_color_argb,
        outline_thickness,
        0,
        rotation_deg,
    ))
}

fn render_polygons(polygons: &[FfiElement]) -> RgbaImage {
    let mut img = base_image();
    for p in polygons {
        frigate::draw_element(&mut img, p, None, &[]);
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
fn golden_polygon_solid_outline() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);

    let x = 0.20 * w;
    let y = 0.20 * h;
    let width = 0.60 * w;
    let height = 0.60 * h;

    let vertices = [x + width / 2.0, y, x + width, y + height, x, y + height];

    let poly = make_polygon_full(
        x,
        y,
        width,
        height,
        &vertices,
        4,
        0xFFFF_0000, // opaque red
        0,
        0,
    );
    let img = render_polygons(&[poly]);
    assert_golden(&img, &golden_path("polygon_solid.png"));
}

#[test]
fn golden_polygon_filled() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);

    let x = 0.15 * w;
    let y = 0.15 * h;
    let width = 0.70 * w;
    let height = 0.70 * h;

    let vertices = [
        x + width / 2.0,
        y,
        x + width,
        y + height / 2.0,
        x + width / 2.0,
        y + height,
        x,
        y + height / 2.0,
    ];

    let poly = make_polygon_full(
        x,
        y,
        width,
        height,
        &vertices,
        6,
        0xFF_FF_FF_FF, // opaque white outline
        0x80_00_00_FF, // 50% blue fill
        0,
    );
    let img = render_polygons(&[poly]);
    assert_golden(&img, &golden_path("polygon_filled.png"));
}

#[test]
fn golden_polygon_clipped() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);

    let x = -0.10 * w;
    let y = -0.10 * h;
    let width = 0.80 * w;
    let height = 0.80 * h;

    let vertices = [x + width / 2.0, y, x + width, y + height, x, y + height];

    let poly = make_polygon_full(
        x,
        y,
        width,
        height,
        &vertices,
        4,
        0xFF00_FF00,   // opaque green
        0x80_FF_00_FF, // 50% magenta fill
        0,
    );
    let img = render_polygons(&[poly]);
    assert_golden(&img, &golden_path("polygon_clipped.png"));
}

#[test]
fn golden_polygon_stacked_overlapping() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);

    let x1 = 0.10 * w;
    let y1 = 0.10 * h;
    let w1 = 0.50 * w;
    let h1 = 0.50 * h;
    let verts1 = [x1 + w1 / 2.0, y1, x1 + w1, y1 + h1, x1, y1 + h1];

    let x2 = 0.30 * w;
    let y2 = 0.30 * h;
    let w2 = 0.50 * w;
    let h2 = 0.50 * h;
    let verts2 = [x2, y2, x2 + w2, y2, x2 + w2 / 2.0, y2 + h2];

    let poly1 = make_polygon_full(x1, y1, w1, h1, &verts1, 3, 0xFFFF_0000, 0x80_FF_00_00, 0);
    let poly2 = make_polygon_full(x2, y2, w2, h2, &verts2, 3, 0xFF00_FF00, 0x80_00_FF_00, 0);

    let img = render_polygons(&[poly1, poly2]);
    assert_golden(&img, &golden_path("polygon_stacked.png"));
}

#[test]
fn golden_polygon_rotated() {
    let base = base_image();
    let (w, h) = (base.width() as f64, base.height() as f64);

    let x = 0.20 * w;
    let y = 0.20 * h;
    let width = 0.60 * w;
    let height = 0.60 * h;

    let vertices = [x + width / 2.0, y, x + width, y + height, x, y + height];

    let poly = make_polygon_full(
        x,
        y,
        width,
        height,
        &vertices,
        4,
        0xFF_FF_FF_FF,
        0xFF_FF_A5_00, // orange fill
        45,            // rotate 45 degrees
    );
    let img = render_polygons(&[poly]);
    assert_golden(&img, &golden_path("polygon_rotated.png"));
}
