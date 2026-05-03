//! FFI helper macros.

#[macro_export]
macro_rules! ffi_result {
    ($name:ident, $ok:ty) => {
        /// Enums with payloads are not supported by `safer_ffi::derive_ReprC` yet.
        #[repr(C, u8)]
        pub enum $name {
            Ok($ok) = 0,
            Err($crate::ffi::FfiError) = 1,
        }

        impl $name {
            #[inline]
            pub fn ok(v: $ok) -> Self {
                Self::Ok(v)
            }
            #[inline]
            pub fn err(e: $crate::ffi::FfiError) -> Self {
                Self::Err(e)
            }
        }
    };
}
