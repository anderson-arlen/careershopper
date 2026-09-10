import 'dart:convert';
import 'dart:typed_data';

class ChatImage {
  ChatImage._(this.bytes, this.mimeType);

  factory ChatImage.fromBytes(Uint8List bytes) {
    if (bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('Each chat image must be at most 10 MB.');
    }
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    final mime = starts([137, 80, 78, 71, 13, 10, 26, 10])
        ? 'image/png'
        : starts([255, 216, 255])
        ? 'image/jpeg'
        : starts([71, 73, 70, 56])
        ? 'image/gif'
        : starts([82, 73, 70, 70]) &&
              bytes.length >= 12 &&
              ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
        ? 'image/webp'
        : null;
    if (mime == null) {
      throw ArgumentError('Paste a PNG, JPEG, GIF, or WebP image.');
    }
    return ChatImage._(Uint8List.fromList(bytes).asUnmodifiableView(), mime);
  }

  final Uint8List bytes;
  final String mimeType;
  Map<String, Object> toContentBlock() => {
    'type': 'image',
    'mimeType': mimeType,
    'data': base64Encode(bytes),
  };

  static List<ChatImage> fromPayload(String payload) {
    final value = jsonDecode(payload);
    if (value is! Map || value['images'] is! List) return const [];
    return (value['images'] as List)
        .map(
          (item) => ChatImage.fromBytes(
            base64Decode((item as Map)['data'] as String),
          ),
        )
        .toList(growable: false);
  }
}

void validateChatImages(List<ChatImage> images) {
  if (images.length > 4) {
    throw ArgumentError('Attach up to four images per message.');
  }
}
