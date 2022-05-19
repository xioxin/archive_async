import 'package:archive/archive.dart';
import '../async_input_stream.dart';
import 'zip_file_header.dart';
import 'zip_file.dart';

class AsyncZipDirectory {
  // End of Central Directory Record
  static const int signature = 0x06054b50;
  static const int zip64EocdLocatorSignature = 0x07064b50;
  static const int zip64EocdLocatorSize = 20;
  static const int zip64EocdSignature = 0x06064b50;
  static const int zip64EocdSize = 56;

  int filePosition = -1;
  int numberOfThisDisk = 0; // 2 bytes
  int diskWithTheStartOfTheCentralDirectory = 0; // 2 bytes
  int totalCentralDirectoryEntriesOnThisDisk = 0; // 2 bytes
  int totalCentralDirectoryEntries = 0; // 2 bytes
  late int centralDirectorySize; // 4 bytes
  late int centralDirectoryOffset; // 2 bytes
  String zipFileComment = ''; // 2 bytes, n bytes
  // Central Directory
  List<AsyncZipFileHeader> fileHeaders = [];

  AsyncZipDirectory();

  Future<AsyncZipDirectory> read(AsyncInputStreamBase input, {String? password}) async {
    filePosition = await _findSignature(input);
    print(filePosition);
    input.position = filePosition;
    final signature = await input.readUint32(); // ignore: unused_local_variable
    numberOfThisDisk = await input.readUint16();
    diskWithTheStartOfTheCentralDirectory = await input.readUint16();
    totalCentralDirectoryEntriesOnThisDisk = await input.readUint16();
    totalCentralDirectoryEntries = await input.readUint16();
    centralDirectorySize = await input.readUint32();
    centralDirectoryOffset = await input.readUint32();

    final len = await input.readUint16();
    if (len > 0) {
      zipFileComment = await input.readString(size: len, utf8: false);
    }

    await _readZip64Data(input);

    final dirContent =
        input.subset(centralDirectoryOffset, centralDirectorySize);

    while (!dirContent.isEOS) {
      final fileSig = await dirContent.readUint32();
      if (fileSig != AsyncZipFileHeader.SIGNATURE) {
        break;
      }
      fileHeaders.add(await AsyncZipFileHeader().init(dirContent, input, password));
    }

    // for(final header in fileHeaders){
    //   input.position = header.localHeaderOffset!;
    //   print(input.position);
    //
    //   header.file = await AsyncZipFile().init(input, header, password);
    // }

    return this;
  }

  Future<void> _readZip64Data(AsyncInputStreamBase input) async {
    final ip = input.position;
    // Check for zip64 data.

    // Zip64 end of central directory locator
    // signature                       4 bytes  (0x07064b50)
    // number of the disk with the
    // start of the zip64 end of
    // central directory               4 bytes
    // relative offset of the zip64
    // end of central directory record 8 bytes
    // total number of disks           4 bytes

    final locPos = filePosition - zip64EocdLocatorSize;
    if (locPos < 0) {
      return;
    }
    final zip64 = input.subset(locPos, zip64EocdLocatorSize);

    var sig = await zip64.readUint32();
    // If this ins't the signature we're looking for, nothing more to do.
    if (sig != zip64EocdLocatorSignature) {
      input.position = ip;
      return;
    }

    final startZip64Disk = await zip64.readUint32(); // ignore: unused_local_variable
    final zip64DirOffset = await zip64.readUint64();
    final numZip64Disks = await zip64.readUint32(); // ignore: unused_local_variable

    input.position = zip64DirOffset;

    // Zip64 end of central directory record
    // signature                       4 bytes  (0x06064b50)
    // size of zip64 end of central
    // directory record                8 bytes
    // version made by                 2 bytes
    // version needed to extract       2 bytes
    // number of this disk             4 bytes
    // number of the disk with the
    // start of the central directory  4 bytes
    // total number of entries in the
    // central directory on this disk  8 bytes
    // total number of entries in the
    // central directory               8 bytes
    // size of the central directory   8 bytes
    // offset of start of central
    // directory with respect to
    // the starting disk number        8 bytes
    // zip64 extensible data sector    (variable size)
    sig = await input.readUint32();
    if (sig != zip64EocdSignature) {
      input.position = ip;
      return;
    }

    final zip64EOCDSize = await input.readUint64(); // ignore: unused_local_variable
    final zip64Version = await input.readUint16(); // ignore: unused_local_variable
    // ignore: unused_local_variable
    final zip64VersionNeeded = await input.readUint16();
    final zip64DiskNumber = await input.readUint32();
    final zip64StartDisk = await input.readUint32();
    final zip64NumEntriesOnDisk = await input.readUint64();
    final zip64NumEntries = await input.readUint64();
    final dirSize = await input.readUint64();
    final dirOffset = await input.readUint64();

    numberOfThisDisk =  zip64DiskNumber;
    diskWithTheStartOfTheCentralDirectory = zip64StartDisk;
    totalCentralDirectoryEntriesOnThisDisk = zip64NumEntriesOnDisk;
    totalCentralDirectoryEntries = zip64NumEntries;
    centralDirectorySize = dirSize;
    centralDirectoryOffset = dirOffset;

    input.position = ip;
  }

  Future<int> _findSignature(AsyncInputStreamBase input) async {
    final pos = input.position;
    final length = input.length;

    // The directory and archive contents are written to the end of the zip
    // file. We need to search from the end to find these structures,
    // starting with the 'End of central directory' record (EOCD).
    for (var ip = length - 5; ip >= 0; --ip) {
      input.position = ip;
      final sig = await input.readUint32();
      if (sig == signature) {
        input.position = pos;
        return ip;
      }
    }
    throw ArchiveException('Could not find End of Central Directory Record');
  }
}
