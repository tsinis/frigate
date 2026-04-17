import 'export_backend.dart';

/// Fallback for unsupported platforms (neither dart:ffi nor dart:js_interop).
ExportBackend createExportBackend() =>
    throw UnsupportedError('No export backend available for this platform.');
