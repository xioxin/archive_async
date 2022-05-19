// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:archive_async/archive_async.dart';
import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:filesize/filesize.dart';

void main() async {
  /* Accept-Ranges: bytes */

  final dio = Dio();

  int downloadedSize = 0;

  // (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
  //     (client) {
  //   client.findProxy = (url) {
  //     return "PROXY 127.0.0.1:11223";
  //   };
  //   client.badCertificateCallback =
  //       (X509Certificate cert, String host, int port) => true;
  // };

  final url = 'https://files.catbox.moe/tuvxhg.zip';
  final headInfo = await dio.head<dynamic>(url);
  final fileLength =
      int.parse(headInfo.headers['content-length']?.first ?? '0');
  final acceptRanges = headInfo.headers['accept-ranges']?.first ?? '';
  final contentType = headInfo.headers['content-type']?.first ?? '';
  print('fileLength: $fileLength (${filesize(fileLength)})');
  print('acceptRanges: $acceptRanges');
  print('contentType: $contentType');

  final loaderHandle = LoaderHandle(fileLength,
      (AsyncInputStream ais, int offset, int length) async {
    final range = 'bytes=$offset-${offset + length}';
    print('Range: $range, SIZE: ${filesize(length)}');
    final testData = await dio.get<Uint8List>(url,
        options: Options(
          headers: <String, dynamic>{'Range': range},
          responseType: ResponseType.bytes,
        ), onReceiveProgress: (int count, int total) {
      // print('download: ${count / total * 100}');
    });
    downloadedSize += length;
    print('DownloadedSize: $downloadedSize (${filesize(downloadedSize)})');
    return testData.data!;
  });

  final inputStream =
      AsyncInputStream(debounceLoader(loaderHandle, chunkSize: 16 * 1024));

  final AsyncArchive archive =
      await AsyncZipDecoder().decodeBuffer(inputStream);

  Directory('out').create(recursive: true);

  for (final AsyncArchiveFile file in archive) {
    print("filename: ${file.name} (${filesize(file.size)})");
  }

  final data = await archive.first.getContent() as List<int>;
  final file = File(p.join('out', archive.first.name))..writeAsBytesSync(data);
  print("File saved: $file");

  inputStream.close();
}
