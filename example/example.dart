import 'dart:io';

import 'package:archive_async/archive_async.dart';

void main() async {
  final file = await File('./cat.zip').open(mode: FileMode.read);

  final fileLength = await file.length();

  final loaderHandle = LoaderHandle(fileLength, (AsyncInputStream ais, int offset, int length) async {
    await file.setPosition(offset);
    final buff = (await file.read(length)).buffer.asUint8List();
    return buff;
  });

  final inputStream = AsyncInputStream(debounceLoader(loaderHandle));

  final AsyncArchive archive = await AsyncZipDecoder().decodeBuffer(inputStream);

  Directory('out').create(recursive: true);

  for (final AsyncArchiveFile file in archive) {
    String filename = file.name;
    print("filename: $filename");
    if (file.isFile) {
      final data = await file.getContent() as List<int>;
      final outFile = File('out/' + filename);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(data);
    } else {
      Directory('out/' + filename).create(recursive: true);
    }
  }

  inputStream.close();
}
