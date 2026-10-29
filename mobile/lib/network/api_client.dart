import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createApiClient() {
  const trustedCaBase64 = String.fromEnvironment('MELODISCAN_ROOT_CA_BASE64');
  if (trustedCaBase64.isEmpty) return http.Client();

  final securityContext = SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(base64Decode(trustedCaBase64));
  return IOClient(HttpClient(context: securityContext));
}
