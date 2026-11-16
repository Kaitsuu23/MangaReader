import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class MangaCoverCacheManager {
  static const key = 'manga_cover_cache_v2';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 365 * 3), // Simpan cache gambar hingga 3 tahun
      maxNrOfCacheObjects: 10000, // Kapasitas 10.000 cover & gambar
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}
