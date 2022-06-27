import 'dart:io';

import 'package:archive_async/archive_async.dart';

void main() async {
  final File file = File('./cat.zip');
  final fileLength = await file.length();

  final loaderHandle = LoaderHandle(fileLength, (AsyncInputStream ais, int offset, int length) async {
    final handle = await file.open(mode: FileMode.read);
    await handle.setPosition(offset);
    final buff = (await handle.read(length)).buffer.asUint8List();
    await handle.close();
    return buff;
  });

  final inputStream = AsyncInputStream(debounceLoader(loaderHandle));

  final AsyncArchive archive = await AsyncZipDecoder().decodeBuffer(inputStream);

  Directory('out').create(recursive: true);

  // for (final AsyncArchiveFile file in archive) {
  //   String filename = file.name;
  //   print("filename: $filename");
  //   if (file.isFile) {
  //     final data = await file.getContent() as List<int>;
  //     final outFile = File('out/' + filename);
  //     await outFile.create(recursive: true);
  //     await outFile.writeAsBytes(data);
  //   } else {
  //     Directory('out/' + filename).create(recursive: true);
  //   }
  // }

  final futures = archive.map((file) async {
    String filename = file.name;
    if (file.isFile) {
      final data = await file.getContent() as List<int>;
      final outFile = File('out/' + filename);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(data);
    } else {
      Directory('out/' + filename).create(recursive: true);
    }
  });
  await Future.wait(futures);

  inputStream.close();
}
