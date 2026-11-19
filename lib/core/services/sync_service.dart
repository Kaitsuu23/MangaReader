import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:dio/dio.dart';
import '../storage/local_storage.dart';
import '../network/parser_channel.dart';
import '../../shared/models/manga_item.dart';
import '../../features/feed/feed_provider.dart';

class SyncResult {
  final bool success;
  final String message;
  final int favoritesCount;
  final int historyCount;

  SyncResult({
    required this.success,
    required this.message,
    this.favoritesCount = 0,
    this.historyCount = 0,
  });
}

class SyncServerStatus {
  final bool isOnline;
  final String message;
  final int? statusCode;

  SyncServerStatus({
    required this.isOnline,
    required this.message,
    this.statusCode,
  });
}

class SyncService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'Kotatsu-Redo/1.0.0 (Flutter)',
      },
    ),
  );

  /// Menormalkan URL server (menghapus trailing slash & menambahkan schema http:// atau https:// jika belum ada)
  static String normalizeUrl(String rawUrl) {
    String url = rawUrl.trim();
    if (url.isEmpty) return LocalStorage.defaultSyncServerUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Membersihkan slug agar konsisten antara format lokal ('slug') dan format server Kotatsu ('/manga/slug/')
  static String _normalizeSlug(String raw) {
    var s = raw.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      try {
        final uri = Uri.parse(s);
        s = uri.path;
      } catch (_) {}
    }
    s = s.replaceAll(RegExp(r'^/+|/+$'), '');
    s = s.replaceFirst(RegExp(r'^manga/', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'^/+|/+$'), '');
    return s;
  }

  /// Menghasilkan ID integer positif 63-bit yang konsisten dari slug/string untuk BIGINT database
  static int hashSlug(String slug) {
    final clean = _normalizeSlug(slug);
    var hash = 0xcbf29ce484222325;
    const fnvPrime = 0x100000001b3;
    final bytes = utf8.encode(clean.isNotEmpty ? clean : slug);
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * fnvPrime) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.remainder(0x7FFFFFFFFFFFFFFF).abs();
  }

  static int _hashSlug(String slug) => hashSlug(slug);

  /// Memotong string agar tidak melebihi kapasitas kolom database kotatsu-syncserver
  static String _truncate(String text, int maxLength) {
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  /// Uji koneksi ke endpoint GET / kotatsu-syncserver (yang mengembalikan 'Alive')
  static Future<SyncServerStatus> testConnection(String rawUrl) async {
    final target = normalizeUrl(rawUrl);
    try {
      final resp = await _dio.get(
        '$target/',
        options: Options(
          validateStatus: (status) => status != null,
        ),
      );

      final body = resp.data?.toString().trim() ?? '';
      if (resp.statusCode == 200 && (body.contains('Alive') || body.isEmpty)) {
        return SyncServerStatus(
          isOnline: true,
          message: 'Server Kotatsu Sync online & siap digunakan (Status 200 - Alive)',
          statusCode: 200,
        );
      } else if (resp.statusCode != null && resp.statusCode! < 500) {
        return SyncServerStatus(
          isOnline: true,
          message: 'Server terhubung (HTTP ${resp.statusCode})',
          statusCode: resp.statusCode,
        );
      } else {
        return SyncServerStatus(
          isOnline: false,
          message: 'Server merespons dengan kesalahan (HTTP ${resp.statusCode})',
          statusCode: resp.statusCode,
        );
      }
    } on DioException catch (e) {
      String detail = 'Koneksi gagal';
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        detail = 'Waktu koneksi habis (Timeout). Periksa apakah port di VPS sudah dibuka (misal port 8080).';
      } else if (e.type == DioExceptionType.connectionError) {
        detail = 'Tidak dapat terhubung ke host. Pastikan IP/domain dan port sudah aktif.';
      } else if (e.message != null) {
        detail = e.message!;
      }
      return SyncServerStatus(
        isOnline: false,
        message: detail,
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return SyncServerStatus(
        isOnline: false,
        message: 'Gagal terhubung: $e',
      );
    }
  }

  /// Ambil profil pengguna saat ini (GET /me)
  static Future<Map<String, dynamic>?> getUserProfile({String? modeId}) async {
    final m = modeId ?? LocalStorage.getActiveContentModeId();
    final token = LocalStorage.getSyncToken(modeId: m);
    if (token == null || token.isEmpty) return null;

    final serverUrl = normalizeUrl(LocalStorage.getSyncServerUrl(modeId: m));
    try {
      final resp = await _dio.get(
        '$serverUrl/me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (status) => status == 200,
        ),
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        return Map<String, dynamic>.from(resp.data as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Masuk atau buat akun baru di server sinkronisasi Kotatsu / VPS
  static Future<void> login({
    required String email,
    required String password,
    String? serverUrl,
    String? modeId,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.length < 5 || cleanEmail.length > 320 || !cleanEmail.contains('@')) {
      throw Exception('Format email tidak valid (harus 5-320 karakter dan mengandung @).');
    }
    if (password.length < 2 || password.length > 24) {
      throw Exception('Kata sandi harus terdiri dari 2 hingga 24 karakter (persyaratan kotatsu-syncserver).');
    }

    final m = modeId ?? LocalStorage.getActiveContentModeId();
    final targetUrl = normalizeUrl(serverUrl ?? LocalStorage.getSyncServerUrl(modeId: m));

    try {
      final response = await _dio.post(
        '$targetUrl/auth',
        data: {
          'email': cleanEmail,
          'password': password,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        String? token;
        if (data is Map && data['token'] != null) {
          token = data['token'].toString();
        } else if (data is String) {
          token = data.replaceAll('"', '').trim();
        }

        if (token != null && token.isNotEmpty) {
          await LocalStorage.setSyncServerUrl(targetUrl, modeId: m);
          await LocalStorage.setSyncEmail(cleanEmail, modeId: m);
          await LocalStorage.setSyncToken(token, modeId: m);
          await LocalStorage.setSyncEnabled(true, modeId: m);
          return;
        }
      }

      if (response.statusCode == 429) {
        throw Exception('Terlalu banyak percobaan masuk (Rate limit). Tunggu 1 menit.');
      }

      String errorMsg = 'Gagal masuk akun';
      if (response.data is Map && response.data['message'] != null) {
        errorMsg = response.data['message'].toString();
      } else if (response.data is String && (response.data as String).isNotEmpty) {
        errorMsg = response.data.toString();
      }

      if (errorMsg.contains('Wrong password')) {
        errorMsg = 'Kata sandi salah atau akun sudah terdaftar dengan kata sandi lain.';
      }
      throw Exception(errorMsg.replaceAll('"', '').trim());
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw Exception('Terlalu banyak percobaan masuk (Rate limit). Tunggu 1 menit.');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Gagal terhubung ke server ($targetUrl). Periksa koneksi internet atau status VPS Anda.');
      }
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('Email atau kata sandi tidak diizinkan.');
      }
      throw Exception('Kesalahan server ($statusCode): ${e.message ?? 'Tidak diketahui'}');
    }
  }

  /// Keluar dari akun sinkronisasi
  static Future<void> logout({String? modeId}) async {
    final m = modeId ?? LocalStorage.getActiveContentModeId();
    await LocalStorage.setSyncToken(null, modeId: m);
    await LocalStorage.setSyncEmail(null, modeId: m);
    await LocalStorage.setSyncEnabled(false, modeId: m);
  }

  /// Mengirim permintaan lupa kata sandi ke server sinkronisasi Kotatsu
  static Future<void> forgotPassword({
    required String email,
    String? serverUrl,
    String? modeId,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Format email tidak valid.');
    }
    final m = modeId ?? LocalStorage.getActiveContentModeId();
    final targetUrl = normalizeUrl(serverUrl ?? LocalStorage.getSyncServerUrl(modeId: m));
    try {
      final response = await _dio.post(
        '$targetUrl/forgot-password',
        data: {'email': cleanEmail},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode != 200 && response.statusCode != 204) {
        String errorMsg = 'Gagal mengirim permintaan reset kata sandi';
        if (response.data is Map && response.data['message'] != null) {
          errorMsg = response.data['message'].toString();
        } else if (response.data is String && (response.data as String).isNotEmpty) {
          errorMsg = response.data.toString();
        }
        throw Exception(errorMsg.replaceAll('"', '').trim());
      }
    } on DioException catch (e) {
      throw Exception('Gagal menghubungi server ($targetUrl): ${e.message ?? 'Kesalahan jaringan'}');
    }
  }

  /// Jalankan sinkronisasi dua arah (Favorit, Kategori, Riwayat)
  static Future<SyncResult> syncNow({
    String? modeId,
    void Function(String step)? onProgress,
  }) async {
    final syncModeId = modeId ?? LocalStorage.getActiveContentModeId();
    final token = LocalStorage.getSyncToken(modeId: syncModeId);
    final serverUrl = normalizeUrl(LocalStorage.getSyncServerUrl(modeId: syncModeId));

    if (token == null || token.isEmpty) {
      return SyncResult(
        success: false,
        message: 'Belum masuk ke akun server sinkronisasi.',
      );
    }

    int favsSynced = 0;
    int histSynced = 0;

    try {
      final authHeaders = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-App-Version': '984',
        'X-Db-Version': '30',
      };

      // 1. SINKRONISASI FAVORIT & KATEGORI
      if (LocalStorage.isSyncFavoritesEnabled(modeId: syncModeId)) {
        onProgress?.call('Menyiapkan kategori & favorit...');
        final localFavs = LocalStorage.getFavorites(modeId: syncModeId);
        final localCategories = LocalStorage.getFavoriteCategories(modeId: syncModeId);
        final savedCatIds = LocalStorage.getSyncCategoryIds(modeId: syncModeId);

        // Bangun daftar kategori yang mematuhi FK (Foreign Key) fk_favourites_category di kotatsu-syncserver
        final categoryMap = <String, int>{...savedCatIds};
        categoryMap['Semua kesukaan'] = 1;
        categoryMap['Semua'] = 1;
        categoryMap['Default'] = 1;

        final categoriesPayload = <Map<String, dynamic>>[
          {
            'category_id': 1,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'sort_key': 0,
            'track': true,
            'title': 'Semua kesukaan',
            'order': 'NEWEST',
            'deleted_at': 0,
            'show_in_lib': true,
          }
        ];

        int nextCatId = 2;
        if (categoryMap.isNotEmpty) {
          final maxId = categoryMap.values.fold(1, (prev, id) => id > prev ? id : prev);
          nextCatId = maxId + 1;
        }

        for (final catTitle in localCategories) {
          final trimmed = catTitle.trim();
          if (trimmed.isEmpty) continue;
          if (categoryMap.containsKey(trimmed)) {
            final existingId = categoryMap[trimmed];
            if (existingId != null && existingId > 1 && !categoriesPayload.any((c) => c['category_id'] == existingId)) {
              categoriesPayload.add({
                'category_id': existingId,
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'sort_key': existingId - 1,
                'track': true,
                'title': _truncate(trimmed, 120),
                'order': 'NEWEST',
                'deleted_at': 0,
                'show_in_lib': true,
              });
            }
            continue;
          }
          final assignedId = nextCatId++;
          categoryMap[trimmed] = assignedId;
          categoriesPayload.add({
            'category_id': assignedId,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'sort_key': assignedId - 1,
            'track': true,
            'title': _truncate(trimmed, 120),
            'order': 'NEWEST',
            'deleted_at': 0,
            'show_in_lib': true,
          });
        }

        // Tambahkan tombstone kategori yang dihapus secara lokal
        final catTombstones = LocalStorage.getDeletedCategoryTombstones(modeId: syncModeId);
        for (final t in catTombstones) {
          final tName = t['name'] as String? ?? '';
          final tId = (t['categoryId'] as num?)?.toInt() ?? categoryMap[tName];
          final delTime = (t['deletedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
          if (tId != null && tId > 1 && !categoriesPayload.any((c) => c['category_id'] == tId)) {
            categoriesPayload.add({
              'category_id': tId,
              'created_at': delTime,
              'sort_key': tId - 1,
              'track': false,
              'title': _truncate(tName, 120),
              'order': 'NEWEST',
              'deleted_at': delTime,
              'show_in_lib': false,
            });
          }
        }

        // Bangun payload favourites dengan foreign key category_id yang valid
        final List<Map<String, dynamic>> favsPayload = [];
        final now = DateTime.now().millisecondsSinceEpoch;

        for (final f in localFavs) {
          final slug = _normalizeSlug(f['slug'] as String? ?? '');
          if (slug.isEmpty) continue;
          final mangaId = _hashSlug(slug);
          final catNames = (f['categories'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
          if (catNames.isEmpty && f['category'] != null && f['category'] != 'Semua' && f['category'] != 'Semua kesukaan') {
            catNames.add(f['category'].toString());
          }
          final catIds = catNames.map((c) => categoryMap[c] ?? 1).toSet();
          if (catIds.isEmpty) catIds.add(1);

          for (final categoryId in catIds) {
            favsPayload.add({
              'manga_id': mangaId,
              'category_id': categoryId,
              'sort_key': 0,
              'pinned': false,
              'created_at': (f['addedAt'] as num?)?.toInt() ?? now,
              'deleted_at': 0,
              'manga': {
                'manga_id': mangaId,
                'title': _truncate(f['title']?.toString() ?? slug, 100),
                'alt_title': null,
                'url': _truncate(slug, 255),
                'public_url': '',
                'rating': 0.0,
                'content_rating': null,
                'cover_url': _truncate(f['cover']?.toString() ?? '', 255),
                'large_cover_url': null,
                'tags': [],
                'state': null,
                'author': null,
                'source': _truncate(f['source']?.toString() ?? 'shinigami', 32),
                'nsfw': false,
              },
            });
          }
        }

        // Tambahkan tombstone favorit yang dihapus secara lokal
        final favTombstones = LocalStorage.getDeletedFavoriteTombstones(modeId: syncModeId);
        for (final t in favTombstones) {
          final rawSlug = t['slug'] as String? ?? '';
          final slug = _normalizeSlug(rawSlug);
          if (slug.isEmpty) continue;
          final mangaId = _hashSlug(slug);
          final delTime = (t['deletedAt'] as num?)?.toInt() ?? now;

          final catNames = (t['categories'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
          if (catNames.isEmpty && t['category'] != null) {
            catNames.add(t['category'].toString());
          }
          final targetCatIds = catNames.map((c) => categoryMap[c] ?? 1).toSet();
          targetCatIds.add(1);
          targetCatIds.addAll(categoryMap.values);

          for (final catId in targetCatIds) {
            favsPayload.add({
              'manga_id': mangaId,
              'category_id': catId,
              'sort_key': 0,
              'pinned': false,
              'created_at': delTime,
              'deleted_at': delTime,
              'manga': {
                'manga_id': mangaId,
                'title': _truncate(t['title']?.toString() ?? slug, 100),
                'alt_title': null,
                'url': _truncate(slug, 255),
                'public_url': '',
                'rating': 0.0,
                'content_rating': null,
                'cover_url': '',
                'large_cover_url': null,
                'tags': [],
                'state': null,
                'author': null,
                'source': _truncate(t['source']?.toString() ?? 'shinigami', 32),
                'nsfw': false,
              },
            });
          }
        }

        onProgress?.call('Mengunggah favorit ke server...');
        final favResp = await _dio.post(
          '$serverUrl/resource/favourites',
          data: {
            'categories': categoriesPayload,
            'favourites': favsPayload,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          options: Options(
            headers: authHeaders,
            validateStatus: (status) => status == 200 || status == 204,
          ),
        );

        if (favResp.statusCode == 200 || favResp.statusCode == 204) {
          await LocalStorage.clearDeletedFavoriteTombstones(modeId: syncModeId);
          await LocalStorage.clearDeletedCategoryTombstones(modeId: syncModeId);
        }

        // Jika 200 OK: merge perubahan yang dikembalikan dari server
        if (favResp.statusCode == 200 && favResp.data is Map) {
          final resData = favResp.data as Map;

          final Map<int, String> categoryIdToName = {
            for (final entry in categoryMap.entries) entry.value: entry.key,
          };

          // Merge kategori dari server
          if (resData['categories'] is List) {
            final remoteCats = (resData['categories'] as List).cast<Map>();
            final newCats = <String>{...localCategories};
            final deletedCatNames = catTombstones.map((t) => t['name'] as String? ?? '').toSet();
            final deletedCatIds = catTombstones.map((t) => (t['categoryId'] as num?)?.toInt()).whereType<int>().toSet();

            for (final c in remoteCats) {
              final catId = (c['category_id'] as num?)?.toInt() ?? (c['id'] as num?)?.toInt();
              final t = c['title'] as String?;
              final del = (c['deleted_at'] as num?)?.toInt() ?? 0;
              if (t != null && t.isNotEmpty) {
                if (catId != null) {
                  categoryMap[t] = catId;
                  categoryIdToName[catId] = t;
                }
                if (t != 'Semua kesukaan' && t != 'Semua' && t != 'Default') {
                  final isTombstone = deletedCatNames.contains(t) || (catId != null && deletedCatIds.contains(catId));
                  if (del == 0 && !isTombstone) {
                    newCats.add(t);
                  } else {
                    newCats.remove(t);
                    categoryMap.remove(t);
                  }
                }
              }
            }
            await LocalStorage.saveFavoriteCategories(newCats.toList(), modeId: syncModeId);
            await LocalStorage.saveSyncCategoryIds(categoryMap, modeId: syncModeId);
          }

          // Merge favourites dari server (termasuk penanganan tombstone deleted_at)
          if (resData['favourites'] is List) {
            final remoteFavs = (resData['favourites'] as List).cast<Map>();
            final deletedTombstoneSlugs = favTombstones
                .map((t) => _normalizeSlug(t['slug'] as String? ?? '').toLowerCase())
                .where((s) => s.isNotEmpty)
                .toSet();
            final deletedTombstoneIds = favTombstones
                .map((t) => _hashSlug(t['slug'] as String? ?? ''))
                .toSet();

            // Kelompokkan remote favourites berdasarkan slug manga
            final Map<String, List<Map>> groupedRemoteFavs = {};
            for (final f in remoteFavs) {
              if (f['manga'] is Map) {
                final m = f['manga'] as Map;
                final rawSlug = (m['url'] as String?)?.isNotEmpty == true
                    ? m['url'] as String
                    : (m['title'] as String? ?? '');
                final slug = _normalizeSlug(rawSlug);
                if (slug.isNotEmpty) {
                  groupedRemoteFavs.putIfAbsent(slug, () => []).add(f);
                }
              }
            }

            for (final entry in groupedRemoteFavs.entries) {
              final slug = entry.key;
              final rows = entry.value;

              final firstRow = rows.first;
              final mangaId = (firstRow['manga_id'] as num?)?.toInt() ?? 0;
              final isLocallyDeleted = deletedTombstoneSlugs.contains(slug.toLowerCase()) ||
                  (mangaId != 0 && deletedTombstoneIds.contains(mangaId));

              // Periksa apakah semua entri untuk manga ini berstatus terhapus
              final hasActiveEntry = rows.any((r) => ((r['deleted_at'] as num?)?.toInt() ?? 0) == 0);

              if (!hasActiveEntry || isLocallyDeleted) {
                final hasActiveLocalFav = LocalStorage.isFavorite(slug, modeId: syncModeId);
                if (!hasActiveLocalFav) {
                  await LocalStorage.removeFavorite(slug, recordTombstone: false, modeId: syncModeId);
                } else if (!hasActiveEntry && !isLocallyDeleted) {
                  // Entri memang dihapus secara remote dari perangkat lain
                  await LocalStorage.removeFavorite(slug, recordTombstone: false, modeId: syncModeId);
                }
              } else {
                final m = firstRow['manga'] as Map;
                final rawTitle = (m['title'] as String?)?.trim();
                String? rawCover = (m['cover_url'] as String?)?.trim();
                if (rawCover == null || rawCover.isEmpty) {
                  rawCover = (m['large_cover_url'] as String?)?.trim();
                }
                if (rawCover == null || rawCover.isEmpty) {
                  rawCover = (m['cover'] as String?)?.trim();
                }
                if (rawCover == null || rawCover.isEmpty) {
                  rawCover = (m['thumbnail'] as String?)?.trim();
                }

                final existingFav = LocalStorage.getFavorite(slug, modeId: syncModeId);
                final existingHist = LocalStorage.getHistoryItem(slug, modeId: syncModeId);

                String resolvedTitle = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : '';
                if (resolvedTitle.isEmpty || resolvedTitle == slug) {
                  final exTitle = (existingFav?['title'] as String?)?.trim() ?? (existingHist?['title'] as String?)?.trim();
                  if (exTitle != null && exTitle.isNotEmpty && exTitle != slug) {
                    resolvedTitle = exTitle;
                  } else {
                    resolvedTitle = MangaItem.formatTitleFromSlug(slug);
                  }
                }

                String? resolvedCover = (rawCover != null && rawCover.isNotEmpty) ? rawCover : null;
                if (resolvedCover == null) {
                  final exCover = (existingFav?['cover'] as String?)?.trim() ?? (existingHist?['cover'] as String?)?.trim();
                  if (exCover != null && exCover.isNotEmpty) {
                    resolvedCover = exCover;
                  }
                }

                final rawSource = (m['source'] as String?)?.trim();
                final source = (rawSource != null && rawSource.isNotEmpty)
                    ? rawSource
                    : (existingFav?['source'] as String? ?? existingHist?['source'] as String? ?? 'shinigami');

                final catNames = <String>[];
                for (final r in rows) {
                  final del = (r['deleted_at'] as num?)?.toInt() ?? 0;
                  if (del == 0) {
                    final catId = (r['category_id'] as num?)?.toInt() ?? 1;
                    final catName = categoryIdToName[catId];
                    if (catName != null &&
                        catName.isNotEmpty &&
                        catName != 'Semua kesukaan' &&
                        catName != 'Semua' &&
                        catName != 'Default') {
                      if (!catNames.contains(catName)) {
                        catNames.add(catName);
                      }
                    }
                  }
                }

                final firstCreatedAt = (firstRow['created_at'] as num?)?.toInt();
                await LocalStorage.saveFavorite(
                  slug: slug,
                  title: resolvedTitle,
                  cover: resolvedCover,
                  source: source,
                  category: catNames.isNotEmpty ? catNames.first : 'Semua kesukaan',
                  categories: catNames,
                  addedAt: existingFav != null ? (existingFav['addedAt'] as num?)?.toInt() : firstCreatedAt,
                  modeId: syncModeId,
                );
              }
            }
          }
        }
        favsSynced = LocalStorage.getFavorites(modeId: syncModeId).length;
      }

      // 2. SINKRONISASI RIWAYAT BACAAN
      if (LocalStorage.isSyncHistoryEnabled(modeId: syncModeId)) {
        onProgress?.call('Menyiapkan riwayat baca...');
        final localHist = LocalStorage.getHistory(modeId: syncModeId);

        final histPayload = localHist.map((h) {
          final slug = h['slug'] as String? ?? '';
          final chSlug = h['chapterSlug'] as String? ?? '';
          final mangaId = _hashSlug(slug);
          final chId = _hashSlug(chSlug);
          final totalPages = (h['totalPages'] as num?)?.toInt() ?? 1;
          final totalChapters = (h['totalChapters'] as num?)?.toInt() ?? totalPages;
          final page = (h['page'] as num?)?.toInt() ?? 1;
          final pct = (h['percent'] as num?)?.toDouble() ??
              (totalPages > 0 ? (page / totalPages).clamp(0.0, 1.0) : 0.0);
          final scrollRatio = (h['pageOffsetRatio'] as num?)?.toDouble() ??
              ((h['scroll'] as num?)?.toDouble() ?? 0.0);
          final createdAt = (h['createdAt'] as num?)?.toInt() ??
              (h['updatedAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch;
          final updatedAt = (h['updatedAt'] as num?)?.toInt() ?? createdAt;

          // Field posisi baca tambahan untuk restore webtoon yang akurat
          final scrollOffset = (h['scrollOffset'] as num?)?.toInt() ?? 0;
          final pageOffset = (h['pageOffset'] as num?)?.toInt() ?? 0;

          // pageHeights: Map<int, double> → encode ke JSON string untuk server
          String pageHeightsJson = '';
          final rawHeights = h['pageHeights'];
          if (rawHeights is Map && rawHeights.isNotEmpty) {
            try {
              final stringKeyMap = rawHeights.map((k, v) => MapEntry(k.toString(), v));
              pageHeightsJson = jsonEncode(stringKeyMap);
            } catch (_) {}
          }

          return {
            'manga_id': mangaId,
            'chapter_id': chId,
            'page': page,
            'scroll': scrollRatio.clamp(0.0, 1.0),
            'percent': pct,
            'chapters': totalChapters,
            'created_at': createdAt,
            'updated_at': updatedAt,
            'deleted_at': 0,
            'scroll_offset': scrollOffset,
            'page_offset': pageOffset,
            'total_pages': totalPages,
            'page_heights': pageHeightsJson,
            'manga': {
              'manga_id': mangaId,
              'title': _truncate(h['title']?.toString() ?? slug, 100),
              'alt_title': null,
              'url': _truncate(slug, 255),
              'public_url': '',
              'rating': 0.0,
              'content_rating': null,
              'cover_url': _truncate(h['cover']?.toString() ?? '', 255),
              'large_cover_url': null,
              'tags': [],
              'state': null,
              'author': null,
              'source': _truncate(h['source']?.toString() ?? 'shinigami', 32),
              'nsfw': false,
            },
          };
        }).toList();

        // Tambahkan tombstone riwayat yang dihapus secara lokal
        final histTombstones = LocalStorage.getDeletedHistoryTombstones(modeId: syncModeId);
        for (final t in histTombstones) {
          final slug = t['slug'] as String? ?? '';
          if (slug.isEmpty) continue;
          final mangaId = _hashSlug(slug);
          final delTime = (t['deletedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
          histPayload.add({
            'manga_id': mangaId,
            'chapter_id': 0,
            'page': 1,
            'scroll': 0.0,
            'percent': 1.0,
            'chapters': 1,
            'created_at': delTime,
            'updated_at': delTime,
            'deleted_at': delTime,
            'manga': {
              'manga_id': mangaId,
              'title': _truncate(t['title']?.toString() ?? slug, 100),
              'alt_title': null,
              'url': _truncate(slug, 255),
              'public_url': '',
              'rating': 0.0,
              'content_rating': null,
              'cover_url': '',
              'large_cover_url': null,
              'tags': [],
              'state': null,
              'author': null,
              'source': _truncate(t['source']?.toString() ?? 'shinigami', 32),
              'nsfw': false,
            },
          });
        }

        onProgress?.call('Mengunggah riwayat baca ke server...');
        final histResp = await _dio.post(
          '$serverUrl/resource/history',
          data: {
            'history': histPayload,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          options: Options(
            headers: authHeaders,
            validateStatus: (status) => status == 200 || status == 204,
          ),
        );

        if (histResp.statusCode == 200 || histResp.statusCode == 204) {
          await LocalStorage.clearDeletedHistoryTombstones(modeId: syncModeId);
        }

        if (histResp.statusCode == 200 && histResp.data is Map) {
          final resData = histResp.data as Map;
          if (resData['history'] is List) {
            final remoteHist = (resData['history'] as List).cast<Map>();
            final deletedHistSlugs = histTombstones
                .map((t) => _normalizeSlug(t['slug'] as String? ?? '').toLowerCase())
                .where((s) => s.isNotEmpty)
                .toSet();
            final deletedHistIds = histTombstones
                .map((t) => _hashSlug(t['slug'] as String? ?? ''))
                .toSet();

            for (final h in remoteHist) {
              final del = (h['deleted_at'] as num?)?.toInt() ?? 0;
              if (h['manga'] is Map) {
                final m = h['manga'] as Map;
                final rawSlug = (m['url'] as String?)?.isNotEmpty == true
                    ? m['url'] as String
                    : (m['title'] as String? ?? '');
                final slug = _normalizeSlug(rawSlug);

                if (slug.isNotEmpty) {
                  final mangaId = (h['manga_id'] as num?)?.toInt() ?? _hashSlug(slug);
                  final isLocallyDeleted = deletedHistSlugs.contains(slug.toLowerCase()) ||
                      deletedHistIds.contains(mangaId);

                  if (del != 0 || isLocallyDeleted) {
                    final hasActiveLocalHist = LocalStorage.getHistoryItem(slug, modeId: syncModeId) != null;
                    if (!hasActiveLocalHist) {
                      await LocalStorage.deleteHistoryItem(slug, recordTombstone: false, modeId: syncModeId);
                    } else if (del != 0 && !isLocallyDeleted) {
                      // Riwayat memang dihapus secara remote dari perangkat lain
                      await LocalStorage.deleteHistoryItem(slug, recordTombstone: false, modeId: syncModeId);
                    }
                  } else {
                    final rawTitle = (m['title'] as String?)?.trim();
                    String? rawCover = (m['cover_url'] as String?)?.trim();
                    if (rawCover == null || rawCover.isEmpty) {
                      rawCover = (m['large_cover_url'] as String?)?.trim();
                    }
                    if (rawCover == null || rawCover.isEmpty) {
                      rawCover = (m['cover'] as String?)?.trim();
                    }
                    if (rawCover == null || rawCover.isEmpty) {
                      rawCover = (m['thumbnail'] as String?)?.trim();
                    }

                    final existing = LocalStorage.getHistoryItem(slug, modeId: syncModeId);
                    final existingFav = LocalStorage.getFavorite(slug, modeId: syncModeId);

                    String title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : '';
                    if (title.isEmpty || title == slug) {
                      final exTitle = (existing?['title'] as String?)?.trim() ?? (existingFav?['title'] as String?)?.trim();
                      if (exTitle != null && exTitle.isNotEmpty && exTitle != slug) {
                        title = exTitle;
                      } else {
                        title = MangaItem.formatTitleFromSlug(slug);
                      }
                    }

                    String? cover = (rawCover != null && rawCover.isNotEmpty) ? rawCover : null;
                    if (cover == null) {
                      final exCover = (existing?['cover'] as String?)?.trim() ?? (existingFav?['cover'] as String?)?.trim();
                      if (exCover != null && exCover.isNotEmpty) {
                        cover = exCover;
                      }
                    }

                    final rawSource = (m['source'] as String?)?.trim();
                    final source = (rawSource != null && rawSource.isNotEmpty)
                        ? rawSource.toLowerCase()
                        : (existing?['source'] as String? ?? existingFav?['source'] as String? ?? 'shinigami').toLowerCase();

                    final page = (h['page'] as num?)?.toInt() ?? 1;
                    final totalChapters = (h['chapters'] as num?)?.toInt() ?? 1;
                    final scroll = (h['scroll'] as num?)?.toDouble() ?? 0.0;
                    final percent = (h['percent'] as num?)?.toDouble() ?? 0.0;
                    final chapterIdRaw = (h['chapter_id'] ?? '').toString();
                    final remoteCreatedAt = (h['created_at'] as num?)?.toInt();
                    final remoteUpdatedAt = (h['updated_at'] as num?)?.toInt() ?? remoteCreatedAt;

                    String resolvedChapterSlug = chapterIdRaw;
                    String resolvedChapterTitle = '';
                    if (existing != null) {
                      final exSlug = existing['chapterSlug']?.toString() ?? '';
                      final exTitle = existing['chapterTitle']?.toString() ?? '';
                      if (exSlug.isNotEmpty && int.tryParse(exSlug) == null) {
                        resolvedChapterSlug = exSlug;
                        resolvedChapterTitle = exTitle;
                      }
                    }

                    final exChapterNumber = (existing?['chapterNumber'] as num?)?.toInt();
                    int? resolvedChapterNumber;
                    if (exChapterNumber != null && exChapterNumber > 0) {
                      resolvedChapterNumber = exChapterNumber;
                    } else if (percent > 0 && totalChapters > 0) {
                      final chVal = percent * totalChapters;
                      final chIdx = chVal.floor().clamp(0, totalChapters - 1);
                      resolvedChapterNumber = chIdx + 1;
                    }

                    final exTotalPages = (existing?['totalPages'] as num?)?.toInt();
                    int resolvedTotalPages = 0;
                    if (exTotalPages != null && exTotalPages > 1) {
                      resolvedTotalPages = exTotalPages;
                    } else if (percent > 0 && totalChapters > 0 && page > 0) {
                      // percent = (chapterIndex + page / totalPages) / totalChapters
                      // chVal = percent * totalChapters = chapterIndex + pageFrac
                      final chVal = percent * totalChapters;
                      final chIdx = chVal.floor();
                      final pageFrac = chVal - chIdx;
                      if (pageFrac > 0.005 && pageFrac <= 1.0) {
                        final estTotal = (page / pageFrac).round();
                        if (estTotal >= page && estTotal <= 300) {
                          resolvedTotalPages = estTotal;
                        }
                      }
                    }
                    // Prioritaskan total_pages dari server kalau tersedia
                    final serverTotalPages = (h['total_pages'] as num?)?.toInt() ?? 0;
                    if (serverTotalPages > resolvedTotalPages) {
                      resolvedTotalPages = serverTotalPages;
                    }

                    if (resolvedChapterTitle.isEmpty && resolvedChapterNumber != null && resolvedChapterNumber > 0) {
                      resolvedChapterTitle = 'Chapter $resolvedChapterNumber';
                    }

                    // Baca scroll_offset dan page_offset dari server (lebih akurat dari estimasi)
                    final serverScrollOffset = (h['scroll_offset'] as num?)?.toDouble() ?? 0.0;
                    final serverPageOffset = (h['page_offset'] as num?)?.toDouble() ?? 0.0;
                    final exScrollOffset = (existing?['scrollOffset'] as num?)?.toDouble() ?? 0.0;
                    final exPageOffset = (existing?['pageOffset'] as num?)?.toDouble() ?? 0.0;
                    // Server wins kalau punya nilai > 0, fallback ke local existing
                    final resolvedScrollOffset = serverScrollOffset > 0 ? serverScrollOffset : exScrollOffset;
                    final resolvedPageOffset = serverPageOffset > 0 ? serverPageOffset : exPageOffset;

                    final exRatio = (existing?['pageOffsetRatio'] as num?)?.toDouble();
                    final resolvedRatio = (scroll > 0.0 && scroll <= 1.0) ? scroll : exRatio;

                    // Decode page_heights JSON string dari server → Map<int, double>
                    Map<int, double>? resolvedPageHeights;
                    final serverPageHeightsStr = (h['page_heights'] as String?) ?? '';
                    if (serverPageHeightsStr.isNotEmpty) {
                      try {
                        final decoded = jsonDecode(serverPageHeightsStr);
                        if (decoded is Map) {
                          resolvedPageHeights = {};
                          decoded.forEach((k, v) {
                            final idx = int.tryParse(k.toString());
                            final val = (v as num?)?.toDouble();
                            if (idx != null && val != null) {
                              resolvedPageHeights![idx] = val;
                            }
                          });
                        }
                      } catch (_) {}
                    }
                    // Fallback ke local existing pageHeights kalau server kosong
                    if ((resolvedPageHeights == null || resolvedPageHeights.isEmpty) &&
                        existing?['pageHeights'] is Map) {
                      resolvedPageHeights = (existing!['pageHeights'] as Map).map(
                        (k, v) => MapEntry(
                          int.tryParse(k.toString()) ?? 0,
                          (v as num).toDouble(),
                        ),
                      );
                    }

                    await LocalStorage.saveHistory(
                      slug: slug,
                      title: title,
                      cover: cover,
                      source: source,
                      chapterSlug: resolvedChapterSlug,
                      chapterTitle: resolvedChapterTitle,
                      page: page,
                      totalPages: resolvedTotalPages,
                      pageOffsetRatio: resolvedRatio,
                      scrollOffset: resolvedScrollOffset,
                      pageOffset: resolvedPageOffset,
                      pageHeights: resolvedPageHeights,
                      percent: percent,
                      totalChapters: totalChapters > 0 ? totalChapters : null,
                      chapterNumber: resolvedChapterNumber,
                      createdAt: remoteCreatedAt,
                      updatedAt: remoteUpdatedAt,
                      modeId: syncModeId,
                    );

                    histSynced++;
                  }
                }
              }
            }
          }
        }
        histSynced = LocalStorage.getHistory(modeId: syncModeId).length;
      }

      await LocalStorage.setLastSyncTime(DateTime.now().millisecondsSinceEpoch, modeId: syncModeId);

      // Trigger background auto-healing for any favorite manga missing cover/title
      unawaited(healMissingFavorites(modeId: syncModeId));

      // Push latest reading positions from server to Android tracker config
      unawaited(FeedUpdateNotifier.syncTrackedMangaConfig());

      return SyncResult(
        success: true,
        message: 'Sinkronisasi berhasil! ($favsSynced favorit, $histSynced riwayat)',
        favoritesCount: favsSynced,
        historyCount: histSynced,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await logout(modeId: syncModeId);
        return SyncResult(
          success: false,
          message: 'Sesi akun telah berakhir (401). Silakan masuk kembali.',
        );
      }
      if (e.response?.statusCode == 429) {
        return SyncResult(
          success: false,
          message: 'Terlalu banyak permintaan ke server (Rate limit 429). Coba lagi nanti.',
        );
      }
      final serverMsg = e.response?.data?.toString();
      return SyncResult(
        success: false,
        message: 'Gagal menyinkronkan: ${serverMsg != null && serverMsg.isNotEmpty ? serverMsg : (e.message ?? 'Kesalahan koneksi')}',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Gagal menyinkronkan: $e',
      );
    }
  }

  /// Background auto-healing to fetch authentic cover and title for favorites that have missing covers or raw slug titles.
  static Future<void> healMissingFavorites({String? modeId}) async {
    final m = modeId ?? LocalStorage.getActiveContentModeId();
    try {
      final favorites = LocalStorage.getFavorites(modeId: m);
      final toHeal = favorites.where((f) {
        final cover = f['cover'] as String?;
        final title = (f['title'] as String?)?.trim() ?? '';
        final slug = (f['slug'] as String?)?.trim() ?? '';
        final hasCover = cover != null && cover.trim().isNotEmpty;
        final isTitleSlug = title.isEmpty ||
            title == slug ||
            (!title.contains(' ') && (title.contains('-') || title.contains('_')));
        return !hasCover || isTitleSlug;
      }).toList();

      if (toHeal.isEmpty) return;

      // Tunggu 30 detik setelah sync selesai sebelum mulai healing,
      // agar request detail screen dari user tidak terganggu.
      await Future.delayed(const Duration(seconds: 30));

      // Batasi maksimal 3 item per sesi healing agar tidak membanjiri source
      // dengan request berat saat user aktif menggunakan app.
      final limited = toHeal.take(3).toList();

      final parser = ParserChannel();
      for (final item in limited) {
        final slug = item['slug'] as String? ?? '';
        final source = (item['source'] as String?)?.trim().isNotEmpty == true
            ? (item['source'] as String).trim()
            : LocalStorage.getActiveSource(modeId: m);
        if (slug.isEmpty) continue;
        try {
          final details = await parser.getDetails(source, slug);
          if (details.title.isNotEmpty || (details.cover != null && details.cover!.isNotEmpty)) {
            await LocalStorage.updateFavoriteMetadata(
              slug: slug,
              title: details.title.isNotEmpty ? details.title : null,
              cover: (details.cover != null && details.cover!.isNotEmpty) ? details.cover : null,
              type: details.type,
              latestChapter: details.chapters.isNotEmpty ? details.chapters.first.title : null,
              modeId: m,
            );
          }
        } catch (_) {
          // Ignore failures gracefully in background healing
        }
        // Jeda 2 detik antar request agar tidak flood source dan tidak
        // mengganggu request lain yang sedang berjalan (detail screen, dll).
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (_) {}
  }

  /// Menghapus seluruh riwayat bacaan dari server sinkronisasi (cloud) dan perangkat lokal
  static Future<SyncResult> clearServerHistory({String? modeId}) async {
    final syncModeId = modeId ?? LocalStorage.getActiveContentModeId();
    final token = LocalStorage.getSyncToken(modeId: syncModeId);
    final serverUrl = normalizeUrl(LocalStorage.getSyncServerUrl(modeId: syncModeId));

    if (token == null || token.isEmpty) {
      return SyncResult(
        success: false,
        message: 'Belum masuk ke akun server sinkronisasi.',
      );
    }

    try {
      final authHeaders = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-App-Version': '984',
        'X-Db-Version': '30',
      };

      // 1. Ambil seluruh riwayat yang ada di server saat ini
      final getResp = await _dio.get(
        '$serverUrl/resource/history',
        options: Options(
          headers: authHeaders,
          validateStatus: (status) => status == 200 || status == 204,
        ),
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final Set<int> processedMangaIds = {};
      final List<Map<String, dynamic>> deletePayload = [];

      if (getResp.statusCode == 200 && getResp.data is Map) {
        final resData = getResp.data as Map;
        if (resData['history'] is List) {
          final remoteHist = (resData['history'] as List).cast<Map>();
          for (final h in remoteHist) {
            final mangaId = (h['manga_id'] as num?)?.toInt() ?? 0;
            if (mangaId != 0 && processedMangaIds.add(mangaId)) {
              final mangaObj = h['manga'] is Map ? h['manga'] as Map : null;
              deletePayload.add({
                'manga_id': mangaId,
                'chapter_id': h['chapter_id'] ?? 0,
                'page': h['page'] ?? 1,
                'scroll': h['scroll'] ?? 0.0,
                'percent': h['percent'] ?? 1.0,
                'chapters': h['chapters'] ?? 1,
                'created_at': (h['created_at'] as num?)?.toInt() ?? now,
                'updated_at': now,
                'deleted_at': now,
                'manga': mangaObj ?? {
                  'manga_id': mangaId,
                  'title': 'Deleted Manga',
                  'alt_title': null,
                  'url': '',
                  'public_url': '',
                  'rating': 0.0,
                  'content_rating': null,
                  'cover_url': '',
                  'large_cover_url': null,
                  'tags': [],
                  'state': null,
                  'author': null,
                  'source': 'shinigami',
                  'nsfw': false,
                },
              });
            }
          }
        }
      }

      // 2. Tambahkan juga seluruh riwayat lokal
      final localHist = LocalStorage.getHistory(modeId: syncModeId);
      for (final h in localHist) {
        final slug = h['slug'] as String? ?? '';
        final mangaId = _hashSlug(slug);
        if (processedMangaIds.add(mangaId)) {
          final chSlug = h['chapterSlug'] as String? ?? '';
          deletePayload.add({
            'manga_id': mangaId,
            'chapter_id': _hashSlug(chSlug),
            'page': 1,
            'scroll': 0.0,
            'percent': 1.0,
            'chapters': 1,
            'created_at': now,
            'updated_at': now,
            'deleted_at': now,
            'manga': {
              'manga_id': mangaId,
              'title': _truncate(h['title']?.toString() ?? slug, 100),
              'alt_title': null,
              'url': _truncate(slug, 255),
              'public_url': '',
              'rating': 0.0,
              'content_rating': null,
              'cover_url': _truncate(h['cover']?.toString() ?? '', 255),
              'large_cover_url': null,
              'tags': [],
              'state': null,
              'author': null,
              'source': _truncate(h['source']?.toString() ?? 'shinigami', 32),
              'nsfw': false,
            },
          });
        }
      }

      // 3. Kirim tombstone ke server jika ada item
      if (deletePayload.isNotEmpty) {
        await _dio.post(
          '$serverUrl/resource/history',
          data: {
            'history': deletePayload,
            'timestamp': now,
          },
          options: Options(
            headers: authHeaders,
            validateStatus: (status) => status == 200 || status == 204,
          ),
        );
      }

      // 4. Bersihkan riwayat lokal & tombstones
      await LocalStorage.clearHistoryDirect(modeId: syncModeId);
      await LocalStorage.clearDeletedHistoryTombstones(modeId: syncModeId);

      return SyncResult(
        success: true,
        message: 'Berhasil menghapus seluruh riwayat bacaan dari server & perangkat.',
        historyCount: deletePayload.length,
      );
    } on DioException catch (e) {
      return SyncResult(
        success: false,
        message: 'Gagal menghapus riwayat di server: ${e.message ?? 'Kesalahan koneksi'}',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Gagal menghapus riwayat di server: $e',
      );
    }
  }

  /// Menghapus seluruh komik favorit dari server sinkronisasi (cloud) dan perangkat lokal
  static Future<SyncResult> clearServerFavorites({String? modeId}) async {
    final syncModeId = modeId ?? LocalStorage.getActiveContentModeId();
    final token = LocalStorage.getSyncToken(modeId: syncModeId);
    final serverUrl = normalizeUrl(LocalStorage.getSyncServerUrl(modeId: syncModeId));

    if (token == null || token.isEmpty) {
      return SyncResult(
        success: false,
        message: 'Belum masuk ke akun server sinkronisasi.',
      );
    }

    try {
      final authHeaders = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-App-Version': '984',
        'X-Db-Version': '30',
      };

      // 1. Ambil seluruh favorit yang ada di server saat ini
      final getResp = await _dio.get(
        '$serverUrl/resource/favourites',
        options: Options(
          headers: authHeaders,
          validateStatus: (status) => status == 200 || status == 204,
        ),
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final Set<String> processedKeys = {};
      final List<Map<String, dynamic>> deleteFavsPayload = [];
      final List<Map<String, dynamic>> categoriesPayload = [];

      if (getResp.statusCode == 200 && getResp.data is Map) {
        final resData = getResp.data as Map;

        // Pertahankan seluruh kategori (kategori tidak dihapus saat hapus favorit)
        if (resData['categories'] is List) {
          final remoteCats = (resData['categories'] as List).cast<Map>();
          for (final c in remoteCats) {
            final catId = (c['category_id'] as num?)?.toInt() ?? 1;
            categoriesPayload.add({
              'category_id': catId,
              'created_at': (c['created_at'] as num?)?.toInt() ?? now,
              'sort_key': (c['sort_key'] as num?)?.toInt() ?? 0,
              'track': c['track'] ?? (catId == 1),
              'title': c['title'] ?? 'Category',
              'order': c['order'] ?? 'NEWEST',
              'deleted_at': (c['deleted_at'] as num?)?.toInt() ?? 0,
              'show_in_lib': c['show_in_lib'] ?? true,
            });
          }
        }

        // Siapkan soft-delete untuk setiap baris (manga_id, category_id) di server
        if (resData['favourites'] is List) {
          final remoteFavs = (resData['favourites'] as List).cast<Map>();
          for (final f in remoteFavs) {
            final mangaId = (f['manga_id'] as num?)?.toInt() ?? 0;
            final catId = (f['category_id'] as num?)?.toInt() ?? 1;
            final pairKey = '${mangaId}_$catId';
            if (mangaId != 0 && processedKeys.add(pairKey)) {
              final mangaObj = f['manga'] is Map ? f['manga'] as Map : null;
              deleteFavsPayload.add({
                'manga_id': mangaId,
                'category_id': catId,
                'sort_key': 0,
                'pinned': false,
                'created_at': (f['created_at'] as num?)?.toInt() ?? now,
                'deleted_at': now,
                'manga': mangaObj ?? {
                  'manga_id': mangaId,
                  'title': 'Deleted Manga',
                  'alt_title': null,
                  'url': '',
                  'public_url': '',
                  'rating': 0.0,
                  'content_rating': null,
                  'cover_url': '',
                  'large_cover_url': null,
                  'tags': [],
                  'state': null,
                  'author': null,
                  'source': 'shinigami',
                  'nsfw': false,
                },
              });
            }
          }
        }
      }

      // Pastikan category 1 selalu ada di payload
      if (!categoriesPayload.any((c) => c['category_id'] == 1)) {
        categoriesPayload.add({
          'category_id': 1,
          'created_at': now,
          'sort_key': 0,
          'track': true,
          'title': 'Semua kesukaan',
          'order': 'NEWEST',
          'deleted_at': 0,
          'show_in_lib': true,
        });
      }

      // 2. Tambahkan juga seluruh favorit lokal
      final localFavs = LocalStorage.getFavorites(modeId: syncModeId);
      for (final f in localFavs) {
        final slug = _normalizeSlug(f['slug'] as String? ?? '');
        if (slug.isEmpty) continue;
        final mangaId = _hashSlug(slug);

        final targetCats = <int>{1};
        for (final c in categoriesPayload) {
          final cId = (c['category_id'] as num?)?.toInt() ?? 1;
          targetCats.add(cId);
        }

        for (final catId in targetCats) {
          final pairKey = '${mangaId}_$catId';
          if (processedKeys.add(pairKey)) {
            deleteFavsPayload.add({
              'manga_id': mangaId,
              'category_id': catId,
              'sort_key': 0,
              'pinned': false,
              'created_at': now,
              'deleted_at': now,
              'manga': {
                'manga_id': mangaId,
                'title': _truncate(f['title']?.toString() ?? slug, 100),
                'alt_title': null,
                'url': _truncate(slug, 255),
                'public_url': '',
                'rating': 0.0,
                'content_rating': null,
                'cover_url': _truncate(f['cover']?.toString() ?? '', 255),
                'large_cover_url': null,
                'tags': [],
                'state': null,
                'author': null,
                'source': _truncate(f['source']?.toString() ?? 'shinigami', 32),
                'nsfw': false,
              },
            });
          }
        }
      }

      // 3. Kirim tombstone ke server jika ada item
      if (deleteFavsPayload.isNotEmpty || categoriesPayload.isNotEmpty) {
        await _dio.post(
          '$serverUrl/resource/favourites',
          data: {
            'categories': categoriesPayload,
            'favourites': deleteFavsPayload,
            'timestamp': now,
          },
          options: Options(
            headers: authHeaders,
            validateStatus: (status) => status == 200 || status == 204,
          ),
        );
      }

      // 4. Bersihkan komik favorit lokal & tombstones tanpa membangkitkan tombstone baru (kategori dipertahankan)
      await LocalStorage.clearFavoritesDirect(modeId: syncModeId);
      await LocalStorage.clearDeletedFavoriteTombstones(modeId: syncModeId);

      return SyncResult(
        success: true,
        message: 'Berhasil menghapus seluruh komik favorit dari server & perangkat.',
        favoritesCount: deleteFavsPayload.length,
      );
    } on DioException catch (e) {
      return SyncResult(
        success: false,
        message: 'Gagal menghapus favorit di server: ${e.message ?? 'Kesalahan koneksi'}',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Gagal menghapus favorit di server: $e',
      );
    }
  }

  /// Menghapus kategori di Kotatsu Sync Server secara langsung jika login & sync favorit aktif.
  static Future<bool> deleteCategoryOnServer(String categoryName, {String? modeId}) async {
    final syncModeId = modeId ?? LocalStorage.getActiveContentModeId();
    final token = LocalStorage.getSyncToken(modeId: syncModeId);
    if (token == null || token.isEmpty || !LocalStorage.isSyncFavoritesEnabled(modeId: syncModeId)) {
      return false;
    }

    final serverUrl = normalizeUrl(LocalStorage.getSyncServerUrl(modeId: syncModeId));
    if (serverUrl.isEmpty) return false;

    final authHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'X-App-Version': '984',
      'X-Db-Version': '30',
    };

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final savedCatIds = LocalStorage.getSyncCategoryIds(modeId: syncModeId);
      int? catId = savedCatIds[categoryName];

      // Jika categoryId belum tercatat di lokal, cari id dari server
      if (catId == null) {
        final checkResp = await _dio.get(
          '$serverUrl/resource/favourites',
          options: Options(
            headers: authHeaders,
            validateStatus: (status) => status == 200,
          ),
        );
        if (checkResp.statusCode == 200 && checkResp.data is Map) {
          final resData = checkResp.data as Map;
          if (resData['categories'] is List) {
            final remoteCats = (resData['categories'] as List).cast<Map>();
            for (final c in remoteCats) {
              if (c['title'] == categoryName) {
                catId = (c['category_id'] as num?)?.toInt() ?? (c['id'] as num?)?.toInt();
                break;
              }
            }
          }
        }
      }

      if (catId == null || catId <= 1) {
        // Kategori tidak ditemukan di server atau kategori default
        await LocalStorage.removeDeletedCategoryTombstone(categoryName, modeId: syncModeId);
        return false;
      }

      // Kirim kategori dengan deleted_at > 0 ke server
      final categoriesPayload = [
        {
          'category_id': catId,
          'created_at': now,
          'sort_key': 0,
          'track': false,
          'title': _truncate(categoryName, 120),
          'order': 'NEWEST',
          'deleted_at': now,
          'show_in_lib': false,
        }
      ];

      final resp = await _dio.post(
        '$serverUrl/resource/favourites',
        data: {
          'categories': categoriesPayload,
          'favourites': [],
          'timestamp': now,
        },
        options: Options(
          headers: authHeaders,
          validateStatus: (status) => status == 200 || status == 204,
        ),
      );

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        // Berhasil dihapus di server! Bersihkan tombstone kategori ini
        await LocalStorage.removeDeletedCategoryTombstone(categoryName, categoryId: catId, modeId: syncModeId);
        return true;
      }
    } catch (_) {
      // Offline atau gagal: tombstone lokal tetap tersimpan untuk dikirim saat sync berikutnya
    }
    return false;
  }
}
