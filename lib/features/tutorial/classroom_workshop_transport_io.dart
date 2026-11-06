import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Connect to the literal address in the teacher's code. Keep classroom
/// requests out of environment/system HTTP proxies.
http.Client createClassroomWorkshopClient() => IOClient(
  HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 5)
    ..findProxy = (_) => 'DIRECT',
);
