use safer_ffi::prelude::*;

#[repr(C)]
#[derive(Clone, Copy)]
pub union FfiPayload {
    pub rectangle: RectanglePayload,
    pub text: TextPayload,
    pub oval: OvalPayload,
    pub polygon: PolygonPayload,
}

impl std::fmt::Debug for FfiPayload {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FfiPayload (union)").finish()
    }
}

/// Tagged-union element struct passed across the FFI boundary.
///
/// NOTE: `safer_ffi` 0.2.0-rc1 does not yet support `derive_ReprC` for enums with payloads.
/// We use `repr(C, u8)` for perfect C ABI compatibility with Dart.
#[repr(C, u8)]
#[derive(Debug, Clone, Copy)]
pub enum FfiElement {
    Rectangle(RectanglePayload) = 0,
    Text(TextPayload) = 1,
    Oval(OvalPayload) = 2,
    Polygon(PolygonPayload) = 3,
}

pub trait Shape {
    fn x(&self) -> f64;
    fn y(&self) -> f64;
    fn width(&self) -> f64;
    fn height(&self) -> f64;
    fn rotation(&self) -> i32;
    fn fill_color_argb(&self) -> u32;
    fn blur(&self) -> u8;
}

pub trait ShapeBuilder: Sized {
    fn set_rotation(&mut self, deg: i32);
    fn set_blur(&mut self, blur: u8);

    fn with_rotation(mut self, deg: i32) -> Self {
        self.set_rotation(deg);
        self
    }

    fn with_blur(mut self, blur: u8) -> Self {
        self.set_blur(blur);
        self
    }
}

#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RectanglePayload {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub rotation_deg: i32,
    pub fill_color_argb: u32,
    pub outline_color_argb: u32,
    pub outline_thickness: u8,
    pub blur: u8,
    pub corner_radius: u16,
}

impl RectanglePayload {
    pub fn new(x: f64, y: f64, width: f64, height: f64, fill_color_argb: u32) -> Self {
        Self {
            x,
            y,
            width,
            height,
            rotation_deg: 0,
            fill_color_argb,
            outline_color_argb: 0,
            outline_thickness: 0,
            blur: 0,
            corner_radius: 0,
        }
    }

    pub fn with_outline(mut self, color_argb: u32, thickness: u8) -> Self {
        self.outline_color_argb = color_argb;
        self.outline_thickness = thickness;
        self
    }

    pub fn with_corner_radius(mut self, radius: u16) -> Self {
        self.corner_radius = radius;
        self
    }
}

impl Shape for RectanglePayload {
    fn x(&self) -> f64 {
        self.x
    }
    fn y(&self) -> f64 {
        self.y
    }
    fn width(&self) -> f64 {
        self.width
    }
    fn height(&self) -> f64 {
        self.height
    }
    fn rotation(&self) -> i32 {
        self.rotation_deg
    }
    fn fill_color_argb(&self) -> u32 {
        self.fill_color_argb
    }
    fn blur(&self) -> u8 {
        self.blur
    }
}

impl ShapeBuilder for RectanglePayload {
    fn set_rotation(&mut self, deg: i32) {
        self.rotation_deg = deg;
    }
    fn set_blur(&mut self, blur: u8) {
        self.blur = blur;
    }
}

#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct OvalPayload {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub rotation_deg: i32,
    pub fill_color_argb: u32,
    pub outline_color_argb: u32,
    pub outline_thickness: u8,
    pub blur: u8,
    pub _pad: [u8; 2],
}

impl OvalPayload {
    pub fn new(x: f64, y: f64, width: f64, height: f64, fill_color_argb: u32) -> Self {
        Self {
            x,
            y,
            width,
            height,
            rotation_deg: 0,
            fill_color_argb,
            outline_color_argb: 0,
            outline_thickness: 0,
            blur: 0,
            _pad: [0; 2],
        }
    }

    pub fn with_outline(mut self, color_argb: u32, thickness: u8) -> Self {
        self.outline_color_argb = color_argb;
        self.outline_thickness = thickness;
        self
    }
}

impl Shape for OvalPayload {
    fn x(&self) -> f64 {
        self.x
    }
    fn y(&self) -> f64 {
        self.y
    }
    fn width(&self) -> f64 {
        self.width
    }
    fn height(&self) -> f64 {
        self.height
    }
    fn rotation(&self) -> i32 {
        self.rotation_deg
    }
    fn fill_color_argb(&self) -> u32 {
        self.fill_color_argb
    }
    fn blur(&self) -> u8 {
        self.blur
    }
}

impl ShapeBuilder for OvalPayload {
    fn set_rotation(&mut self, deg: i32) {
        self.rotation_deg = deg;
    }
    fn set_blur(&mut self, blur: u8) {
        self.blur = blur;
    }
}

#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct TextPayload {
    pub x: f64,
    pub y: f64,
    pub height: f64,
    pub rotation_deg: i32,
    pub fill_color_argb: u32,
    pub blur: u8,
    pub _pad: [u8; 3],
    pub font_id: u32,
    pub text_offset: u32,
    pub text_len: u32,
}

impl TextPayload {
    pub fn new(
        x: f64,
        y: f64,
        height: f64,
        fill_color_argb: u32,
        font_id: u32,
        text_offset: u32,
        text_len: u32,
    ) -> Self {
        Self {
            x,
            y,
            height,
            rotation_deg: 0,
            fill_color_argb,
            blur: 0,
            _pad: [0; 3],
            font_id,
            text_offset,
            text_len,
        }
    }
}

impl Shape for TextPayload {
    fn x(&self) -> f64 {
        self.x
    }
    fn y(&self) -> f64 {
        self.y
    }
    fn width(&self) -> f64 {
        0.0 // width is computed dynamically at render time from font metrics; not stored in the wire struct.
    }
    fn height(&self) -> f64 {
        self.height
    }
    fn rotation(&self) -> i32 {
        self.rotation_deg
    }
    fn fill_color_argb(&self) -> u32 {
        self.fill_color_argb
    }
    fn blur(&self) -> u8 {
        self.blur
    }
}

impl ShapeBuilder for TextPayload {
    fn set_rotation(&mut self, deg: i32) {
        self.rotation_deg = deg;
    }
    fn set_blur(&mut self, blur: u8) {
        self.blur = blur;
    }
}

/// Represents the FFI layout for a polygon payload.
/// Note: Manual padding fields (_pad1, _pad2) are explicitly specified here instead of
/// #[repr(C, align(8))] to ensure a mechanical, 1-to-1 match with the Dart FFI Struct definition
/// without depending on compiler-specific alignment behavior for composite fields.
#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct PolygonPayload {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub vertices_ptr: *const f64,
    pub vertex_count: u32,
    pub fill_color_argb: u32,
    pub outline_color_argb: u32,
    pub outline_thickness: u8,
    pub blur: u8,
    pub _pad1: u16,
    pub rotation_deg: i32,
    pub _pad2: u32,
}

impl Shape for PolygonPayload {
    fn x(&self) -> f64 {
        self.x
    }
    fn y(&self) -> f64 {
        self.y
    }
    fn width(&self) -> f64 {
        self.width
    }
    fn height(&self) -> f64 {
        self.height
    }
    fn rotation(&self) -> i32 {
        self.rotation_deg
    }
    fn fill_color_argb(&self) -> u32 {
        self.fill_color_argb
    }
    fn blur(&self) -> u8 {
        self.blur
    }
}

impl ShapeBuilder for PolygonPayload {
    fn set_rotation(&mut self, deg: i32) {
        self.rotation_deg = deg;
    }
    fn set_blur(&mut self, blur: u8) {
        self.blur = blur;
    }
}

// Layout assertions to freeze the wire contract.
// Dart side MUST match these exactly using Struct + Union + padding.
const _: () = assert!(std::mem::size_of::<RectanglePayload>() == 48);
const _: () = assert!(std::mem::size_of::<OvalPayload>() == 48);
const _: () = assert!(std::mem::size_of::<TextPayload>() == 48);
const _: () = assert!(std::mem::size_of::<PolygonPayload>() == 64);
const _: () = assert!(std::mem::size_of::<FfiPayload>() == 64);
const _: () = assert!(std::mem::align_of::<FfiPayload>() == 8);
const _: () = assert!(std::mem::size_of::<FfiElement>() == 72); // Tag(1) + Pad(7) + Payload(64)
const _: () = assert!(std::mem::align_of::<FfiElement>() == 8);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_element_layout() {
        assert_eq!(std::mem::size_of::<RectanglePayload>(), 48);
        assert_eq!(std::mem::size_of::<OvalPayload>(), 48);
        assert_eq!(std::mem::size_of::<TextPayload>(), 48);
        assert_eq!(std::mem::size_of::<PolygonPayload>(), 64);
        assert_eq!(std::mem::size_of::<FfiPayload>(), 64);
        assert_eq!(std::mem::align_of::<FfiPayload>(), 8);
        assert_eq!(std::mem::size_of::<FfiElement>(), 72);
        assert_eq!(std::mem::align_of::<FfiElement>(), 8);
    }

    // --- RectanglePayload ---

    #[test]
    fn rectangle_shape_trait_getters() {
        let p = RectanglePayload::new(1.0, 2.0, 3.0, 4.0, 0xFF_00_FF_00)
            .with_rotation(45)
            .with_blur(7)
            .with_outline(0xFF_FF_00_00, 3)
            .with_corner_radius(8);

        assert_eq!(p.x(), 1.0);
        assert_eq!(p.y(), 2.0);
        assert_eq!(p.width(), 3.0);
        assert_eq!(p.height(), 4.0);
        assert_eq!(p.rotation(), 45);
        assert_eq!(p.fill_color_argb(), 0xFF_00_FF_00);
        assert_eq!(p.blur(), 7);
        assert_eq!(p.outline_color_argb, 0xFF_FF_00_00);
        assert_eq!(p.outline_thickness, 3);
        assert_eq!(p.corner_radius, 8);
    }

    #[test]
    fn rectangle_shape_builder_set_methods() {
        let mut p = RectanglePayload::new(0.0, 0.0, 10.0, 10.0, 0);
        p.set_rotation(90);
        p.set_blur(5);
        assert_eq!(p.rotation(), 90);
        assert_eq!(p.blur(), 5);
    }

    // --- OvalPayload ---

    #[test]
    fn oval_shape_trait_getters() {
        let p = OvalPayload::new(5.0, 6.0, 7.0, 8.0, 0xFF_00_00_FF)
            .with_rotation(30)
            .with_blur(2)
            .with_outline(0xFF_FF_FF_00, 4);

        assert_eq!(p.x(), 5.0);
        assert_eq!(p.y(), 6.0);
        assert_eq!(p.width(), 7.0);
        assert_eq!(p.height(), 8.0);
        assert_eq!(p.rotation(), 30);
        assert_eq!(p.fill_color_argb(), 0xFF_00_00_FF);
        assert_eq!(p.blur(), 2);
        assert_eq!(p.outline_color_argb, 0xFF_FF_FF_00);
        assert_eq!(p.outline_thickness, 4);
    }

    #[test]
    fn oval_shape_builder_set_methods() {
        let mut p = OvalPayload::new(0.0, 0.0, 10.0, 10.0, 0);
        p.set_rotation(-90);
        p.set_blur(12);
        assert_eq!(p.rotation(), -90);
        assert_eq!(p.blur(), 12);
    }

    // --- TextPayload ---

    #[test]
    fn text_shape_trait_getters() {
        let p = TextPayload::new(10.0, 20.0, 30.0, 0xFF_AA_BB_CC, 1, 0, 5)
            .with_rotation(180)
            .with_blur(3);

        assert_eq!(p.x(), 10.0);
        // TextPayload has no `width` stored — always returns 0.0 per spec.
        assert_eq!(p.width(), 0.0);
        assert_eq!(p.y(), 20.0);
        assert_eq!(p.height(), 30.0);
        assert_eq!(p.rotation(), 180);
        assert_eq!(p.fill_color_argb(), 0xFF_AA_BB_CC);
        assert_eq!(p.blur(), 3);
        assert_eq!(p.font_id, 1);
        assert_eq!(p.text_offset, 0);
        assert_eq!(p.text_len, 5);
    }

    #[test]
    fn text_shape_builder_set_methods() {
        let mut p = TextPayload::new(0.0, 0.0, 12.0, 0, 0, 0, 0);
        p.set_rotation(270);
        p.set_blur(9);
        assert_eq!(p.rotation(), 270);
        assert_eq!(p.blur(), 9);
    }

    // --- PolygonPayload ---

    #[test]
    fn polygon_shape_trait_getters() {
        let p = PolygonPayload {
            x: 11.0,
            y: 22.0,
            width: 33.0,
            height: 44.0,
            vertices_ptr: std::ptr::null(),
            vertex_count: 0,
            fill_color_argb: 0xFF_CC_DD_EE,
            outline_color_argb: 0,
            outline_thickness: 0,
            blur: 6,
            _pad1: 0,
            rotation_deg: -45,
            _pad2: 0,
        };

        assert_eq!(p.x(), 11.0);
        assert_eq!(p.y(), 22.0);
        assert_eq!(p.width(), 33.0);
        assert_eq!(p.height(), 44.0);
        assert_eq!(p.rotation(), -45);
        assert_eq!(p.fill_color_argb(), 0xFF_CC_DD_EE);
        assert_eq!(p.blur(), 6);
    }

    #[test]
    fn polygon_shape_builder_set_methods() {
        let mut p = PolygonPayload {
            x: 0.0,
            y: 0.0,
            width: 10.0,
            height: 10.0,
            vertices_ptr: std::ptr::null(),
            vertex_count: 0,
            fill_color_argb: 0,
            outline_color_argb: 0,
            outline_thickness: 0,
            blur: 0,
            _pad1: 0,
            rotation_deg: 0,
            _pad2: 0,
        };
        p.set_rotation(90);
        p.set_blur(15);
        assert_eq!(p.rotation(), 90);
        assert_eq!(p.blur(), 15);
    }

    // --- FfiPayload debug impl ---

    #[test]
    fn ffi_payload_debug_does_not_panic() {
        let payload = FfiPayload {
            rectangle: RectanglePayload::new(0.0, 0.0, 1.0, 1.0, 0),
        };
        let debug_str = format!("{:?}", payload);
        assert!(debug_str.contains("FfiPayload"));
    }
}
