// safer_ffi's #[derive_ReprC] generates per-type registration tables that are processed by a
// static initializer before main(). In debug builds (cargo test) the init chain is unoptimized
// and creates ~10-20 stack frames per registered type. With enough types the cumulative depth
// exceeds the OS default (8 MB on macOS aarch64 / Linux x86-64) before any test code runs.
//
// `rustc-link-arg-tests` is Cargo's mechanism for passing linker flags *only* to test binaries.
// Note: We cannot apply these to the cdylib (library) as macOS/Linux linkers only support
// stack size adjustment for main executables. For the library loaded by Dart, we rely on
// opt-level = 1 in the dev profile to keep stack usage manageable.
fn main() {
    if cfg!(target_os = "macos") {
        // macOS: -stack_size is the ld64 spelling (note: no comma after -Wl).
        println!("cargo:rustc-link-arg-tests=-Wl,-stack_size,0x2000000"); // 32 MB
    } else if cfg!(target_os = "linux") {
        // Linux: GNU ld uses -z stacksize.
        println!("cargo:rustc-link-arg-tests=-Wl,-z,stacksize=0x2000000");
    }
    // Windows: the default 1 MB stack is set per-thread; the test harness spawns threads via
    // std::thread, so RUST_MIN_STACK=33554432 is the correct knob there. No linker flag needed.
}
