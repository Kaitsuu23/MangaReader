import 'package:flutter/material.dart';
import '../models/manga_item.dart';
import '../../core/theme/app_theme.dart';
import '../../core/storage/local_storage.dart';
import 'shimmer_loading.dart';
import 'cached_cover.dart';
import 'manga_card_badges.dart';

class MangaCard extends StatelessWidget {
  final MangaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showBadge;
  final bool showSubtitle;
  final bool isSelected;
  final String? fallbackSource;

  /// Optional pre-computed badge values. When supplied by the caller (e.g. from
  /// a list itemBuilder that already has the data), the card skips the matching
  /// `LocalStorage` query in its `build`. When null, the card queries once per
  /// build (no per-card subscription).
  final int? unreadCount;
  final bool? isFavorite;
  final double? readProgress;

  const MangaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.showBadge = false,
    this.showSubtitle = false,
    this.isSelected = false,
    this.fallbackSource,
    this.unreadCount,
    this.isFavorite,
    this.readProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSource = (item.source != null && item.source!.trim().isNotEmpty)
        ? item.source!.trim()
        : fallbackSource?.trim();

    final isFav = isFavorite ?? LocalStorage.isFavorite(item.slug, source: effectiveSource);
    final progress = readProgress ?? LocalStorage.getHistoryProgress(item.slug, source: effectiveSource);
    final unreadUpdates = unreadCount ?? LocalStorage.getMangaUnreadNewChaptersCount(item.slug, source: effectiveSource);

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight = constraints.hasBoundedHeight;
            final coverHeight = constraints.maxWidth * (18 / 13);
            final isExtremelyConstrained = hasBoundedHeight && constraints.maxHeight < (coverHeight + 20);

            final coverWidget = AspectRatio(
              aspectRatio: 13 / 18,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    child: item.cover != null && item.cover!.isNotEmpty
                        ? CachedCover(
                            imageUrl: item.cover!,
                            source: item.source,
                            slug: item.slug,
                            width: constraints.maxWidth.isFinite && constraints.maxWidth > 0
                                ? constraints.maxWidth
                                : null,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            placeholder: (context, url) => const MangaCardCoverShimmer(),
                            errorWidget: (context, url, error) => Container(
                              color: theme.colorScheme.surfaceContainerHigh,
                              child: const Center(
                                child: Icon(Icons.broken_image, size: 28, color: Colors.grey),
                              ),
                            ),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: const Center(
                              child: Icon(Icons.menu_book, size: 28, color: Colors.grey),
                            ),
                          ),
                  ),

                  // Top Left: Selection overlay (when in selection mode) or Favorite Heart badge
                  if (isSelected)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2.5,
                          ),
                          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                          color: theme.colorScheme.primary.withValues(alpha: 0.25),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (unreadUpdates > 0 || isFav)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unreadUpdates > 0) ...[
                            NewChaptersBadge(count: unreadUpdates),
                            if (isFav) const SizedBox(width: 4),
                          ],
                          if (isFav) const FavoriteBadge(),
                        ],
                      ),
                    ),

                  // Top Right Badge: Reading Progress
                  if (progress > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: ReadingProgressBadge(progress: progress),
                    ),
                ],
              ),
            );

            final titleWidget = Text(
              item.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 12.0,
                height: 1.2,
              ),
            );

            final subtitleWidget = showSubtitle
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.genres.isNotEmpty
                          ? item.genres.take(2).join(', ')
                          : (item.status ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                  )
                : null;

            if (!hasBoundedHeight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  coverWidget,
                  const SizedBox(height: 4),
                  titleWidget,
                  ?subtitleWidget,
                ],
              );
            }

            if (isExtremelyConstrained) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: coverWidget,
                    ),
                  ),
                  const SizedBox(height: 2),
                  titleWidget,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                coverWidget,
                const SizedBox(height: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        titleWidget,
                        ?subtitleWidget,
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
