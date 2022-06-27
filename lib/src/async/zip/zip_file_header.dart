import 'package:archive/archive.dart';
import '../async_input_stream.dart';
import 'zip_file.dart';

class AsyncZipFileHeader {
  static const int SIGNATURE = 0x02014b50;
  int versionMadeBy = 0; // 2 bytes
  int versionNeededToExtract = 0; // 2 bytes
  int generalPurposeBitFlag = 0; // 2 bytes
  int compressionMethod = 0; // 2 bytes
  int lastModifiedFileTime = 0; // 2 bytes
  int lastModifiedFileDate = 0; // 2 bytes
  int? crc32; // 4 bytes
  int? compressedSize; // 4 bytes
  int? uncompressedSize; // 4 bytes
  int? diskNumberStart; // 2 bytes
  int? internalFileAttributes; // 2 bytes
  int? externalFileAttributes; // 4 bytes
  int? localHeaderOffset; // 4 bytes
  String filename = '';
  List<int> extraField = [];
  String fileComment = '';
  AsyncZipFile? file;

  AsyncZipFileHeader();
  Future<AsyncZipFileHeader> init([AsyncInputStreamBase? input, AsyncInputStreamBase? bytes,
                 String? password]) async {
    if (input != null) {
      versionMadeBy = await input.readUint16();
      versionNeededToExtract = await input.readUint16();
      generalPurposeBitFlag = await input.readUint16();
      compressionMethod = await input.readUint16();
      lastModifiedFileTime = await input.readUint16();
      lastModifiedFileDate = await input.readUint16();
      crc32 = await input.readUint32();
      compressedSize = await input.readUint32();
      uncompressedSize = await input.readUint32();
      final fnameLen = await input.readUint16();
      final extraLen = await input.readUint16();
      final commentLen = await input.readUint16();
      diskNumberStart = await input.readUint16();
      internalFileAttributes = await input.readUint16();
      externalFileAttributes = await input.readUint32();
      localHeaderOffset = await input.readUint32();

      if (fnameLen > 0) {
        filename = await input.readString(size: fnameLen);
      }

      if (extraLen > 0) {
        final extra = input.readBytes(extraLen);
        extraField = await extra.toUint8List();

        final id = await extra.readUint16();
        final size = await extra.readUint16();
        if (id == 1) {
          // Zip64 extended information
          // Original
          // Size       8 bytes    Original uncompressed file size
          // Compressed
          // Size       8 bytes    Size of compressed data
          // Relative Header
          // Offset     8 bytes    Offset of local header record
          // Disk Start
          // Number     4 bytes    Number of the disk on which
          // this file starts
          if (size >= 8) {
            uncompressedSize = await extra.readUint64();
          }
          if (size >= 16) {
            compressedSize = await extra.readUint64();
          }
          if (size >= 24) {
            localHeaderOffset = await extra.readUint64();
          }
          if (size >= 28) {
            diskNumberStart = await extra.readUint32();
          }
        }
      }

      if (commentLen > 0) {
        fileComment = await input.readString(size: commentLen);
      }

      // if (bytes != null) {
      //   bytes.position = localHeaderOffset!;
      //   file = await AsyncZipFile().init(bytes, this, password);
      // }
    }
    return this;
  }

  Future<AsyncZipFile> getFile(AsyncInputStreamBase input, [String? password]) async {
    if(file == null) {
      final subInput = input.subset(localHeaderOffset!);
      file = await AsyncZipFile().init(subInput, this, password);
    }
    return file!;
  }

  @override
  String toString() => filename;
}
