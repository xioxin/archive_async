import 'package:archive/archive.dart';
import '../archive.dart';
import '../archive_file.dart';
import '../async_input_stream.dart';
import 'zip_directory.dart';
import 'zip_file.dart';

/// Decode a zip formatted buffer into an [Archive] object.
class AsyncZipDecoder {
  late AsyncZipDirectory directory;

  // AsyncArchive decodeBytes(List<int> data, {bool verify = false, String? password}) {
  //   return decodeBuffer(InputStream(data), verify: verify, password: password);
  // }

  Future<AsyncArchive> decodeBuffer(AsyncInputStreamBase input,
      {bool verify = false, String? password}) async {
    directory = await AsyncZipDirectory().read(input, password: password);
    final archive = AsyncArchive();

    for (final zfh in directory.fileHeaders) {
      // The attributes are stored in base 8
      final mode = zfh.externalFileAttributes!;
      final compress = zfh.compressionMethod != AsyncZipFile.STORE;

      // todo
      // if (verify) {
      //   final computedCrc = getCrc32(await zf.getContent());
      //   if (computedCrc != zf.crc32) {
      //     throw ArchiveException('Invalid CRC for file in archive.');
      //   }
      // }

      var file = AsyncArchiveFile(
          zfh.filename,
          zfh.uncompressedSize!,
          () => zfh
              .getFile(input, password)
              .then((v) => v.rawContent as AsyncInputStreamBase),
          zfh.compressionMethod);

      file.mode = mode >> 16;

      // see https://github.com/brendan-duncan/archive/issues/21
      // UNIX systems has a creator version of 3 decimal at 1 byte offset
      if (zfh.versionMadeBy >> 8 == 3) {
        //final bool isDirectory = file.mode & 0x7000 == 0x4000;
        final isFile = file.mode & 0x3F000 == 0x8000;
        file.isFile = isFile;
      } else {
        file.isFile = !file.name.endsWith('/');
      }

      file.crc32 = zfh.crc32;
      file.compress = compress;
      file.lastModTime = zfh.lastModifiedFileDate << 16 | zfh.lastModifiedFileDate;

      archive.addFile(file);
    }

    return archive;
  }
}
