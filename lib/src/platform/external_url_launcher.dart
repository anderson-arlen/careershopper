import 'dart:io';

Future<void> openExternalUrl(Uri url) async {
  if (!url.hasScheme || (url.scheme != 'https' && url.scheme != 'http')) {
    throw ArgumentError('Only saved HTTP(S) URLs can be opened.');
  }

  final (executable, arguments) = switch (Platform.operatingSystem) {
    'linux' => ('xdg-open', [url.toString()]),
    'macos' => ('open', [url.toString()]),
    'windows' => (
      'rundll32.exe',
      ['url.dll,FileProtocolHandler', url.toString()],
    ),
    _ => throw UnsupportedError(
      'Opening a browser is not supported on ${Platform.operatingSystem}.',
    ),
  };

  await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detached,
    runInShell: false,
  );
}
