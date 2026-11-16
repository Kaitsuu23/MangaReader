import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/parser_channel.dart';
import '../storage/local_storage.dart';
import '../../shared/models/manga_source.dart';
import '../../shared/models/content_mode.dart';

/// Primary parser client via MethodChannel (Kotlin parsers, no server needed).
final parserChannelProvider = Provider<ParserChannel>((ref) {
  return ParserChannel();
});

final activeContentModeProvider =
    NotifierProvider<ActiveContentModeNotifier, ContentMode>(ActiveContentModeNotifier.new);

class ActiveContentModeNotifier extends Notifier<ContentMode> {
  @override
  ContentMode build() => LocalStorage.getActiveContentMode();

  void setMode(String modeId) {
    LocalStorage.setActiveContentModeId(modeId);
    state = LocalStorage.getActiveContentMode();
    final modeSource = LocalStorage.getActiveSource(modeId: modeId);
    ref.read(activeSourceProvider.notifier).setSource(modeSource);
    LocalStorage.notifyContentModeChanged();
  }

  void refresh() {
    state = LocalStorage.getActiveContentMode();
  }
}

final contentModesListProvider =
    NotifierProvider<ContentModesListNotifier, List<ContentMode>>(ContentModesListNotifier.new);

class ContentModesListNotifier extends Notifier<List<ContentMode>> {
  @override
  List<ContentMode> build() => LocalStorage.getContentModes();

  void reload() {
    state = LocalStorage.getContentModes();
  }
}

final activeSourceProvider =
    NotifierProvider<ActiveSourceNotifier, String>(ActiveSourceNotifier.new);

class ActiveSourceNotifier extends Notifier<String> {
  @override
  String build() => LocalStorage.getActiveSource();

  void setSource(String source) {
    state = source;
    LocalStorage.setActiveSource(source);
  }
}

/// Sources list — loaded from Kotlin parsers via MethodChannel.
final sourcesListProvider = FutureProvider<List<MangaSource>>((ref) async {
  final parser = ref.watch(parserChannelProvider);
  return parser.getSources();
});

final appThemeModeProvider =
    NotifierProvider<ThemeModeNotifier, String>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<String> {
  @override
  String build() => LocalStorage.getThemeMode();

  void setTheme(String mode) {
    state = mode;
    LocalStorage.setThemeMode(mode);
  }
}
