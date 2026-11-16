import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/in_place_predictive_back_page_transitions_builder.dart';
import '../../shared/models/chapter.dart';
import '../../shared/models/manga_details.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/models/manga_source.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/shimmer_loading.dart';
import 'manga_details_screen.dart';

/// Urutan pengurutan hasil alternatif sesuai Kotatsu Redo (AlternativeSortOrder)
enum AlternativeSortOrder {
  bestMatch('Paling cocok'),
  mostChapters('Bab terbanyak'),
  closestChapters('Jumlah bab terdekat'),
  sourcePriority('Prioritas sumber');

  final String label;
  const AlternativeSortOrder(this.label);
}

class AlternativesScreen extends ConsumerStatefulWidget {
  final String source;
  final String? sourceName;
  final String slug;
  final String title;
  final String? cover;
  final int? totalChapters;

  const AlternativesScreen({
    super.key,
    required this.source,
    this.sourceName,
    required this.slug,
    required this.title,
    this.cover,
    this.totalChapters,
  });

  @override
  ConsumerState<AlternativesScreen> createState() => _AlternativesScreenState();
}

class _AlternativesScreenState extends ConsumerState<AlternativesScreen> with SingleTickerProviderStateMixin {
  late String _currentQuery;
  int _completedSources = 0;
  int _totalSources = 0;
  bool _isSearching = false;
  int _searchSessionId = 0;

  List<MangaItem> _results = [];
  List<MangaSource> _allSources = [];
  Map<String, MangaSource> _sourceMap = {};
  final Map<String, int> _exactChapterCounts = {};
  final Map<String, String> _altTitleMap = {};

  AlternativeSortOrder _sortOrder = AlternativeSortOrder.bestMatch;
  bool _hideNoChapters = false;
  bool _pinnedOnly = false;
  bool _relevantOnly = true;

  late AnimationController _syncAnimController;

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.title.trim();
    _syncAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSearch(_currentQuery);
    });
  }

  @override
  void dispose() {
    _searchSessionId++;
    _syncAnimController.dispose();
    super.dispose();
  }

  String _getSourceName(String sourceId) {
    if (_sourceMap.containsKey(sourceId)) {
      return _sourceMap[sourceId]!.name;
    }
    if (sourceId.toLowerCase() == widget.source.toLowerCase() && widget.sourceName != null) {
      return widget.sourceName!;
    }
    // Fallback capitalizing
    if (sourceId.isEmpty) return 'Sumber';
    return sourceId[0].toUpperCase() + sourceId.substring(1);
  }

  String? _getSourceIcon(String sourceId) {
    return _sourceMap[sourceId]?.icon;
  }

  int? _parseChapterCount(String? latestChapter) {
    if (latestChapter == null || latestChapter.isEmpty) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(latestChapter);
    if (match != null) {
      final val = double.tryParse(match.group(1)!);
      if (val != null) return val.round();
    }
    return null;
  }

  int? _getEffectiveChapterCount(MangaItem item) {
    final key = '${item.source ?? ''}:${item.slug}';
    final exact = _exactChapterCounts[key];
    if (exact != null && exact > 0) return exact;
    return _parseChapterCount(item.latestChapter);
  }

  String _getChapterDisplay(MangaItem item) {
    final key = '${item.source ?? ''}:${item.slug}';
    final exact = _exactChapterCounts[key];
    if (exact != null && exact > 0) {
      return '$exact';
    }
    final count = _parseChapterCount(item.latestChapter);
    if (count != null && count > 0) {
      return '$count';
    }
    if (item.latestChapter != null && item.latestChapter!.trim().isNotEmpty) {
      final clean = item.latestChapter!
          .replaceAll(RegExp(r'chapter|ch\.?|bab', caseSensitive: false), '')
          .trim();
      if (clean.isNotEmpty) return clean;
    }
    return '?';
  }

  int _titleMatchScore(String title, String query, {String? slug, String? altTitle}) {
    final normTitle = _normalizeTitle(title);
    final normQuery = _normalizeTitle(query);
    if (normQuery.isEmpty || normTitle.isEmpty) return 0;

    int computeScore(String candidate) {
      if (candidate.isEmpty) return 0;
      if (candidate == normQuery) return 100;
      if (candidate.startsWith(normQuery) || normQuery.startsWith(candidate)) return 85;
      if (candidate.contains(normQuery) || normQuery.contains(candidate)) return 75;

      final queryTokens = normQuery.split(' ').where((s) => s.isNotEmpty).toSet();
      final candidateTokens = candidate.split(' ').where((s) => s.isNotEmpty).toSet();
      final total = max(queryTokens.length, candidateTokens.length);
      if (total == 0) return 0;
      final intersect = queryTokens.intersection(candidateTokens).length;

      // Jika query terdiri dari beberapa kata (misal "Nano Machine"),
      // judul yang hanya mencocokkan 1 kata acak (seperti hanya kata "nano") dianggap tidak cocok (skor 0)
      if (queryTokens.length > 1 && (intersect < 2 || intersect / queryTokens.length < 0.5)) {
        return 0;
      }

      return (intersect * 60) ~/ total;
    }

    var bestScore = computeScore(normTitle);
    if (slug != null && slug.isNotEmpty) {
      bestScore = max(bestScore, computeScore(_normalizeTitle(slug)));
    }
    if (altTitle != null && altTitle.isNotEmpty) {
      final alts = altTitle.split(RegExp(r'[,;/|]'));
      for (final alt in alts) {
        bestScore = max(bestScore, computeScore(_normalizeTitle(alt)));
      }
    }
    return bestScore;
  }

  String _normalizeTitle(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  void _sortResults() {
    final refChapters = widget.totalChapters ?? 0;

    _results.sort((left, right) {
      final leftChapters = _getEffectiveChapterCount(left) ?? 0;
      final rightChapters = _getEffectiveChapterCount(right) ?? 0;

      switch (_sortOrder) {
        case AlternativeSortOrder.bestMatch:
          final rightScore = _titleMatchScore(
            right.title,
            _currentQuery,
            slug: right.slug,
            altTitle: _altTitleMap['${right.source ?? ''}:${right.slug}'],
          );
          final leftScore = _titleMatchScore(
            left.title,
            _currentQuery,
            slug: left.slug,
            altTitle: _altTitleMap['${left.source ?? ''}:${left.slug}'],
          );
          if (rightScore != leftScore) return rightScore.compareTo(leftScore);

          if ((rightChapters > 0) != (leftChapters > 0)) {
            return (rightChapters > 0) ? -1 : 1;
          }
          break;

        case AlternativeSortOrder.mostChapters:
          if (rightChapters != leftChapters) {
            return rightChapters.compareTo(leftChapters);
          }
          break;

        case AlternativeSortOrder.closestChapters:
          final leftDist = leftChapters == 0 ? 999999 : (leftChapters - refChapters).abs();
          final rightDist = rightChapters == 0 ? 999999 : (rightChapters - refChapters).abs();
          if (leftDist != rightDist) {
            return leftDist.compareTo(rightDist);
          }
          break;

        case AlternativeSortOrder.sourcePriority:
          final aPinned = LocalStorage.isSourcePinned(left.source ?? '') ? 0 : 1;
          final bPinned = LocalStorage.isSourcePinned(right.source ?? '') ? 0 : 1;
          if (aPinned != bPinned) return aPinned.compareTo(bPinned);
          break;
      }

      // Secondary fallback: chapter count
      if (rightChapters != leftChapters) {
        return rightChapters.compareTo(leftChapters);
      }
      // Tertiary: source name
      final leftSrc = left.source ?? '';
      final rightSrc = right.source ?? '';
      if (leftSrc != rightSrc) return leftSrc.compareTo(rightSrc);

      return left.title.compareTo(right.title);
    });
  }

  Future<void> _startSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    _searchSessionId++;
    final session = _searchSessionId;

    setState(() {
      _currentQuery = cleanQuery;
      _isSearching = true;
      _completedSources = 0;
      _results = [];
      _exactChapterCounts.clear();
      _altTitleMap.clear();
    });

    try {
      if (_allSources.isEmpty) {
        _allSources = await ref.read(sourcesListProvider.future);
        _sourceMap = {for (final s in _allSources) s.id: s};
      }

      final disabled = LocalStorage.getDisabledSources();
      var targetSources = _allSources.where((s) => !disabled.contains(s.id)).toList();

      if (_pinnedOnly) {
        targetSources = targetSources.where((s) => LocalStorage.isSourcePinned(s.id)).toList();
      }

      // Exclude current source to find alternatives on other sources
      targetSources = targetSources.where((s) => s.id != widget.source).toList();

      // Prioritize pinned sources first
      targetSources.sort((a, b) {
        final aPinned = LocalStorage.isSourcePinned(a.id) ? 0 : 1;
        final bPinned = LocalStorage.isSourcePinned(b.id) ? 0 : 1;
        if (aPinned != bPinned) return aPinned.compareTo(bPinned);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (session != _searchSessionId || !mounted) return;

      setState(() {
        _totalSources = targetSources.length;
      });

      if (targetSources.isEmpty) {
        setState(() {
          _isSearching = false;
        });
        return;
      }

      final queue = List<MangaSource>.from(targetSources);
      const maxParallel = 4;
      final workersCount = min(maxParallel, queue.length);

      final api = ref.read(parserChannelProvider);

      Future<void> worker() async {
        while (queue.isNotEmpty) {
          if (session != _searchSessionId || !mounted) return;
          final src = queue.removeAt(0);

          try {
            final res = await api.search(src.id, cleanQuery, page: 1);
            if (session != _searchSessionId || !mounted) return;

            if (res.data.isNotEmpty) {
              final valid = res.data.where((m) => !(m.source == widget.source && m.slug == widget.slug)).toList();
              if (valid.isNotEmpty) {
                setState(() {
                  _results.addAll(valid);
                  _sortResults();
                });

                // Asynchronously fetch exact details for candidates
                // to get the actual chapter count and altTitles (like Kotatsu Redo does):
                for (final item in valid) {
                  final initialScore = _titleMatchScore(item.title, cleanQuery, slug: item.slug);
                  if (initialScore >= 25 || item == valid.first) {
                    _loadDetailsFor(item, session);
                  }
                }
              }
            }
          } catch (_) {
            // Ignore individual source failure
          } finally {
            if (session == _searchSessionId && mounted) {
              setState(() {
                _completedSources++;
              });
            }
          }
        }
      }

      await Future.wait(List.generate(workersCount, (_) => worker()));

      if (session == _searchSessionId && mounted) {
        setState(() {
          _isSearching = false;
          _sortResults();
        });
      }
    } catch (_) {
      if (session == _searchSessionId && mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _loadDetailsFor(MangaItem item, int session) async {
    final src = item.source;
    if (src == null || src.isEmpty) return;
    final key = '$src:${item.slug}';
    if (_exactChapterCounts.containsKey(key)) return;

    try {
      final api = ref.read(parserChannelProvider);
      final details = await api.getDetails(src, item.slug);
      if (session != _searchSessionId || !mounted) return;

      final count = details.chapters.isNotEmpty ? details.chapters.length : details.totalChapters;
      if (count > 0 || (details.altTitle != null && details.altTitle!.trim().isNotEmpty)) {
        setState(() {
          if (count > 0) {
            _exactChapterCounts[key] = count;
          }
          if (details.altTitle != null && details.altTitle!.trim().isNotEmpty) {
            _altTitleMap[key] = details.altTitle!.trim();
          }
          _sortResults();
        });
      }
    } catch (_) {
      // Ignore background detail load failure
    }
  }

  void _showEditQueryDialog() {
    final controller = TextEditingController(text: _currentQuery);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cari Alternatif', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ketik judul manga...',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (val) {
            Navigator.pop(ctx);
            if (val.trim().isNotEmpty) {
              _startSearch(val.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (controller.text.trim().isNotEmpty) {
                _startSearch(controller.text.trim());
              }
            },
            child: const Text('Cari'),
          ),
        ],
      ),
    );
  }

  void _showFilterBottomSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bContext) => StatefulBuilder(
        builder: (builderContext, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Filter & Urutan', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(bContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text('Urutkan Berdasarkan', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                  ),
                  ...AlternativeSortOrder.values.map((order) {
                    final selected = _sortOrder == order;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _sortOrder = order;
                          _sortResults();
                        });
                        Navigator.pop(bContext);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              selected ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 20,
                              color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              order.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Hanya judul relevan', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Sembunyikan hasil yang tidak cocok dengan judul manga', style: TextStyle(fontSize: 12)),
                    value: _relevantOnly,
                    dense: true,
                    onChanged: (val) {
                      setState(() {
                        _relevantOnly = val;
                      });
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Sembunyikan tanpa bab', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Hanya tampilkan hasil dengan jumlah bab > 0', style: TextStyle(fontSize: 12)),
                    value: _hideNoChapters,
                    dense: true,
                    onChanged: (val) {
                      setState(() {
                        _hideNoChapters = val;
                      });
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Hanya sumber disematkan', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Batasi pencarian ke sumber yang di-pin', style: TextStyle(fontSize: 12)),
                    value: _pinnedOnly,
                    dense: true,
                    onChanged: (val) {
                      setState(() {
                        _pinnedOnly = val;
                      });
                      Navigator.pop(bContext);
                      _startSearch(_currentQuery);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMigrationConfirmation(MangaItem target) {
    final theme = Theme.of(context);
    final oldSourceName = widget.sourceName ?? _getSourceName(widget.source);
    final newSourceName = _getSourceName(target.source ?? '');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: Icon(Icons.copy_rounded, size: 32, color: theme.colorScheme.primary),
        title: const Text('Migrasi manga', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text(
          'Ganti sumber manga ini?\n\nRiwayat bacaan dan status favorit akan dimigrasikan dari "${widget.title}" ($oldSourceName) ke "${target.title}" ($newSourceName).',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _performMigration(target);
            },
            child: const Text('Migrasi'),
          ),
        ],
      ),
    );
  }

  Future<void> _performMigration(MangaItem target) async {
    final oldSlug = widget.slug;
    final newSlug = target.slug;
    final newSource = target.source ?? widget.source;
    final shouldRecordTombstone = oldSlug != newSlug;

    // 1. Migrasi Favorit
    final oldFav = LocalStorage.getFavorite(oldSlug, source: widget.source);
    if (oldFav != null) {
      final categories = LocalStorage.getFavoriteCategoriesForSlug(oldSlug, source: widget.source);
      final oldAddedAt = (oldFav['addedAt'] as num?)?.toInt();
      final type = target.type ?? oldFav['type'] as String?;

      // Hapus favorit lama terlebih dahulu
      await LocalStorage.removeFavorite(
        oldSlug,
        source: widget.source,
        recordTombstone: shouldRecordTombstone,
      );

      // Simpan favorit baru dengan addedAt lama agar urutan card tidak meloncat ke atas
      await LocalStorage.saveFavorite(
        slug: newSlug,
        title: target.title,
        cover: target.cover ?? widget.cover,
        source: newSource,
        categories: categories,
        type: type,
        latestChapter: target.latestChapter,
        addedAt: oldAddedAt,
      );
    }

    // 2. Migrasi Riwayat Bacaan
    final histItem = LocalStorage.getHistoryItem(oldSlug, source: widget.source);
    final readChapters = LocalStorage.getReadChapters(oldSlug, source: widget.source);
    if (histItem != null) {
      final oldCreatedAt = (histItem['createdAt'] as num?)?.toInt();
      final oldUpdatedAt = (histItem['updatedAt'] as num?)?.toInt();

      // Hapus riwayat lama terlebih dahulu
      await LocalStorage.deleteHistoryItem(
        oldSlug,
        source: widget.source,
        recordTombstone: shouldRecordTombstone,
      );

      final targetChapters = _getEffectiveChapterCount(target) ?? widget.totalChapters;
      String newChapterSlug = histItem['chapterSlug'] as String? ?? '';
      String newChapterTitle = histItem['chapterTitle'] as String? ?? '';
      num? newChapterNum = (histItem['chapterNumber'] as num?);
      final toMarkReadNew = <String>[];

      // Kumpulkan seluruh nomor bab yang sudah dibaca di sumber lama (dari riwayat dan daftar readChapters)
      final readNumbers = <double>{};
      for (final slug in readChapters) {
        final match = RegExp(r'(?:chapter|ch|bab)[-_]?([0-9]+(?:[-.][0-9]+)?)', caseSensitive: false).firstMatch(slug) ??
            RegExp(r'[-_/]([0-9]+(?:\.[0-9]+)?)[-_/]?').firstMatch(slug);
        if (match != null) {
          final n = double.tryParse(match.group(1)!.replaceAll('-', '.'));
          if (n != null && n > 0 && n < 100000) {
            readNumbers.add(n);
          }
        }
      }

      final oldTitle = histItem['chapterTitle']?.toString() ?? '';
      double? oldNum = (histItem['chapterNumber'] as num?)?.toDouble() ??
          double.tryParse(RegExp(r'(?:Chapter|Bab|Ch\.?|Episode|Ep\.?)\s*([0-9.]+)', caseSensitive: false).firstMatch(oldTitle)?.group(1) ?? '') ??
          double.tryParse(RegExp(r'([0-9.]+)').firstMatch(oldTitle)?.group(1) ?? '');

      if (readNumbers.isNotEmpty) {
        final maxFromRead = readNumbers.reduce(max);
        if (oldNum == null || maxFromRead > oldNum) {
          oldNum = maxFromRead;
        }
      }

      try {
        final api = ref.read(parserChannelProvider);
        MangaDetails? targetDetails;
        try {
          targetDetails = await api.getDetails(newSource, newSlug);
        } catch (_) {
          final cleanNew = newSlug.trim().replaceAll(RegExp(r'^/+|/+$'), '').replaceFirst(RegExp(r'^manga/', caseSensitive: false), '').replaceAll(RegExp(r'^/+|/+$'), '');
          final effectiveNewSlug = cleanNew.isNotEmpty ? cleanNew : newSlug;
          targetDetails = await api.getDetails(newSource, effectiveNewSlug);
        }

        if (targetDetails != null && targetDetails.chapters.isNotEmpty) {
          final sortedNew = Chapter.sortChronological(targetDetails.chapters);

          Chapter? matchedCh;
          int matchedIdx = -1;
          if (oldNum != null && oldNum > 0) {
            for (int i = 0; i < sortedNew.length; i++) {
              final c = sortedNew[i];
              final cNum = c.chapterNumber ??
                  double.tryParse(RegExp(r'(?:Chapter|Bab|Ch\.?|Episode|Ep\.?)\s*([0-9.]+)', caseSensitive: false).firstMatch(c.title)?.group(1) ?? '') ??
                  double.tryParse(RegExp(r'([0-9.]+)').firstMatch(c.title)?.group(1) ?? '') ??
                  double.tryParse(RegExp(r'([0-9.]+)').firstMatch(c.chapter)?.group(1) ?? '');

              // Tandai bab di sumber baru sebagai sudah dibaca jika nomornya <= oldNum atau nomornya ada di readNumbers
              final isReadByNum = cNum != null && (cNum <= oldNum || readNumbers.contains(cNum));
              if (isReadByNum) {
                if (c.slug.isNotEmpty) toMarkReadNew.add(c.slug);
                if (c.chapter.isNotEmpty) toMarkReadNew.add(c.chapter);
                toMarkReadNew.add(SyncService.hashSlug(c.slug).toString());
                toMarkReadNew.add(SyncService.hashSlug(c.chapter).toString());
              }

              if (cNum != null && (cNum - oldNum).abs() < 0.01) {
                matchedCh = c;
                matchedIdx = i;
              }
            }

            // Fallback jika tidak ada yang exact match: cari bab terdekat yang <= oldNum
            if (matchedCh == null) {
              for (int i = sortedNew.length - 1; i >= 0; i--) {
                final cNum = sortedNew[i].chapterNumber;
                if (cNum != null && cNum <= oldNum) {
                  matchedCh = sortedNew[i];
                  matchedIdx = i;
                  break;
                }
              }
            }
          }

          if (matchedCh != null) {
            newChapterSlug = matchedCh.slug;
            newChapterTitle = matchedCh.title;
            newChapterNum = matchedCh.chapterNumber ?? oldNum;

            // Pastikan semua bab kronologis sampai matchedIdx ditandai sudah dibaca
            for (int i = 0; i <= matchedIdx; i++) {
              final c = sortedNew[i];
              if (c.slug.isNotEmpty) toMarkReadNew.add(c.slug);
              if (c.chapter.isNotEmpty) toMarkReadNew.add(c.chapter);
              toMarkReadNew.add(SyncService.hashSlug(c.slug).toString());
              toMarkReadNew.add(SyncService.hashSlug(c.chapter).toString());
            }
          }
        }
      } catch (e) {
        debugPrint('[Migration] Could not pre-fetch target chapters: $e');
      }

      await LocalStorage.saveHistory(
        slug: newSlug,
        title: target.title,
        cover: target.cover ?? widget.cover,
        source: newSource,
        chapterSlug: newChapterSlug,
        chapterTitle: newChapterTitle,
        page: (histItem['page'] as num?)?.toInt() ?? 1,
        totalPages: (histItem['totalPages'] as num?)?.toInt() ?? 1,
        pageOffset: (histItem['pageOffset'] as num?)?.toDouble() ?? 0.0,
        scrollOffset: (histItem['scrollOffset'] as num?)?.toDouble() ?? 0.0,
        percent: (histItem['percent'] as num?)?.toDouble(),
        totalChapters: targetChapters,
        chapterNumber: newChapterNum ?? (histItem['chapterNumber'] as num?),
        pageOffsetRatio: (histItem['pageOffsetRatio'] as num?)?.toDouble(),
        createdAt: oldCreatedAt,
        updatedAt: oldUpdatedAt,
      );

      final allReadSlugs = <String>{...readChapters, ...toMarkReadNew};
      if (allReadSlugs.isNotEmpty) {
        await LocalStorage.markChaptersAsRead(newSlug, allReadSlugs, source: newSource);
      }
    } else {
      await LocalStorage.clearReadChapters(oldSlug, source: widget.source);
    }

    // 3. Migrasi Bookmark jika slug berubah
    if (shouldRecordTombstone) {
      final oldBookmarks = LocalStorage.getAllBookmarks();
      for (final bm in oldBookmarks) {
        if (bm['slug'] == oldSlug) {
          await LocalStorage.saveBookmark(
            slug: newSlug,
            mangaTitle: target.title,
            chapterSlug: bm['chapterSlug'] as String? ?? '',
            chapterTitle: bm['chapterTitle'] as String? ?? '',
            page: (bm['page'] as num?)?.toInt() ?? 1,
          );
        }
      }
    }

    // 4. Migrasi Feed dan Tracking Baseline ke Source Baru
    await LocalStorage.migrateFeedAndTrackBaseline(
      oldSlug: oldSlug,
      oldSource: widget.source,
      newSlug: newSlug,
      newSource: newSource,
      newTitle: target.title,
      newCover: target.cover ?? widget.cover,
    );

    // 5. Picu sinkronisasi ke server (jika user login sync server)
    // agar komik lama otomatis dihapus dari server dan komik baru langsung terdaftar.
    SyncService.syncNow().catchError((e) => SyncResult(success: false, message: e.toString()));

    if (!mounted) return;
    Navigator.pop(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final srcTitle = widget.sourceName ?? _getSourceName(widget.source);
    final chCount = widget.totalChapters != null && widget.totalChapters! > 0
        ? '${widget.totalChapters} bab'
        : '? bab';
    final subtitleText = '$srcTitle • ID • $chCount';

    final displayedResults = _results.where((m) {
      if (_hideNoChapters && (_getEffectiveChapterCount(m) ?? 0) <= 0) {
        return false;
      }
      final score = _titleMatchScore(
        m.title,
        _currentQuery,
        slug: m.slug,
        altTitle: _altTitleMap['${m.source ?? ''}:${m.slug}'],
      );
      if (_relevantOnly && score < 25) {
        return false;
      }
      return true;
    }).toList();

    final progressRatio = _totalSources > 0 ? _completedSources / _totalSources : 0.0;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Alternatif',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text(
              subtitleText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Ubah Pencarian',
            onPressed: _showEditQueryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter & Urutkan',
            onPressed: _showFilterBottomSheet,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2.5),
          child: _isSearching
              ? LinearProgressIndicator(
                  value: _totalSources > 0 ? progressRatio : null,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  minHeight: 2.5,
                )
              : const SizedBox(height: 2.5),
        ),
      ),
      body: Column(
        children: [
          // Row of Summary Chips (Kotatsu Redo layout)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  // 1. Query Chip
                  InkWell(
                    onTap: _showEditQueryDialog,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              _currentQuery,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Sources Progress Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSearching)
                          RotationTransition(
                            turns: _syncAnimController,
                            child: Icon(Icons.sync, size: 16, color: theme.colorScheme.primary),
                          )
                        else
                          Icon(Icons.sync, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          _isSearching
                              ? '$_completedSources/$_totalSources sources'
                              : '${displayedResults.length} hasil',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Sort Chip
                  InkWell(
                    onTap: _showFilterBottomSheet,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sort_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            _sortOrder.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content List
          Expanded(
            child: _buildBody(displayedResults),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<MangaItem> items) {
    final theme = Theme.of(context);
    if (_isSearching && items.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: 4,
        itemBuilder: (_, index) => _buildSkeletonCard(theme),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: EmptyView(
          icon: Icons.search_off_rounded,
          title: 'Tidak Ada Alternatif',
          subtitle: 'Tidak ditemukan alternatif untuk "$_currentQuery" di sumber lain.',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildAlternativeCard(item);
      },
    );
  }

  Widget _buildSkeletonCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: AppShimmer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 92,
              height: 92 * 18 / 13,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 18,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 14,
                    width: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 24,
                    width: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      height: 32,
                      width: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlternativeCard(MangaItem item) {
    final theme = Theme.of(context);
    final sourceName = _getSourceName(item.source ?? '');
    final sourceIcon = _getSourceIcon(item.source ?? '');
    final chapterText = '${_getChapterDisplay(item)} bab';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Tap card body -> Preview manga details
            Navigator.push(
              context,
              PredictiveBackPageRoute(
                builder: (_) => MangaDetailsScreen(
                  slug: item.slug,
                  source: item.source ?? widget.source,
                  title: item.title,
                  cover: item.cover,
                  sourceName: sourceName,
                  origin: 'explore',
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Cover Thumbnail (Aspect Ratio 13:18 Kotatsu standard)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 92,
                    child: AspectRatio(
                      aspectRatio: 13 / 18,
                      child: item.cover != null && item.cover!.isNotEmpty
                          ? CachedCover(
                              imageUrl: item.cover!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_rounded, size: 28),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // 2. Info Column + Action Button
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Manga Title
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Chapter count
                      Text(
                        chapterText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Source badge chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (sourceIcon != null && sourceIcon.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CachedCover(
                                    imageUrl: sourceIcon,
                                    fit: BoxFit.contain,
                                    errorWidget: (context, url, error) => _buildFallbackInitial(sourceName),
                                  ),
                                ),
                              )
                            else
                              _buildFallbackInitial(sourceName),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                sourceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Replace Tonal Button on bottom-right
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showMigrationConfirmation(item),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text(
                            'Replace',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackInitial(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final theme = Theme.of(context);
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
