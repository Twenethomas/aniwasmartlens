import 'dart:typed_data';
import 'package:image/image.dart' as img;

Future<Uint8List> compressImage(Uint8List originalBytes, {int quality = 75}) async {
  final image = img.decodeImage(originalBytes);
  if (image == null) return originalBytes;
  final compressed = img.encodeJpg(image, quality: quality);
  return Uint8List.fromList(compressed);
}

String trimToTokenLimit(String text, int tokenLimit) {
  final words = text.split(' ');
  List<String> result = [];
  int tokenCount = 0;

  for (final word in words) {
    int tokens = (word.length / 4).ceil();
    if (tokenCount + tokens > tokenLimit) break;
    result.add(word);
    tokenCount += tokens;
  }
  return result.join(' ');
}
