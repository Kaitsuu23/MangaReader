import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/feed_item.dart';
import '../../shared/widgets/cached_cover.dart';
import '../details/manga_details_screen.dart';
import '../settings/settings_screen.dart';
import 'feed_provider.dart';
import '../../shared/widgets/kotatsu_search_bar.dart';
import '../content_mode/content_mode_dialog.dart';
import '../../core/services/network_service.dart';
import '../../core/services/tracker_notification_service.dart';

class FeedScreen extends ConsumerStatefulWidget {
  final VoidCallback? onExploreTap;

  const FeedScreen({super.key, this.onExploreTap});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkPendingBackgroundUpdates();
      await LocalStorage.syncAllFeedItemsReadStatus();
      await FeedUpdateNotifier.syncTrackedMangaConfig();
      if (mounted) {
        ref.read(feedUpdateProvider.notifier).syncRunningStatus();
      }
    });
  }

  Future<void> _checkPendingBackgroundUpdates() async {
    await FeedUpdateNotifier.importPendingUpdates();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHeaderVisible = ref.watch(feedHeaderVisibleProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Search Bar matching Kotatsu fragment_explore / actionbar
            KotatsuSearchBar(
              trailingMenu: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                offset: const Offset(0, 40),
                constraints: const BoxConstraints(minWidth: 160, maxWidth: 190),
                onSelected: (value) => _handleMenuOption(value),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'content_mode',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.dashboard_customize_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Mode Konten', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'check_now',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Periksa sekarang', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'mark_all_read',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.done_all_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Tandai dibaca', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear_feed',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Bersihkan', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Pengaturan', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body content
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  LocalStorage.listenContentMode(),
                  LocalStorage.listenFeed(),
                ]),
                builder: (context, child) {
                  final activeModeId = LocalStorage.getActiveContentModeId();
                  final items = LocalStorage.getFeedItems(modeId: activeModeId);

                      if (items.isEmpty) {
                        return RefreshIndicator(
                          key: _refreshIndicatorKey,
                          backgroundColor: Colors.white,
                          color: Colors.black87,
                          displacement: 24,
                          onRefresh: _handleCheckForUpdates,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height * 0.7,
                              child: _buildEmptyState(theme),
                            ),
                          ),
                        );
                      }

                      return RefreshIndicator(
                        key: _refreshIndicatorKey,
                        backgroundColor: Colors.white,
                        color: Colors.black87,
                        displacement: 24,
                        onRefresh: _handleCheckForUpdates,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            if (isHeaderVisible && items.isNotEmpty)
                              SliverToBoxAdapter(
                                child: _buildUpdatedMangaStrip(context, items, theme),
                              ),

                            ..._buildGroupedFeedList(context, items, theme),

                            const SliverToBoxAdapter(child: SizedBox(height: 100)),
                          ],
                        ),
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Header Carousel: Recently Updated Manga Strip ---

  Widget _buildUpdatedMangaStrip(
    BuildContext context,
    List<FeedItem> items,
    ThemeData theme,
  ) {
    // Unique manga entries from recent feed items (up to 10)
    // ONLY include manga that still have unread new chapters!
    final seen = <String>{};
    final uniqueItems = <FeedItem>[];
    for (final it in items) {
      if (!it.isValid) continue;
      if (!LocalStorage.isFeedItemUnread(it)) continue;
      if (seen.add(it.mangaSlug)) {
        uniqueItems.add(it);
        if (uniqueItems.length >= 10) break;
      }
    }

    if (uniqueItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pembaruan Terkini',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${uniqueItems.length} manga',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: uniqueItems.length,
            separatorBuilder: (_, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final it = uniqueItems[index];
              final unreadCount = LocalStorage.getUnreadNewChaptersCount(it);
              return InkWell(
                onTap: () {
                  _openMangaDetails(context, it);
                },
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: SizedBox(
                  width: 96,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Manga Cover with New Chapters Badge
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                            child: SizedBox(
                              width: 96,
                              height: 128,
                              child: CachedCover(
                                imageUrl: it.mangaCover,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '+$unreadCount',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // Manga Title
                      Text(
                        it.mangaTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ],
    );
  }

  // --- Grouped Feed List ---

  List<Widget> _buildGroupedFeedList(
    BuildContext context,
    List<FeedItem> items,
    ThemeData theme,
  ) {
    // Group valid items by relative date header
    final Map<String, List<FeedItem>> groups = {};
    for (final it in items) {
      if (!it.isValid) continue;
      final header = _formatDateHeader(DateTime.fromMillisecondsSinceEpoch(it.createdAt));
      groups.putIfAbsent(header, () => []).add(it);
    }

    final slivers = <Widget>[];

    groups.forEach((header, groupItems) {
      // Date Section Header
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              header,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      );

      // Section Items
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final it = groupItems[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildFeedItemTile(context, it, theme),
                );
              },
              childCount: groupItems.length,
            ),
          ),
        ),
      );
    });

    return slivers;
  }

  // --- Feed Item Tile with Swipe to Dismiss ---

  Widget _buildFeedItemTile(
    BuildContext context,
    FeedItem item,
    ThemeData theme,
  ) {
    if (!item.isValid) return const SizedBox.shrink();
    final isUnread = LocalStorage.isFeedItemUnread(item);
    final unreadChCount = LocalStorage.getUnreadNewChaptersCount(item);
    final timeStr = _formatTimeAgo(DateTime.fromMillisecondsSinceEpoch(item.createdAt));

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.horizontal,
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
          ],
        ),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final removed = await LocalStorage.removeFeedItem(item.id);
        if (!mounted || removed == null) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Pembaruan "${item.mangaTitle}" dihapus'),
            action: SnackBarAction(
              label: 'Urungkan',
              onPressed: () {
                LocalStorage.restoreFeedItem(removed);
              },
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      },
      child: Material(
        color: isUnread
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _openMangaDetails(context, item);
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // Manga Cover Thumbnail with new chapters badge
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 46,
                        height: 58,
                        child: CachedCover(
                          imageUrl: item.mangaCover,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (unreadChCount > 0)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            '+$unreadChCount',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Main Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        item.mangaTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Chapter Summary + Source Badge
                      Row(
                        children: [
                          if (isUnread) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                unreadChCount > 0 ? '+$unreadChCount BARU' : 'BARU',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimary,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              _buildChapterSummary(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          Text(
                            ' • ',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          Text(
                            item.mangaSource.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                          if (item.modeName != null && item.modeName!.isNotEmpty) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.modeName!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Time ago + Unread dot
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    if (isUnread) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Empty State ---

  Widget _buildEmptyState(ThemeData theme) {
    final activeMode = LocalStorage.getActiveContentMode();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.rss_feed_rounded,
                size: 56,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Umpan Kosong (${activeMode.name})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bab baru dari komik mode "${activeMode.name}" yang Anda baca atau simpan ke kesukaan ditampilkan di sini.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Periksa Pembaruan Sekarang'),
              onPressed: _handleCheckForUpdates,
            ),
            if (widget.onExploreTap != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Jelajahi Manga'),
                onPressed: widget.onExploreTap,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Actions & Helpers ---

  Future<void> _handleCheckForUpdates() async {
    if (!NetworkService.isConnected) {
      NetworkService.showNoInternetSnackBar(context, onRetry: _handleCheckForUpdates);
      return;
    }
    final notifier = ref.read(feedUpdateProvider.notifier);
    // Periksa semua mode sekaligus (modeId null = semua mode)
    final count = await notifier.checkForUpdates();
    await LocalStorage.syncAllFeedItemsReadStatus();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? 'Ditemukan $count pembaruan baru'
                : 'Semua manga sudah diperbarui',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleMenuOption(String value) async {
    switch (value) {
      case 'content_mode':
        showContentModeDialog(context, ref);
        break;
      case 'settings':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        break;
      case 'check_now':
        if (_refreshIndicatorKey.currentState != null) {
          _refreshIndicatorKey.currentState!.show();
        } else {
          _handleCheckForUpdates();
        }
        break;
      case 'mark_all_read':
        final currentMode = LocalStorage.getActiveContentMode();
        await LocalStorage.markAllFeedItemsAsRead(modeId: currentMode.id);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Semua pembaruan mode ${currentMode.name} ditandai sudah dibaca'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        break;
      case 'clear_feed':
        _showClearFeedDialog();
        break;
    }
  }

  void _showClearFeedDialog() {
    final currentMode = LocalStorage.getActiveContentMode();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bersihkan Umpan (${currentMode.name})'),
        content: Text('Bersihkan semua riwayat pembaruan mode "${currentMode.name}" secara permanen?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalStorage.clearFeed(modeId: currentMode.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Umpan mode ${currentMode.name} telah dibersihkan'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMangaDetails(BuildContext context, FeedItem item) async {
    final effectiveItem = LocalStorage.resolveMigratedFeedItem(item) ?? item;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaDetailsScreen(
          slug: effectiveItem.mangaSlug,
          source: effectiveItem.mangaSource,
          title: effectiveItem.mangaTitle,
          cover: effectiveItem.mangaCover,
          origin: 'feed',
        ),
      ),
    );
    if (mounted) {
      await LocalStorage.syncFeedItemsReadStatus(
        slug: effectiveItem.mangaSlug,
        source: effectiveItem.mangaSource,
        modeId: effectiveItem.modeId,
      );
      final unread = LocalStorage.getTotalUnreadNewChaptersCount();
      await TrackerNotificationService.setBadgeCount(unread);
      setState(() {});
    }
  }

  String _buildChapterSummary(FeedItem item) {
    if (item.newChapters.isNotEmpty) {
      if (item.newChapters.length == 1) {
        return item.newChapters.first;
      }
      return '${item.newChapters.last} (+${item.newChapters.length} bab)';
    }
    return '${item.newChaptersCount} bab baru';
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final itemDate = DateTime(date.year, date.month, date.day);

    if (itemDate == today) return 'Hari ini';
    if (itemDate == yesterday) return 'Kemarin';

    final diffDays = today.difference(itemDate).inDays;
    if (diffDays > 0 && diffDays < 7) {
      return '$diffDays hari lalu';
    }

    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.isNegative || diff.inSeconds < 60) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    if (diff.inHours < 24) return '${diff.inHours}j lalu';
    if (diff.inDays < 7) return '${diff.inDays}h lalu';
    return '${date.day}/${date.month}';
  }
}
