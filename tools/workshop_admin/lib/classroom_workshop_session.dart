import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nodeql/features/tutorial/classroom_workshop_code.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';

typedef ClassroomNetwork = ({String name, InternetAddress address});

/// Serves one immutable, encrypted workshop on a chosen private interface.
class ClassroomWorkshopSession {
  ClassroomWorkshopSession._(
    this._server,
    this.code,
    this._payload,
    Duration duration,
  ) : expiresAt = DateTime.now().add(duration),
      _endpoint = code.requestUri {
    _expiry = Timer(duration, () => unawaited(stop()));
    _server.listen(_serve, onError: (Object _) => unawaited(stop()));
  }

  static const maxDuration = Duration(minutes: 30);
  static const _maxActiveRequests = 64;
  final HttpServer _server;
  final ClassroomWorkshopCode code;
  final Uint8List _payload;
  final Uri _endpoint;
  final DateTime expiresAt;
  final _closed = Completer<void>();
  late final Timer _expiry;
  Future<void>? _stopping;
  int _activeRequests = 0;

  Future<void> get closed => _closed.future;

  static Future<List<ClassroomNetwork>> networks() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return {
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (ClassroomWorkshopCode.acceptsAddress(address.address))
            address.address: (name: interface.name, address: address),
    }.values.toList(growable: false);
  }

  static Future<ClassroomWorkshopSession> start({
    required InternetAddress address,
    required String source,
    Duration duration = maxDuration,
  }) async {
    if (!ClassroomWorkshopCode.acceptsAddress(address.address) ||
        duration <= Duration.zero ||
        duration > maxDuration) {
      throw const FormatException('Invalid classroom session settings.');
    }
    validateRemoteWorkshopBundle(source);
    final bytes = utf8.encode(source);
    final server = await HttpServer.bind(address, 0)
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final code = ClassroomWorkshopCode.issue(
        address: address.address,
        port: server.port,
        bundle: bytes,
      );
      final payload = await code.seal(bytes);
      return ClassroomWorkshopSession._(server, code, payload, duration);
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }

  Future<void> stop() {
    _expiry.cancel();
    return _stopping ??= _server
        .close(force: true)
        .then<void>((_) {})
        .whenComplete(() => _closed.complete());
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response
      ..persistentConnection = false
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('X-Content-Type-Options', 'nosniff');
    final peer = request.connectionInfo?.remoteAddress.address;
    final allowed =
        _stopping == null &&
        DateTime.now().isBefore(expiresAt) &&
        peer != null &&
        ClassroomWorkshopCode.acceptsAddress(peer) &&
        request.method == 'GET' &&
        !request.uri.hasAuthority &&
        !request.uri.hasQuery &&
        request.uri.path == _endpoint.path &&
        request.headers[HttpHeaders.hostHeader]?.singleOrNull ==
            _endpoint.authority &&
        request.contentLength <= 0 &&
        request.headers[HttpHeaders.transferEncodingHeader] == null;
    if (!allowed) {
      response.statusCode = HttpStatus.notFound;
      await _closeResponse(response);
      return;
    }
    if (_activeRequests >= _maxActiveRequests) {
      response.statusCode = HttpStatus.serviceUnavailable;
      await _closeResponse(response);
      return;
    }
    _activeRequests++;
    try {
      response.headers.contentType = ContentType.binary;
      response.contentLength = _payload.length;
      response.add(_payload);
      await _closeResponse(response);
    } on Exception {
      // A disconnected student must not stop sharing with the rest of class.
    } finally {
      _activeRequests--;
    }
  }

  static Future<void> _closeResponse(HttpResponse response) async {
    try {
      await response.close();
    } on Exception {
      // A peer may close the connection before reading the response.
    }
  }
}
