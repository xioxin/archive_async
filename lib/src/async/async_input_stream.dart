import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';

abstract class AsyncInputStreamBase {
  ///  The current read position relative to the start of the buffer.
  int get position;

  set position(int v);

  /// How many bytes are left in the stream.
  int get length;

  /// Is the current position at the end of the stream?
  bool get isEOS;

  /// Asynchronously closes the input stream.
  Future<void> close() async {}

  /// Reset to the beginning of the stream.
  void reset();

  /// Rewind the read head of the stream by the given number of bytes.
  void rewind([int length = 1]);

  /// Move the read position by [count] bytes.
  void skip(int length);

  /// Read [count] bytes from an [offset] of the current read position, without
  /// moving the read position.
  AsyncInputStreamBase peekBytes(int count, [int offset = 0]);

  /// Read a single byte.
  Future<int> readByte();

  /// Read [count] bytes from the stream.
  AsyncInputStreamBase readBytes(int count);

  AsyncInputStreamBase subset([int? position, int? length]);

  /// Read a null-terminated string, or if [len] is provided, that number of
  /// bytes returned as a string.
  Future<String> readString({int? size, bool utf8 = true});

  /// Read a 16-bit word from the stream.
  Future<int> readUint16();

  /// Read a 24-bit word from the stream.
  Future<int> readUint24();

  /// Read a 32-bit word from the stream.
  Future<int> readUint32();

  /// Read a 64-bit word form the stream.
  Future<int> readUint64();

  Future<Uint8List> toUint8List();
}

typedef AsyncInputStreamLoaderFunc = Future<
    Uint8List> Function(AsyncInputStream ais, int offset, int length);

typedef AsyncInputStreamCloseFunc = Future<void> Function();

class LoaderHandle {
  AsyncInputStreamLoaderFunc handle;
  int length;
  AsyncInputStreamCloseFunc? onClose;
  LoaderHandle(this.length, this.handle, [this.onClose]);
}

class AsyncInputStream extends AsyncInputStreamBase {
  LoaderHandle? loader;
  late final AsyncInputStream? parent;
  final int byteOrder;
  late int offset;
  late int start;
  late int _length;

  var _extendData = Map<String, dynamic>();

  dynamic getExtendData(String key) => _extendData[key];
  dynamic getDeepExtendData(String key) => _extendData[key] ?? parent?.getDeepExtendData(key);
  dynamic getRootExtendData(String key) => parent != null ? parent!.getRootExtendData(key): getExtendData(key);

  void setExtendData(String key, dynamic data) {
    _extendData[key] = data;
  }
  void setRootExtendData(String key, dynamic data) {
    if(parent != null) {
      parent!.setRootExtendData(key, data);
    } else {
      setExtendData(key, data);
    }
  }


  AsyncInputStream(LoaderHandle loader, {this.byteOrder = LITTLE_ENDIAN}) {
    // ignore: prefer_initializing_formals
    this.loader = loader;
    _length = loader.length;
    parent = null;
    offset = 0;
    start = 0;
  }

  AsyncInputStream.clone(AsyncInputStream parent, {int start = 0, int? length})
      : byteOrder = parent.byteOrder {
    // ignore: prefer_initializing_formals
    this.parent = parent;
    this.start = start;
    loader = null;
    offset = start;
    _length = length ?? parent.remaining;
  }

  @override
  int get position => offset - start;

  @override
  int get length => _length - (offset - start);

  @override
  bool get isEOS => offset >= (start + _length);

  int get remaining => (start + _length) - offset;

  Future<Uint8List> _loadData(int offset, int length, [AsyncInputStream? ais]) async {
    if (parent != null) {
      final data = await parent!._loadData(offset, length, ais ?? this);
      return data;
    }
    Uint8List data = await loader!.handle(ais ?? this, offset, length);
    return data;
  }

  @override
  AsyncInputStreamBase peekBytes(int count, [int offset = 0]) {
    return subset((this.offset - start) + offset, count);
  }

  @override
  Future<int> readByte() async {
    final data = await _loadData(offset, 1);
    skip(1);
    return data[0];
  }

  @override
  AsyncInputStreamBase readBytes(int count) {
    count = min(count, remaining);
    final bytes = subset(offset - start, count);
    skip(count);
    return bytes;
  }

  @override
  Future<String> readString({int? size, bool utf8 = true}) async {
    if (size == null) {
      List<int> codes = [];
      while (!isEOS) {
        int c = await readByte();
        if (c == 0) {
          return utf8
              ? Utf8Decoder().convert(codes)
              : String.fromCharCodes(codes);
        }
        codes.add(c);
      }
      throw ArchiveException('EOF reached without finding string terminator');
    }
    AsyncInputStreamBase s = readBytes(size);
    Uint8List bytes = await s.toUint8List();
    String str =
    utf8 ? Utf8Decoder().convert(bytes) : String.fromCharCodes(bytes);
    return str;
  }

  @override
  Future<int> readUint16() async {
    final buffer = await _loadData(this.offset, 2);
    skip(2);
    int offset = 0;
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return (b1 << 8) | b2;
    }
    return (b2 << 8) | b1;
  }

  @override
  Future<int> readUint24() async {
    final buffer = await _loadData(this.offset, 3);
    skip(3);
    int offset = 0;
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    int b3 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return b3 | (b2 << 8) | (b1 << 16);
    }
    return b1 | (b2 << 8) | (b3 << 16);
  }

  @override
  Future<int> readUint32() async {
    final buffer = await _loadData(this.offset, 4);
    skip(4);

    int offset = 0;
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    int b3 = buffer[offset++] & 0xff;
    int b4 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
    }
    return (b4 << 24) | (b3 << 16) | (b2 << 8) | b1;
  }

  @override
  Future<int> readUint64() async {
    final buffer = await _loadData(this.offset, 8);
    skip(8);
    int offset = 0;
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    int b3 = buffer[offset++] & 0xff;
    int b4 = buffer[offset++] & 0xff;
    int b5 = buffer[offset++] & 0xff;
    int b6 = buffer[offset++] & 0xff;
    int b7 = buffer[offset++] & 0xff;
    int b8 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return (b1 << 56) |
      (b2 << 48) |
      (b3 << 40) |
      (b4 << 32) |
      (b5 << 24) |
      (b6 << 16) |
      (b7 << 8) |
      b8;
    }
    return (b8 << 56) |
    (b7 << 48) |
    (b6 << 40) |
    (b5 << 32) |
    (b4 << 24) |
    (b3 << 16) |
    (b2 << 8) |
    b1;
  }

  @override
  void reset() {
    offset = start;
  }

  @override
  void rewind([int length = 1]) {
    offset -= length;
    assert(offset >= 0);
    if (offset < 0) {
      offset = 0;
    }
  }

  @override
  void skip(int length) {
    offset += length;
  }

  @override
  AsyncInputStreamBase subset([int? position, int? length]) {
    if (position == null) {
      position = offset;
    } else {
      position += start;
    }
    if (length == null || length < 0) {
      length = _length - (position - start);
    }
    return AsyncInputStream.clone(this, start: position, length: length);
  }

  @override
  Future<Uint8List> toUint8List() async {
    final buffer = await _loadData(offset, length);
    int end = offset + length;
    if (end > buffer.length) {
      end = buffer.length;
    }
    return buffer;
  }

  @override
  set position(int p) {
    offset = p + start;
  }

  @override
  Future<void> close() async {
    _extendData.clear();
    if(loader?.onClose != null) await loader?.onClose!();
    loader = null;
  }
}

class AsyncInputStreamAdapter extends AsyncInputStreamBase {
  InputStreamBase input;

  AsyncInputStreamAdapter(this.input);

  @override
  int get position => input.position;

  @override
  set position(v) => input.position = v;

  @override
  bool get isEOS => input.isEOS;

  @override
  int get length => input.length;

  @override
  AsyncInputStreamBase peekBytes(int count, [int offset = 0]) {
    return AsyncInputStreamAdapter(input.peekBytes(count, offset));
  }

  @override
  Future<int> readByte() async => input.readByte();

  @override
  AsyncInputStreamBase readBytes(int count) {
    return AsyncInputStreamAdapter(input.readBytes(count));
  }

  @override
  Future<String> readString({int? size, bool utf8 = true}) async =>
      input.readString(size: size, utf8: utf8);

  @override
  Future<int> readUint16() async => input.readUint16();

  @override
  Future<int> readUint24() async => input.readUint24();

  @override
  Future<int> readUint32() async => input.readUint32();

  @override
  Future<int> readUint64() async => input.readUint64();

  @override
  void reset() => input.reset();

  @override
  void rewind([int length = 1]) => input.rewind(length);

  @override
  void skip(int length) => input.skip(length);

  @override
  AsyncInputStreamBase subset([int? position, int? length]) {
    return AsyncInputStreamAdapter(input.subset(position, length));
  }

  @override
  Future<Uint8List> toUint8List() async => input.toUint8List();

  @override
  Future<void> close() => input.close();
}
