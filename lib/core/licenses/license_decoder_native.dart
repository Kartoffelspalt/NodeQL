import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

String decodeBundledLicenses(Uint8List bytes) =>
    utf8.decode(gzip.decode(bytes));
