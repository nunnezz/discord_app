import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

class ChatMediaAttachment {
  final String path;
  final String mimeType;
  final String fileName;
  final String type;

  const ChatMediaAttachment({
    required this.path,
    required this.mimeType,
    required this.fileName,
    required this.type,
  });
}

class ChatMediaService {
  static const bucket = 'chat-media';
  static const imageMaxBytes = 5 * 1024 * 1024;
  static const videoMaxBytes = 20 * 1024 * 1024;
  static const _signedUrlLifetime = Duration(hours: 24);
  static const _mimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
  };

  static final _random = Random.secure();
  static final Map<String, ({String url, DateTime expiresAt})> _signedUrlCache =
      {};

  static Future<ChatMediaAttachment> upload({
    required String userId,
    required XFile file,
  }) async {
    final extension =
        file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    final mimeType = _mimeTypes[extension] ?? file.mimeType?.toLowerCase();
    if (mimeType == null || !_mimeTypes.values.contains(mimeType)) {
      throw const FormatException(
        'Formato não aceito. Envie uma imagem JPG, PNG ou WEBP, '
        'ou um vídeo MP4, WEBM ou MOV.',
      );
    }

    final type = mimeType.startsWith('image/') ? 'image' : 'video';
    final maxBytes = type == 'image' ? imageMaxBytes : videoMaxBytes;
    final fileSize = await file.length();
    if (fileSize == 0) {
      throw const FormatException('O arquivo selecionado está vazio.');
    }
    if (fileSize > maxBytes) {
      final maxMegabytes = type == 'image' ? 5 : 20;
      throw FormatException('O arquivo deve ter no máximo $maxMegabytes MB.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('O arquivo selecionado está vazio.');
    }
    if (bytes.length > maxBytes) {
      final maxMegabytes = type == 'image' ? 5 : 20;
      throw FormatException('O arquivo deve ter no máximo $maxMegabytes MB.');
    }

    final safeExtension = _extensionForMimeType(mimeType);
    final uniqueId =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff).toRadixString(16)}';
    final path = '$userId/$uniqueId.$safeExtension';

    await supabase.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: mimeType,
          ),
        );

    return ChatMediaAttachment(
      path: path,
      mimeType: mimeType,
      fileName: file.name,
      type: type,
    );
  }

  static Future<void> remove(String path) async {
    await supabase.storage.from(bucket).remove([path]);
    _signedUrlCache.remove(path);
  }

  static Future<Map<String, String>> createSignedUrls(
    Iterable<String?> paths,
  ) async {
    final uniquePaths =
        paths.whereType<String>().where((path) => path.isNotEmpty).toSet();
    final now = DateTime.now();
    final urls = <String, String>{};
    final pathsToSign = <String>[];

    for (final path in uniquePaths) {
      final cached = _signedUrlCache[path];
      if (cached != null &&
          cached.expiresAt.isAfter(now.add(const Duration(minutes: 2)))) {
        urls[path] = cached.url;
      } else {
        pathsToSign.add(path);
      }
    }

    if (pathsToSign.isEmpty) return urls;

    final results = await supabase.storage
        .from(bucket)
        .createSignedUrlsResult(pathsToSign, _signedUrlLifetime.inSeconds);
    final expiresAt = now.add(_signedUrlLifetime);
    for (final result in results) {
      switch (result) {
        case SignedUrlSuccess(:final path, :final signedUrl):
          urls[path] = signedUrl;
          _signedUrlCache[path] = (url: signedUrl, expiresAt: expiresAt);
        case SignedUrlFailure():
          break;
      }
    }
    return urls;
  }

  static String _extensionForMimeType(String mimeType) {
    return _mimeTypes.entries
        .firstWhere((entry) => entry.value == mimeType)
        .key;
  }
}
