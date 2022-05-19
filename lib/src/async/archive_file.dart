import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'async_input_stream.dart';


typedef LoaderContentHandle = Future<AsyncInputStreamBase> Function();


/// A file contained in an Archive.
class AsyncArchiveFile {
  static const int STORE = 0;
  static const int DEFLATE = 8;

  String name;

  /// The uncompressed size of the file
  int size = 0;
  int mode = 420; // octal 644 (-rw-r--r--)
  int ownerId = 0;
  int groupId = 0;
  /// Seconds since epoch
  int lastModTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  /// If false, this is a directory.
  bool isFile = true;
  /// If true, this is a symbolic link to the file specified in nameOfLinkedFile
  bool isSymbolicLink = false;
  /// If this is a symbolic link, this is the path to the file its linked to.
  String nameOfLinkedFile = '';

  /// The crc32 checksum of the uncompressed content.
  int? crc32;
  String? comment;

  /// If false, this file will not be compressed when encoded to an archive
  /// format such as zip.
  bool compress = true;

  int get unixPermissions => mode & 0x1FF;

  Future<AsyncInputStreamBase?> getRawContent() async {
    _rawContent ??= await contentLoader();
    return _rawContent;
  }


  LoaderContentHandle contentLoader;
  AsyncArchiveFile(this.name, this.size, this.contentLoader,
      [this._compressionType = STORE]) {
    name = name.replaceAll('\\', '/');
  }

  void writeContent(OutputStreamBase output, {bool freeMemory = true}) {
    // if (_content is List<int>) {
    //   output.writeBytes(_content as List<int>);
    // } else if (_content is InputStreamBase) {
    //   output.writeInputStream(_content as InputStreamBase);
    // } else if (_rawContent != null) {
    //   decompress();
    //   output.writeBytes(_content as List<int>);
    //   // Release memory
    //   if (freeMemory) {
    //     _content = null;
    //   }
    // }
  }

  /// Get the content of the file, decompressing on demand as necessary.
  Future<dynamic> getContent() async {
    if (_content == null) {
      await decompress();
    }
    return _content;
  }

  void clear() {
    _content = null;
  }

  Future<void> close() async {
    var futures = <Future<void>>[];
    if (_content is InputStreamBase) {
      futures.add((_content as InputStreamBase).close());
    }
    if (_rawContent is InputStreamBase) {
      futures.add((_rawContent as InputStreamBase).close());
    }
    if (_content is AsyncInputStreamBase) {
      futures.add((_content as AsyncInputStreamBase).close());
    }
    if (_rawContent is AsyncInputStreamBase) {
      futures.add((_rawContent as AsyncInputStreamBase).close());
    }
    _content = null;
    _rawContent = null;
    await Future.wait(futures);
  }

  /// If the file data is compressed, decompress it.
  Future decompress([OutputStreamBase? output]) async {
    if (_content == null && (await getRawContent()) != null) {
      if (_compressionType == DEFLATE) {
        if (output != null) {
          final data = await (await getRawContent())!.toUint8List();
          final input = InputStream(data);
          Inflate.stream(input, output);
        } else {
          final data = await (await getRawContent())!.toUint8List();
          _content = inflateBuffer(data);
        }
      } else {
        if (output != null) {
          final data = (await getRawContent())!.toUint8List();
          final input = InputStream(data);
          output.writeInputStream(input);
        } else {
          _content = await (await getRawContent())!.toUint8List();
        }
      }
      _compressionType = STORE;
    }
  }

  /// Is the data stored by this file currently compressed?
  bool get isCompressed => _compressionType != STORE;

  /// What type of compression is the raw data stored in
  int? get compressionType => _compressionType;

  /// Get the content without decompressing it first.
  // AsyncInputStreamBase? getRawContent => _rawContent;

  @override
  String toString() => name;

  int? _compressionType;
  AsyncInputStreamBase? _rawContent;
  dynamic _content;
}
