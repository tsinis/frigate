use safer_ffi::prelude::*;

#[repr(C)]
#[derive(Clone, Copy)]
pub union FfiPayload {
    pub rectangle: RectanglePayload,
    pub text: TextPayload,
    pub oval: OvalPayload,
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

// Layout assertions to freeze the wire contract.
// Dart side MUST match these exactly using Struct + Union + padding.
const _: () = assert!(std::mem::size_of::<RectanglePayload>() == 48);
const _: () = assert!(std::mem::size_of::<OvalPayload>() == 48);
const _: () = assert!(std::mem::size_of::<TextPayload>() == 48);
const _: () = assert!(std::mem::size_of::<FfiPayload>() == 48);
const _: () =
    assert!(std::mem::align_of::<FfiPayload>() == std::mem::align_of::<RectanglePayload>());
const _: () = assert!(std::mem::size_of::<FfiElement>() == 56); // Tag(1) + Pad(7) + Payload(48)
const _: () = assert!(std::mem::align_of::<FfiElement>() == 8);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_element_layout() {
        assert_eq!(std::mem::size_of::<RectanglePayload>(), 48);
        assert_eq!(std::mem::size_of::<OvalPayload>(), 48);
        assert_eq!(std::mem::size_of::<TextPayload>(), 48);
        assert_eq!(std::mem::size_of::<FfiPayload>(), 48);
        assert_eq!(
            std::mem::align_of::<FfiPayload>(),
            std::mem::align_of::<RectanglePayload>()
        );
        assert_eq!(std::mem::size_of::<FfiElement>(), 56);
        assert_eq!(std::mem::align_of::<FfiElement>(), 8);
    }
}
