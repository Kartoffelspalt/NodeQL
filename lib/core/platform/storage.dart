// Native files on desktop; an isolated, in-memory session on the web.
export 'storage_native.dart' if (dart.library.js_interop) 'storage_web.dart';
