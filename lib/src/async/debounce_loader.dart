import 'dart:math';
import 'dart:typed_data';

import './async_input_stream.dart';

bool _overlap(int start1, int end1, int start2, int end2) {
  return start2 < end1 && end2 > start1;
}

LoaderHandle debounceLoader(LoaderHandle loader, {int chunkSize = 1024 * 4}) {

  Uint8List? _cache;
  int? _startBlock;
  int? _endBlock;


  setCache(AsyncInputStream ais, Uint8List data, int startBlock, int endBlock) {
    _cache = data;
    _startBlock = startBlock;
    _endBlock = endBlock;
    // ais.setRootExtendData('DebounceLoaderCache', data);
    // ais.setRootExtendData('DebounceLoaderCacheStartBlock', startBlock);
    // ais.setRootExtendData('DebounceLoaderCacheEndBlock', endBlock);
  }

  Map<String, dynamic> getCache(AsyncInputStream ais) {
    // final cache = ais.getDeepExtendData('DebounceLoaderCache') as Uint8List?;
    // final int? startBlock = ais.getDeepExtendData('DebounceLoaderCacheStartBlock') as int?;
    // final int? endBlock = ais.getDeepExtendData('DebounceLoaderCacheEndBlock') as int?;
    // return <String, dynamic>{
    //   'cache': cache,
    //   'startBlock': startBlock,
    //   'endBlock': endBlock,
    // };

    return <String, dynamic>{
      'cache': _cache,
      'startBlock': _startBlock,
      'endBlock': _endBlock,
    };
  }


  return LoaderHandle(loader.length, (AsyncInputStream ais, int offset, int length) async {
    final startBlock = (offset / chunkSize).floor();
    final endBlock = ((offset + length) / chunkSize).ceil();

    final cacheData = getCache(ais);

    final cache = cacheData['cache'] as Uint8List?;
    final int? cacheStartBlock = cacheData['startBlock'] as int?;
    final int? cacheEndBlock = cacheData['endBlock'] as int?;

    if(cache != null && cacheStartBlock != null && cacheEndBlock != null) {
      if (_overlap(cacheStartBlock, cacheEndBlock, startBlock, endBlock)) {
        Uint8List blockLeft = Uint8List(0);
        Uint8List blockCentre = Uint8List(0);
        Uint8List blockRight = Uint8List(0);
        final blockLeftLength = cacheStartBlock - startBlock;
        if(blockLeftLength > 0) {
          final so = startBlock * chunkSize;
          int eo = (startBlock + blockLeftLength) * chunkSize;
          if(eo > loader.length) eo = loader.length;
          blockLeft = await loader.handle(ais, so, eo - so);
        }

        final blockCentreLength = min((cacheEndBlock - cacheStartBlock), (endBlock - startBlock));
        final blockCentreStart = max(startBlock, cacheStartBlock);
        final centreStartOffset = (blockCentreStart - cacheStartBlock) * chunkSize;
        int centreEndOffset = centreStartOffset + (blockCentreLength * chunkSize);
        if(centreEndOffset > cache.length) centreEndOffset = cache.length;
        blockCentre = cache.sublist(centreStartOffset, centreEndOffset);

        final blockRightLength = endBlock - cacheEndBlock;
        if(blockRightLength > 0) {
          final so = cacheEndBlock * chunkSize;
          int eo = (cacheEndBlock + blockRightLength) * chunkSize;
          if(eo > loader.length) eo = loader.length;
          blockRight = await loader.handle(ais, so, eo - so);
        }

        final data = Uint8List.fromList(blockLeft + blockCentre + blockRight) ;

        setCache(ais, data, startBlock, endBlock);

        int startOffset = startBlock * chunkSize;
        final subStart = offset - startOffset;
        int subEnd = subStart + length;
        return data.sublist(subStart, subEnd);
      }
    }

    int startOffset = startBlock * chunkSize;
    int endOffset = endBlock * chunkSize;
    if(endOffset > loader.length) endOffset = loader.length;
    final data = await loader.handle(ais, startOffset, endOffset - startOffset);

    setCache(ais, data, startBlock, endBlock);

    final subStart = offset - startOffset;
    final subEnd = subStart + length;
    return data.sublist(subStart, subEnd);
  });
}