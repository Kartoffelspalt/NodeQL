import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// A code shared by the teacher over a separate channel. Its key never travels
/// in the HTTP request. The digest pins the original workshop even for peers
/// who know the classroom key.
class ClassroomWorkshopCode {
  ClassroomWorkshopCode._(this.address, this.port, this._key, this._digest);

  static const prefix = 'NQL1-';
  static const _keyLength = 16;
  static const _portOffset = 4;
  static const _keyOffset = 6;
  static const _digestOffset = _keyOffset + _keyLength;
  static final _encodedPayload = RegExp(r'^[A-Za-z0-9_-]{72}$');
  static final _cipher = AesGcm.with256bits();

  final String address;
  final int port;
  final List<int> _key;
  final hash.Digest _digest;

  String get digest => _digest.toString();
  static int get encryptionOverhead =>
      _cipher.nonceLength + _cipher.macAlgorithm.macLength;

  factory ClassroomWorkshopCode.issue({
    required String address,
    required int port,
    required List<int> bundle,
  }) {
    if (!acceptsAddress(address) || !_isUnprivilegedPort(port)) {
      throw const FormatException('Invalid classroom endpoint.');
    }
    final random = Random.secure();
    return ClassroomWorkshopCode._(
      address,
      port,
      List<int>.generate(_keyLength, (_) => random.nextInt(256)),
      hash.sha256.convert(bundle),
    );
  }

  factory ClassroomWorkshopCode.parse(String source) {
    final code = source.trim();
    if (!code.startsWith(prefix) ||
        !_encodedPayload.hasMatch(code.substring(prefix.length))) {
      throw const FormatException('Invalid classroom code.');
    }
    final bytes = base64Url.decode(code.substring(prefix.length));
    final address = bytes.take(_portOffset).join('.');
    final port = ByteData.sublistView(bytes).getUint16(_portOffset);
    if (!acceptsAddress(address) || !_isUnprivilegedPort(port)) {
      throw const FormatException('Invalid classroom endpoint.');
    }
    return ClassroomWorkshopCode._(
      address,
      port,
      bytes.sublist(_keyOffset, _digestOffset),
      hash.Digest(bytes.sublist(_digestOffset)),
    );
  }

  String encode() {
    final payload = <int>[
      ...address.split('.').map(int.parse),
      port >> 8,
      port & 255,
      ..._key,
      ..._digest.bytes,
    ];
    return '$prefix${base64Url.encode(payload)}';
  }

  Uri get requestUri => Uri(
    scheme: 'http',
    host: address,
    port: port,
    path: '/nodeql-classroom/v1/${_derive('download')}',
  );

  Future<Uint8List> seal(List<int> bundle) async {
    final box = await _cipher.encrypt(bundle, secretKey: _encryptionKey);
    return box.concatenation();
  }

  Future<Uint8List> open(Uint8List bytes) async {
    if (bytes.length < encryptionOverhead) {
      throw const FormatException('Incomplete classroom download.');
    }
    final box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
    );
    return Uint8List.fromList(
      await _cipher.decrypt(box, secretKey: _encryptionKey),
    );
  }

  SecretKey get _encryptionKey => SecretKey(_derive('encryption').bytes);

  hash.Digest _derive(String purpose) => hash.Hmac(
    hash.sha256,
    _key,
  ).convert(utf8.encode('NodeQL classroom v1 $purpose'));

  static bool acceptsAddress(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return false;
    final bytes = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part, radix: 10);
      if (value == null || value < 0 || value > 255 || '$value' != part) {
        return false;
      }
      bytes.add(value);
    }
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static bool _isUnprivilegedPort(int port) => port >= 1024 && port <= 65535;
}
