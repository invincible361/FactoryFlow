import 'package:web/web.dart' as web;
import 'dart:convert';

Future<void> downloadWebFile(
  List<int> bytes,
  String fileName,
  String mimeType,
) async {
  final encoded = base64Encode(bytes);
  final url = 'data:$mimeType;base64,$encoded';
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.click();
}
