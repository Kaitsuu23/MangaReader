import 'package:flutter/material.dart';

/// InheritedNotifier yang membawa state "search overlay sedang terbuka".
/// Di-inject oleh MainScreen di root widget tree sehingga KotatsuSearchBar
/// di screen mana pun bisa mengakses dan meng-update-nya tanpa perlu prop-drilling.
class SearchOverlayNotifier extends InheritedNotifier<ValueNotifier<bool>> {
  const SearchOverlayNotifier({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Ambil notifier dari context. Tidak akan null jika MainScreen sudah inject.
  static ValueNotifier<bool>? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SearchOverlayNotifier>()
        ?.notifier;
  }

  /// Set status search overlay secara langsung tanpa context dependency.
  static void setOpen(BuildContext context, bool isOpen) {
    of(context)?.value = isOpen;
  }
}
