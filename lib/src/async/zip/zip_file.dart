import 'package:archive/archive.dart';
import 'zip_file_header.dart';
import '../async_input_stream.dart';

class AsyncZipFile {
  static const int STORE = 0;
  static const int DEFLATE = 8;
  static const int BZIP2 = 12;

  static const int SIGNATURE = 0x04034b50;

  int signature = SIGNATURE; // 4 bytes
  int version = 0; // 2 bytes
  int flags = 0; // 2 bytes
  int compressionMethod = 0; // 2 bytes
  int lastModFileTime = 0; // 2 bytes
  int lastModFileDate = 0; // 2 bytes
  int? crc32; // 4 bytes
  int? compressedSize; // 4 bytes
  int? uncompressedSize; // 4 bytes
  String filename = ''; // 2 bytes length, n-bytes data
  List<int> extraField = []; // 2 bytes length, n-bytes data
  AsyncZipFileHeader? header;

  Future<AsyncZipFile> init([AsyncInputStreamBase? input, AsyncZipFileHeader? header, String? password]) async {
    this.header = header;
    if (input != null) {
      signature = await input.readUint32();
      if (signature != SIGNATURE) {
        throw ArchiveException('Invalid Zip Signature');
      }


      version = await input.readUint16();
      flags = await input.readUint16();
      compressionMethod = await input.readUint16();
      lastModFileTime = await input.readUint16();
      lastModFileDate = await input.readUint16();
      crc32 = await input.readUint32();
      compressedSize = await input.readUint32();
      uncompressedSize = await input.readUint32();
      final fnLen = await input.readUint16();
      final exLen = await input.readUint16();
      filename = await input.readString(size: fnLen);
      extraField = await input.readBytes(exLen).toUint8List();

      // Read compressedSize bytes for the compressed data.
      //_rawContent = input.subset(null, header!.compressedSize!);
      _rawContent = input.readBytes(header!.compressedSize!);

      if (password != null) {
        _initKeys(password);
        _isEncrypted = true;
      }

      // If bit 3 (0x08) of the flags field is set, then the CRC-32 and file
      // sizes are not known when the header is written. The fields in the
      // local header are filled with zero, and the CRC-32 and size are
      // appended in a 12-byte structure (optionally preceded by a 4-byte
      // signature) immediately after the compressed data:
      if (flags & 0x08 != 0) {
        final sigOrCrc = input.readUint32();
        if (sigOrCrc == 0x08074b50) {
          crc32 = await input.readUint32();
        } else {
          crc32 = await sigOrCrc;
        }

        compressedSize = await input.readUint32();
        uncompressedSize = await input.readUint32();
      }
    }
    return this;
  }

  /// This will decompress the data (if necessary) in order to calculate the
  /// crc32 checksum for the decompressed data and verify it with the value
  /// stored in the zip.
  Future<bool> verifyCrc32() async {
    _computedCrc32 ??= getCrc32(await getContent());
    return _computedCrc32 == crc32;
  }

  /// Get the decompressed content from the file. The file isn't decompressed
  /// until it is requested.
  Future<List<int>> getContent() async {
    if (_content == null) {
      if (_isEncrypted) {
        if (_rawContent.length <= 0) {
          _content = await _rawContent.toUint8List();
          _isEncrypted = false;
        } else {
          _rawContent = await _decodeRawContent(_rawContent);
          _isEncrypted = false;
        }
      }

      if (compressionMethod == DEFLATE) {
        final data = await _rawContent.toUint8List();
        final input = InputStream(data);
        _content = Inflate.buffer(input, uncompressedSize).getBytes();
        compressionMethod = STORE;
      } else {
        _content = await _rawContent.toUint8List();
      }
    }

    return _content!;
  }

  dynamic get rawContent {
    if (_content != null) {
      return _content;
    }
    return _rawContent;
  }

  @override
  String toString() => filename;

  void _initKeys(String password) {
    _keys[0] = 305419896;
    _keys[1] = 591751049;
    _keys[2] = 878082192;
    for (final c in password.codeUnits) {
      _updateKeys(c);
    }
  }

  void _updateKeys(int c) {
    _keys[0] = CRC32(_keys[0], c);
    _keys[1] += _keys[0] & 0xff;
    _keys[1] = _keys[1] * 134775813 + 1;
    _keys[2] = CRC32(_keys[2], _keys[1] >> 24);
  }

  int _decryptByte() {
    final temp = (_keys[2] & 0xffff) | 2;
    return ((temp * (temp ^ 1)) >> 8) & 0xff;
  }

  void _decodeByte(int c) {
    c ^= _decryptByte();
    _updateKeys(c);
  }

  Future<AsyncInputStreamBase> _decodeRawContent(AsyncInputStreamBase input) async {
    for (var i = 0; i < 12; ++i) {
      _decodeByte(await _rawContent.readByte());
    }
    var bytes = await _rawContent.toUint8List();
    for (var i = 0; i < bytes.length; ++i) {
      final temp = bytes[i] ^ _decryptByte();
      _updateKeys(temp);
      bytes[i] = temp;
    }
    return AsyncInputStreamAdapter(InputStream(bytes));
  }

  // Content of the file. If compressionMethod is not STORE, then it is
  // still compressed.
  late AsyncInputStreamBase _rawContent;
  List<int>? _content;
  int? _computedCrc32;
  bool _isEncrypted = false;
  final _keys = <int>[0, 0, 0];
}
