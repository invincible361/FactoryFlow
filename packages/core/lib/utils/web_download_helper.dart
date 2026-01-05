import 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart';

class WebDownloadHelper {
  static Future<void> download(List<int> bytes, String fileName, {String mimeType = 'application/octet-stream'}) {
    return downloadWebFile(bytes, fileName, mimeType);
  }
}
