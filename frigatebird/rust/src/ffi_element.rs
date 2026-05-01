//! Tagged-union element struct passed across the FFI boundary.

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

#[repr(C, u8)]
#[derive(Debug, Clone, Copy)]
pub enum FfiElement {
    Rectangle(RectanglePayload) = 0,
    Text(TextPayload) = 1,
}

// Layout assertions to freeze the wire contract.
// We assert size and alignment.
// Dart side MUST match these exactly using Struct + Union + padding.
const _: () = assert!(std::mem::size_of::<RectanglePayload>() == 48);
const _: () = assert!(std::mem::size_of::<TextPayload>() == 48);
const _: () = assert!(std::mem::size_of::<FfiElement>() == 56); // Tag(1) + Pad(7) + TextPayload(48)
const _: () = assert!(std::mem::align_of::<FfiElement>() == 8);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_element_layout() {
        assert_eq!(std::mem::size_of::<RectanglePayload>(), 48);
        assert_eq!(std::mem::size_of::<TextPayload>(), 48);
        assert_eq!(std::mem::size_of::<FfiElement>(), 56);
        assert_eq!(std::mem::align_of::<FfiElement>(), 8);
    }
}
