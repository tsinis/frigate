import 'export_backend.dart';

/// Fallback for unsupported platforms (neither dart:ffi nor dart:js_interop).
// ignore: prefer-static-class, required top-level for conditional import pattern.
ExportBackend createExportBackend() =>
    throw UnsupportedError('No export backend available for this platform.');
