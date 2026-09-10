import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:image/image.dart' as img;

import 'database.dart';

/// Logos are downloaded once, decoded with a size ceiling, and stored as local
/// PNG thumbnails. Browsing the job list never makes third-party requests.
class EmployerLogoRepository {
  EmployerLogoRepository(
    this.database, {
    Future<Uint8List> Function(Uri)? fetch,
  }) : fetch = fetch ?? fetchPublicLogo;
  final CareerShopperDatabase database;
  final Future<Uint8List> Function(Uri) fetch;
  static const maxBytes = 1024 * 1024;

  Future<void> setFromUrl(String employerId, Uri url) async {
    validateLogoUrl(url);
    final employer = await (database.select(
      database.employers,
    )..where((row) => row.id.equals(employerId))).getSingle();
    if (employer.blockedAt != null) {
      throw StateError('Do not fetch logos for a blocked employer.');
    }
    if (employer.logoSourceUrl == url.toString() && employer.logoPng != null) {
      return;
    }
    final bytes = await fetch(url).timeout(const Duration(seconds: 15));
    if (bytes.length > maxBytes) {
      throw const FormatException('Logo exceeds the 1 MiB limit.');
    }
    final decoder = img.findDecoderForData(bytes);
    if (decoder is! img.PngDecoder &&
        decoder is! img.JpegDecoder &&
        decoder is! img.WebPDecoder) {
      throw const FormatException('Use a PNG, JPEG or WebP company logo.');
    }
    final info = decoder!.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width > 2048 ||
        info.height > 2048) {
      throw const FormatException(
        'Logo dimensions must be between 1 and 2048 pixels.',
      );
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException('Logo could not be decoded.');
    }
    final thumbnail = decoded.width >= decoded.height
        ? img.copyResize(
            decoded,
            width: decoded.width > 128 ? 128 : decoded.width,
          )
        : img.copyResize(
            decoded,
            height: decoded.height > 128 ? 128 : decoded.height,
          );
    final png = Uint8List.fromList(img.encodePng(thumbnail));
    // Recheck the block in the update predicate in case the user changed it
    // during the download. An unavailable replacement never erases a good logo.
    await (database.update(database.employers)
          ..where((row) => row.id.equals(employerId) & row.blockedAt.isNull()))
        .write(
          EmployersCompanion(
            logoPng: Value(png),
            logoSourceUrl: Value(url.toString()),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }
}

void validateLogoUrl(Uri url) {
  if (url.scheme != 'https' ||
      !url.hasAuthority ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      url.port != 443 ||
      !url.host.contains('.') ||
      url.host.endsWith('.localhost') ||
      url.host.endsWith('.local') ||
      InternetAddress.tryParse(url.host) != null) {
    throw const FormatException(
      'Logo must be a public HTTPS image URL on port 443, without credentials.',
    );
  }
}

bool isPublicLogoAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return b[0] != 0 &&
        b[0] != 10 &&
        b[0] != 127 &&
        b[0] < 224 &&
        !(b[0] == 169 && b[1] == 254) &&
        !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
        !(b[0] == 192 && b[1] == 168) &&
        !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
        !(b[0] == 198 && (b[1] == 18 || b[1] == 19));
  }
  // Only ordinary globally routed IPv6; excludes mapped IPv4 and local ranges.
  return (b[0] & 0xe0) == 0x20;
}

Future<Uint8List> fetchPublicLogo(Uri url) async {
  validateLogoUrl(url);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    validateLogoUrl(uri);
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 5));
    if (addresses.isEmpty ||
        addresses.any((address) => !isPublicLogoAddress(address))) {
      throw const FormatException(
        'Logo host must resolve only to public addresses.',
      );
    }
    // Connect to the checked address, preventing a second DNS lookup/rebinding.
    return Socket.startConnect(addresses.first, uri.port);
  };
  try {
    return await (() async {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Logo returned HTTP ${response.statusCode}; no retries or redirects attempted.',
        );
      }
      if (!{
        'image/png',
        'image/jpeg',
        'image/webp',
      }.contains(response.headers.contentType?.mimeType)) {
        throw const FormatException(
          'Logo response is not a supported raster image.',
        );
      }
      if (response.contentLength > EmployerLogoRepository.maxBytes) {
        throw const FormatException('Logo exceeds the 1 MiB limit.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > EmployerLogoRepository.maxBytes) {
          throw const FormatException('Logo exceeds the 1 MiB limit.');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    })().timeout(const Duration(seconds: 12));
  } finally {
    client.close(force: true);
  }
}
