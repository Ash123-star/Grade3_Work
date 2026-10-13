import 'dart:typed_data';
import 'package:pandora_mobile/core/errors/api_failure.dart';

const maximumAttachmentBytes = 10 * 1024 * 1024;

/// Memory-only file selected by the user; never persisted with credentials or drafts.
class SelectedAttachment {
  const SelectedAttachment(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  void validate({bool avatar = false}) {
    if (bytes.isEmpty || bytes.length > maximumAttachmentBytes) {
      throw const ApiFailure(FailureKind.validation, '文件大小须为1字节至10MB');
    }
    if (avatar && !isAvatarImage(bytes)) {
      throw const ApiFailure(FailureKind.validation, '头像请选择PNG、JPEG或WebP图片');
    }
  }
}

bool isAvatarImage(List<int> bytes) =>
    bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10' ||
    bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255 ||
    bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';

String safeAttachmentName(String name) {
  var result = name
      .replaceAll(RegExp(r'[\\/\x00-\x1f\x7f<>:"|?*]'), '_')
      .trim();
  result = result.replaceAll(RegExp(r'[. ]+$'), '');
  if (result.isEmpty || result == '.' || result == '..') return 'attachment';
  if (result.length > 200) result = result.substring(result.length - 200);
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
    caseSensitive: false,
  ).hasMatch(result)) {
    result = '_$result';
  }
  return result;
}

class UploadedAttachment {
  const UploadedAttachment({
    required this.id,
    required this.name,
    required this.size,
  });
  final String id, name;
  final int size;
}

class DownloadedAttachment {
  const DownloadedAttachment({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}
