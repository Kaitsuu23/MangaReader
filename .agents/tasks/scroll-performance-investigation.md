# Investigasi Performa Scroll — MangaReader (Flutter)

## Ringkasan Jawaban

Scroll terasa berat bukan karena satu penyebab, melainkan tumpukan overhead yang dieksekusi **setiap kali sebuah kartu masuk ke layar** dan **setiap kali data berubah di background**. Penyebab utama, berurutan dari dampak terbesar:

1. **Pemanggilan method `LocalStorage` yang berat di dalam `build()` setiap kartu.** `getMangaUnreadNewChaptersCount()` (dan `getUnreadNewChaptersCount()`) melakukan *full scan* atas seluruh isi box feed, mendeserialisasi tiap `FeedItem` yang cocok, lalu memanggil `getReadChapters()` + `getHistoryItem()` per item. Ini dipanggil **per kartu** di `manga_card.dart`, `_HistoryCard`, dan `_buildCompactItem`/`_buildDetailedItem`. Saat scroll membangun beberapa kartu baru per frame, beban ini menumpuk dan menyebabkan jank.
2. **`ListenableBuilder` berlebihan & redundan.** Setiap `MangaCard` membungkus dirinya sendiri dengan `ListenableBuilder(Listenable.merge([favorites, history, feed]))`, sementara layar induk (history, favorites) sudah membungkus seluruh konten dengan `ListenableBuilder.merge` 4 listener. Akibatnya, setiap perubahan data feed/favorit/history memicu rebuild **semua kartu yang tampil**, yang masing-masing kembali menjalankan method berat di poin 1.
3. **Operasi O(n) penuh di dalam `build()` layar.** `history_screen` memanggil `getHistory()` **dua kali** (sort aktif + `last_read`); `favorites_screen` memanggil `getFavorites(category:)` untuk **setiap tab** (untuk badge count) lalu memanggilnya lagi + mengurutkan ulang per tab; `feed_screen` mengelompokkan ulang seluruh item setiap rebuild.
4. **GridView bersarang dengan `shrinkWrap`** di mode pengelompokan history — mengalahkan lazy building karena harus mengukur seluruh anak.
5. **Tidak ada `RepaintBoundary`/`itemExtent`/`cacheExtent` di grid/list utama**, dan `AnimatedBuilder` di floating_navbar membungkus seluruh bar item (rebuild semua item tiap frame animasi).

Animasi (floating_navbar tap, shimmer) **tidak** berjalan saat idle — mereka hanya aktif saat tap / loading, jadi bukan penyebab jank saat scroll murni.

Detail lengkap, kutipan file+baris, dan rekomendasi fix konkret ada di bawah.

---

## Batasan Investigasi

Investigasi ini bersifat read-only: membaca kode di `lib/` (khususnya `main_screen.dart`, `history_screen.dart`, `favorites_screen.dart`, `feed_screen.dart`, `floating_navbar.dart`, `manga_card.dart`, `cached_cover.dart`, `local_storage.dart`, `manga_card_badges.dart`, `shimmer_loading.dart`, `feed_provider.dart`). Tidak ada kode yang diubah, tidak ada server dijalankan, tidak ada build/test yang dieksekusi. Analisis bersifat statis berdasarkan kode yang dibaca.

---

## Temuan Per Fokus

### 1. ListenableBuilder / ValueListenableBuilder berlebihan

**1a. `MangaCard` — subscription per-kartu yang redundan (penyebab terbesar)**
- File: `lib/shared/widgets/manga_card.dart:36-45`
- Setiap `MangaCard` membungkus seluruh isinya dengan:
  ```
  ListenableBuilder(
    listenable: Listenable.merge([
      LocalStorage.listenFavorites(),
      LocalStorage.listenHistory(),
      LocalStorage.listenFeed(),
    ]),
    ...
  ```
- `Listenable.merge` membuat instance merge baru **setiap build**, lalu `ListenableBuilder` berlangganan/melepasnya. Setiap kartu yang tampil = 3 subscription aktif.
- Ketika box feed/favorit/history berubah (mis. cek bab baru di background, toggle favorit), **setiap kartu yang sedang tampil rebuild** dan menjalankan ulang `isFavorite` + `getHistoryProgress` + `getMangaUnreadNewChaptersCount` (lihat poin 3 untuk beratnya).
- `MangaCard` dipakai di `favorites_screen.dart:1583`, `explore_screen.dart:111`, `source_view_screen.dart:2546,2635`, `source_catalog_screen.dart:169`, `manga_details_screen.dart:2264` — jadi dampaknya meluas ke seluruh layar bergrid.

**Kenapa jank:** saat scroll, Flutter membangun kartu baru secara lazy. Setiap kartu baru langsung berlangganan 3 listener dan menjalankan method berat. Saat ada notifikasi box (background feed check yang sering jalan), kartu yang sudah tampil juga rebuild.

**Rekomendasi fix:**
- Hapus `ListenableBuilder` di dalam `MangaCard`. Layar induk (history/favorites/explore) sudah membungkus list dengan `ListenableBuilder`/`ValueListenableBuilder`, jadi rebuild sudah terjadi di level yang tepat. Mengizinkan subscription per-kartu hanya menambah rebuild granular yang mahal.
- Jika badge "new chapters" perlu update real-time tanpa rebuild layar penuh, kirim nilai `unreadUpdates`/`isFav`/`progress` sebagai parameter dari itemBuilder (yang sudah punya data list) daripada meng-query ulang di dalam kartu.

**1b. `history_screen` — merge 4 listener membungkus seluruh body**
- File: `lib/features/history/history_screen.dart:605-614`
  ```
  child: ListenableBuilder(
    listenable: Listenable.merge([
      LocalStorage.listenHistory(),
      LocalStorage.listenFavorites(),
      LocalStorage.listenContentMode(),
      LocalStorage.listenFeed(),
    ]),
  ```
- Setiap perubahan pada **salah satu** dari 4 box memicu rebuild seluruh body termasuk dua pemanggilan `getHistory()` penuh (lihat poin 5a). Pengecekan bab baru di background (feed box) → rebuild penuh history screen saat user sedang scroll di sana.

**Rekomendasi:** pisahkan listener sesuai kebutuhan: konten list hanya perlu `listenHistory` (+ `listenContentMode` untuk ganti mode). Badge favorit/unread bisa dibaca dari data item yang sudah ada. Hindari `listenFeed` di sini karena history tidak bergantung pada feed box — kecuali badge unread yang sebaiknya di-precompute.

**1c. `favorites_screen` — merge 4 listener membungkus TabBar + seluruh TabBarView**
- File: `lib/features/favorites/favorites_screen.dart:1404-1423`
  ```
  child: ListenableBuilder(
    listenable: Listenable.merge([
      LocalStorage.listenFavorites(),
      LocalStorage.listenHistory(),
      LocalStorage.listenContentMode(),
      LocalStorage.listenFeed(),
    ]),
  ```
- Rebuild ini membangun ulang TabBar (yang memanggil `getFavorites(category: cat).length` untuk setiap tab — poin 6) **dan** seluruh isi tab aktif, termasuk memanggil `getFavorites(category:)` + `_filterAndSortItems()` lagi (poin 6).
- Lagi-lalu: feed box berubah → favorites screen rebuild penuh saat scroll.

**Rekomendasi:** sama dengan 1b — batasi listener. `listenContentMode` sudah ditangani terpisah via `_onContentModeChanged` (line 67), jadi merge ini menggandakan kerja.

---

### 2. IndexedStack + listener global di main_screen.dart

- File: `lib/features/main/main_screen.dart`
  - `late final List<Widget> _screens` (line 32) berisi 4 layar instance tetap.
  - Tiga `ValueListenableBuilder` bersarang: `listenSettings` (line 296) → `listenContentMode` (line 310) → `listenFeed` (line 313), yang membungkus `Scaffold` + `IndexedStack` (line 322-325).
- **Catatan penting:** karena `_screens` adalah instance widget yang sama (dibuat sekali di field initializer), saat `ValueListenableBuilder` atas rebuild, Flutter **tidak** membangun ulang elemen anak IndexedStack (instance widget identik → element dipakai ulang tanpa build). Jadi nesting ini sendiri **tidak** menyebabkan rebuild isi tab.
- **Yang tetap bermasalah:** saat box feed/settings/contentMode berubah, `ValueListenableBuilder` paling luar rebuild `Scaffold` → membangun ulang `FloatingNavbar` (kedua cabang floating & non-floating) yang memiliki `AnimatedBuilder` sendiri (poin 4). Juga `getTotalUnreadNewChaptersCount()` (line 317) dipanggil tiap rebuild feed — ini juga O(n) scan feed box (lihat `local_storage.dart:3414-3435`).
- **Yang benar-benar membuat tiap tab "selalu hidup":** IndexedStack memang mempertahankan state 4 layar sekaligus, dan setiap layar punya ListenableBuilder-nya sendiri (poin 1b, 1c, poin 7). Jadi satu perubahan box bisa memicu rebuild di **lebih dari satu layar yang tidak sedang tampil** sekaligus — pemborosan karena user hanya melihat satu tab.

**Rekomendasi:**
- Flatten tiga `ValueListenableBuilder` jadi satu `ListenableBuilder(Listenable.merge([settings, contentMode, feed]))` tunggal, dan bungkus hanya bagian navbar/badge dengannya — bukan seluruh `Scaffold`/`IndexedStack`. `IndexedStack` bisa diletakkan di luar listener (di `child`), karena `IndexedStack` tidak bergantung pada nilai listener tersebut.
- Pindahkan `getTotalUnreadNewChaptersCount()` agar tidak dipanggil pada setiap tick feed; hitung saat notifikasi feed benar-benar selesai, atau gunakan value yang sudah di-cache.
- Pertimbangkan `Offstage`/lazy tab loading alih-alih `IndexedStack` jika mempertahankan state semua tab sekaligus terbukti memberatkan, tapi ini perlu pengukuran; IndexedStack sendiri lazily *builds* child saat index dipilih (anak non-aktif tidak dibangun sampai pertama kali dipilih), jadi dampaknya terbatas pada rebuild listener, bukan build awal.

---

### 3. manga_card.dart & cached_cover.dart — operasi berat di build

**3a. Tiga query `LocalStorage` berat per kartu**
- File: `lib/shared/widgets/manga_card.dart:43-45`
  ```
  final isFav = LocalStorage.isFavorite(item.slug, source: effectiveSource);
  final progress = LocalStorage.getHistoryProgress(item.slug, source: effectiveSource);
  final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(item.slug, source: effectiveSource);
  ```
- Beratnya:
  - `getMangaUnreadNewChaptersCount` (`local_storage.dart:3220-3290`) → loop atas **semua key** di `_feedBox`, untuk yang cocok slug-nya: `FeedItem.fromJson(...)`, lalu `getReadChapters(...)` (yang sendiri melakukan beberapa `_feedBox`/`_historyBox.get`), `getHistoryItem(...)`, dan `_isChapterReadMatch` per chapter. Kompleksitas O(feedKeys × chapters) per kartu.
  - `getHistoryProgress` → `getHistoryItem` (`local_storage.dart:2227-2300`) → beberapa `box.get` langsung, dan jika tidak ketemu, **full scan** `_historyBox.keys` dengan string matching. Untuk slug yang sudah clean/source-scoped biasanya O(1), tapi fallback scan tetap mungkin.
  - `isFavorite` → `getFavorite` (`local_storage.dart:1166-1230`) → `box.get` langsung, fallback full scan jika tidak ketemu.
- Untuk grid 3 kolom di ponsel, ~6-9 kartu tampil; scroll membangun beberapa kartu/frame. Beban per-frame = (kartu baru) × (feedKeys × chapters). Dengan puluhan feed item ini menjadi puluhan–ratusan box.get + deserialisasi per frame scroll.

**Rekomendasi (prioritas tertinggi):**
- **Pre-compute nilai badge di level layar**, bukan di dalam kartu. Layar sudah punya list item (dari `getFavorites`/`getHistory`); saat membangun list, hitung `unreadUpdates`/`isFav`/`progress` sekali per item (atau cache di map ber-key slug), lalu teruskan ke `MangaCard` sebagai parameter. Ini mengubah O(visibleCards × feedKeys) menjadi satu kali pass per layar.
- Atau, untuk `getMangaUnreadNewChaptersCount`, bangun indeks terbalik: `Map<String, int>` slug→unreadCount di-cache di `LocalStorage`, diperbarui saat feed/history berubah (notifier), sehingga query kartu jadi O(1) map lookup.
- Singkirkan `ListenableBuilder` dari kartu (poin 1a) sehingga kartu tidak re-query saat box berubah — data sudah disuplai dari layar.

**3b. `LayoutBuilder` di dalam `MangaCard`**
- File: `lib/shared/widgets/manga_card.dart:51-53`
- `LayoutBuilder` memicu extra layout pass per kartu untuk menghitung `coverHeight` dan meneruskan `constraints.maxWidth` ke `CachedCover`. Untuk item grid dengan lebar tetap, ini berlebihan.
- **Rekomendasi:** kirim lebar eksplisit dari itemBuilder (grid tahu cell width), atau gunakan `AspectRatio` murni tanpa `LayoutBuilder`, dan beri `CachedCover` `memCacheWidth` eksplisit alih-alih andalkan `LayoutBuilder`.

**3c. `CachedCover` — konfigurasi gambar**
- File: `lib/shared/widgets/cached_cover.dart`
- **Bagus:** `memCacheWidth`/`memCacheHeight` SUDAH dikonfigurasi (line ~ `effectiveMemCacheWidth`, default 360 untuk cover manga; clamp 180-500 untuk bounded width). Ini membatasi decode bitmap di RAM. ✅
- `cacheKey` tidak diatur eksplisit, tapi `CachedNetworkImage` memakai `key: ValueKey('$url-$_retryAttempt')` — cukup untuk identifikasi. Tidak ada masalah cache key yang jelas.
- **Catatan minor:** `_checkCachedFile()` (line ~ initState/didUpdateWidget) melakukan `MangaCoverCacheManager.instance.getFileFromCache(rawUrl)` secara async lalu `setState` jika ketemu → satu rebuild tambahan per cover saat pertama muncul. Untuk banyak kartu yang muncul saat scroll, ini menambah tick rebuild.
- **Catatan:** `fadeInDuration` default 150ms (singkat, OK). Tidak ada animasi idle.
- **Rekomendasi minor:** pertimbangkan memeriksa `_cachedFile` sinkron dari `LocalStorage.getSavedCoverPath` saja (sudah dilakukan di awal) dan jangan picu `setState` async tambahan untuk `getFileFromCache` jika cover akan segera dimuat oleh `CachedNetworkImage` juga — hindari double-load + rebuild.

**3d. Badge painter tanpa RepaintBoundary**
- File: `lib/shared/widgets/manga_card_badges.dart` — `ReadingProgressBadge` memakai `CustomPaint` dengan `ProgressPainter` (`shouldRepaint` benar). Tanpa `RepaintBoundary`, saat parent repaint, badge ikut repaint. Bukan penyebab utama tapi menambah.
- **Rekomendasi:** bungkus tiap kartu grid dengan `RepaintBoundary` (lihat poin 5b).

---

### 4. floating_navbar.dart — AnimationController & AnimatedBuilder

- File: `lib/shared/widgets/floating_navbar.dart`
- **AnimationController per-tab** (`_tapControllers`, line 77-81): satu controller per item, hanya `forward(from: 0)` saat tab diketuk (line ~ `didUpdateWidget` line 86-91 & `onTap` line 304). Durasi 700ms lalu berhenti. **Tidak berjalan saat idle** — jadi bukan penyebab jank scroll murni. ✅
- **`_pillController`** (slide indicator, 300ms) juga hanya jalan saat ganti tab. ✅
- **Yang suboptimal:** ada **dua** `AnimatedBuilder(animation: _pillAnimation)`:
  - Line 270: membungkus *pill indicator* saja (scoped, benar).
  - Line 307: membungkus **isi tiap nav item** di dalam `List.generate` (line 293). Saat slide 300ms, **setiap frame** merebuild semua 4 item (rebuild `SvgPicture.asset`/`Icon`/`Badge`, `Color.lerp`, `FontWeight.lerp`, dan `_wrapWithAnim`). Itu ~4 rebuild × ~18 frame.
- **Catatan:** tidak ada idle animation. Shimmer (`shimmer_loading.dart`) hanya aktif saat placeholder loading, bukan saat idle.

**Kenapa (mungkin) berhubungan dengan jank:** jika user mengganti tab lalu langsung scroll, animasi slide (60fps × 0.3s) bersamaan dengan scroll membangun kartu → beban tumpang tindih.

**Rekomendasi:**
- Pisahkan logika `Color.lerp`/`FontWeight` agar tidak memerlukan rebuild tiap frame. Karena indikator pill sudah `AnimatedBuilder` terpisah (line 270), warna icon sebenarnya bisa di-*drive* oleh `_pillController` juga tapi dengan `RepaintBoundary` di tiap item, atau cache nilai lerp. Minimal, bungkus `iconWidget` (yang statis) sebagai `child` dari `AnimatedBuilder` agar tidak dibangun ulang tiap frame — saat ini `iconWidget` sudah di-build di luar builder, tapi `animatedIcon = _wrapWithAnim(...)` dipanggil di dalam builder (line 372-376) setiap frame, yang memanggil `_buildFeedAnim` yang membuat `Badge`/`CustomPaint` baru tiap frame.
- Bungkus tiap nav item dengan `RepaintBoundary` agar repaint pill tidak memaksa repaint seluruh bar.

---

### 5. history_screen.dart & favorites_screen.dart — list/grid & const

**5a. history_screen: dua `getHistory()` penuh + GridView bersarang shrinkWrap**
- File: `lib/features/history/history_screen.dart:613-614`
  ```
  final all = LocalStorage.getHistory(sortOrder: _sortOrder);
  final lastRead = LocalStorage.getHistory(sortOrder: 'last_read').firstOrNull;
  ```
  `getHistory()` (`local_storage.dart:1953-2040`) melakukan full scan `_historyBox.keys`, filter prefix mode, dedupe, lalu `list.sort()`. Dipanggil **dua kali** di setiap rebuild (sort aktif + `last_read`), padahal `lastRead` hanya butuh 1 item. Untuk library besar ini dobel beban.
- File: `lib/features/history/history_screen.dart:721-723` — `GridView.builder` (mode tidak dikelompokkan), `gridDelegate` sudah `const` ✅. Tidak ada `itemExtent` (GridView tidak mendukungnya; tidak ada masalah di sini).
- File: `lib/features/history/history_screen.dart:776-780` — mode dikelompokkan: `ListView.builder` yang di dalamnya menaruh `GridView.builder` dengan **`shrinkWrap: true`** + **`NeverScrollableScrollPhysics()`**. Ini memaksa GridView mengukur **semua** anaknya (bukan lazy) untuk menentukan tinggi group — berat untuk group besar. Lazy building hilang.
- File: `lib/features/history/history_screen.dart:834-835` — `_HistoryCard.build()` memanggil `isFavorite` + `getMangaUnreadNewChaptersCount` per kartu (sama beratnya dengan MangaCard, poin 3a).

**Rekomendasi:**
- Ganti pemanggilan `lastRead`: ambil dari `all` jika sort-nya kompatibel, atau simpan/cached satu item `last_read` di state (perbarui saat history box berubah) — jangan full-scan dua kali.
- Untuk mode dikelompokkan, ganti struktur `ListView > Column > GridView(shrinkWrap)` dengan satu `CustomScrollView` berisi `SliverList` header + `SliverGrid` per group (atau `SliverList` untuk header, `SliverGrid` untuk item). Ini mengembalikan lazy building dan menghilangkan pengukuran penuh.
- Pre-compute badge values (poin 3a).

**5b. const yang bisa dipakai**
- Sebagian besar `SizedBox`, `SizedBox(height:)`, `SliverGridDelegateWithFixedCrossAxisCount` sudah `const`. ✅
- Yang belum const (karena memakai `theme`): banyak `BoxDecoration`/`TextStyle`/`Container` di `manga_card.dart`, `history_screen.dart`, `favorites_screen.dart`. Ini tidak bisa di-`const` karena memakai `theme.colorScheme.*` (runtime). Bukan pelanggaran, tapi menandakan tiap build membuat objek baru.
- **Rekomendasi nyata:** tambahkan `RepaintBoundary` di sekitar tiap kartu grid/list. Saat ini **tidak ada `RepaintBoundary`** di sekitar item list/grid mana pun (grep `RepaintBoundary` hanya menemukan di reader, predictive-back, dan page image widgets). Tanpa ini, repaint salah satu kartu memaksa repaint saudaranya.

**5c. favorites_screen: list mode tanpa itemExtent**
- File: `lib/features/favorites/favorites_screen.dart:1598` (compact) & `1623` (details): `ListView.builder` tanpa `itemExtent`/`prototypeItem`. Tiap item harus diukur. Item compact punya tinggi hampir tetap (cover 44px + padding) — cocok untuk `itemExtent` atau `prototypeItem`. Item details tingginya bervariasi (Wrap badge), jadi `prototypeItem` tidak akurat — biarkan tanpa.
- **Rekomendasi:** untuk mode compact, tambahkan `itemExtent` (jika tinggi benar-benar tetap) atau `prototypeItem` (lebih aman). Untuk grid (line 1553) tidak ada `itemExtent` (tidak didukung) — OK.

---

### 6. ListenableBuilder di favorites_screen.dart — merge 4 listener di dalam Expanded

- File: `lib/features/favorites/favorites_screen.dart:1404-1423` (sudah dibahas poin 1c). Rebuild-nya agresif karena:
  - TabBar memanggil `getFavorites(category: cat).length` untuk **setiap** tab (line 1425) → N full-scan + sort hanya untuk badge count, tiap rebuild.
  - Tiap tab memanggil `getFavorites(category: cat)` (line 1460) + `_filterAndSortItems()` (line 1461, definisi 211) → sort ulang seluruh list, tiap rebuild.
  - Padahal `_filterAndSortItems` hanya mengurutkan ulang list yang isinya sama — bisa di-memoize per (tab, sortOrder) sampai data berubah.
- Tambahan: `getFavorites(category:)` (`local_storage.dart:1084-1135`) sendiri sudah melakukan `list.sort()` internal (sort by addedAt desc) **sebelum** `_filterAndSortItems` mengurutkan ulang → **dua sort** per tab per rebuild.

**Rekomendasi:**
- Memoize hasil `getFavorites(category:)` + sort per tab. Hitung ulang hanya ketika box favorit benar-benar berubah, simpan di state, bukan di tiap `build()`.
- Cache count per tab sekali; hanya invalidasi saat favorit berubah.
- Pre-compute badge (poin 3a) sehingga tidak perlu `getMangaUnreadNewChaptersCount`/`getHistoryProgress` per item.
- Singkirkan `listenFeed` dari merge — favorites tidak bergantung pada feed box (kecuali badge unread yang sebaiknya di-precompute).

---

### 7. feed_screen.dart — CustomScrollView + SliverList, regroup setiap rebuild

- File: `lib/features/feed/feed_screen.dart:124-131` — `ValueListenableBuilder(listenContentMode)` bersarang di dalam `ValueListenableBuilder(listenFeed)` (atau sebaliknya, line 124 → 127). Tiap perubahan feed/contentMode rebuild seluruh body.
- File: `lib/features/feed/feed_screen.dart:131` → `LocalStorage.getFeedItems(modeId: activeModeId)` per rebuild.
- File: `lib/features/feed/feed_screen.dart:163` → `..._buildGroupedFeedList(context, items, theme)` (definisi line 328) yang **setiap rebuild**: iterasi semua item, bangun `Map<String, List<FeedItem>>`, lalu untuk setiap group buat `SliverToBoxAdapter` (header) + `SliverPadding(SliverList(...))`. SliverList-nya lazy (delegate), tapi pengelompokan + konstruksi widget sliver adalah O(n) per rebuild.
- File: `lib/features/feed/feed_screen.dart:243` (header strip) & `392-393` (tile): memanggil `getUnreadNewChaptersCount(item)` / `isFeedItemUnread(item)` per item. `getUnreadNewChaptersCount` (`local_storage.dart:3188`) — serupa beratnya, full scan read chapters per item.
- `feedHeaderVisibleProvider` (`feed_provider.dart:299-319`) hanyalah `Notifier<bool>` toggle — **bukan** scroll listener, jadi tidak memicu rebuild saat scroll. ✅

**Kenapa jank:** saat feed box berubah (sering saat/sepulah cek pembaruan), seluruh grouped list diregroup + tiap tile re-query unread. Jika bersamaan dengan scroll, frame drop.

**Rekomendasi:**
- Flatten dua `ValueListenableBuilder` jadi satu `ListenableBuilder(merge([contentMode, feed]))`.
- Cache hasil grouping + `getFeedItems` di state, invalidasi hanya saat feed/contentMode berubah (notifier), bukan rebuild tiap kali.
- Pre-compute `unreadChCount`/`isUnread` per feed item saat feed dibangun (satu pass), teruskan ke tile sebagai parameter; jangan query di dalam `_buildFeedItemTile`.
- Gunakan `SliverChildBuilderDelegate` dengan `addRepaintBoundaries: true` (default sudah true di `SliverList`? — `SliverChildBuilderDelegate.addRepaintBoundaries` default `true`), tapi pastikan tile tidak re-query tiap build.

---

### 8. main_screen.dart — ValueListenableBuilder bersarang

- File: `lib/features/main/main_screen.dart:296-316` — tiga `ValueListenableBuilder` bersarang: `listenSettings` → `listenContentMode` → `listenFeed`, semuanya membungkus `Scaffold` + `IndexedStack`.
- Seperti dibahas poin 2: anak IndexedStack tidak rebuild (instance `_screens` stabil), tapi `Scaffold` + kedua `FloatingNavbar` rebuild tiap perubahan settings/contentMode/feed. Dan `getTotalUnreadNewChaptersCount(modeId:)` (line 317) — O(n) scan feed box (`local_storage.dart:3414-3435`) — dipanggil tiap rebuild feed.
- `isFloatingNav`/`isShowLabels` (line 300-301) dibaca di dalam builder `listenSettings` — benar, karena hanya butuh saat settings berubah. Tapi karena seluruh Scaffold ada di dalamnya, rebuildnya luas.

**Rekomendasi:**
- Flatten jadi satu `ListenableBuilder(Listenable.merge([settings, contentMode, feed]))`.
- Keluarkan `IndexedStack` ke `child:` (tetap) karena tidak bergantung nilai listener; `ValueListenableBuilder`/`ListenableBuilder` punya parameter `child` yang tidak rebuild.
- Bungkus hanya navbar + badge unread dengan listener; body (`IndexedStack`) di luar.
- Cache `getTotalUnreadNewChaptersCount` agar tidak full-scan tiap tick.

---

## Konklusi & Prioritas Fix

Dampak terbesar ke terkecil (untuk scroll murni):

| Prioritas | Masalah | File:baris | Fix inti |
|---|---|---|---|
| P0 | `getMangaUnreadNewChaptersCount`/`getUnreadNewChaptersCount`/`getHistoryProgress` dipanggil per-kartu di build | manga_card.dart:43-45, history_screen.dart:834-835, favorites_screen.dart (compact/detailed) | Pre-compute nilai badge di level layar / bangun map cache slug→unread di LocalStorage (O(1) lookup) |
| P0 | `ListenableBuilder.merge([3])` per kartu di MangaCard | manga_card.dart:36-42 | Hapus subscription per-kartu; suplai data dari itemBuilder |
| P1 | Dua `getHistory()` full-scan di build history | history_screen.dart:613-614 | Cache `lastRead`; jangan scan dua kali |
| P1 | TabBar getFavorites(cat).length per tab + sort ganda per rebuild | favorites_screen.dart:1425, 1460-1461 | Memoize per-tab; invalidasi saat box berubah |
| P1 | GridView shrinkWrap di mode grouped history | history_screen.dart:776-780 | Ganti ke CustomScrollView + SliverGrid |
| P2 | Tiga VLB bersarang membungkus Scaffold di main_screen | main_screen.dart:296-316 | Flatten; `IndexedStack` ke `child`; bungkus hanya navbar |
| P2 | merge 4 listener di history & favorites | history_screen.dart:605, favorites_screen.dart:1404 | Batasi listener; buang `listenFeed` yang tidak perlu |
| P2 | feed regroup + re-query unread per rebuild | feed_screen.dart:163, 328, 392-393 | Cache grouping + pre-compute unread |
| P3 | LayoutBuilder di MangaCard | manga_card.dart:51 | Kirim width eksplisit dari grid |
| P3 | AnimatedBuilder(_pill) membungkus seluruh bar item | floating_navbar.dart:307 | Scope; RepaintBoundary per item |
| P3 | Tidak ada RepaintBoundary di sekitar kartu grid/list | (semua list/grid) | Bungkus tiap kartu RepaintBoundary |
| P3 | ListView compact tanpa itemExtent/prototypeItem | favorites_screen.dart:1598 | Tambah itemExtent/prototypeItem |

**Yang TIDAK menjadi masalah** (diverifikasi, jangan diubah sia-sia):
- `CachedCover` sudah set `memCacheWidth`/`memCacheHeight` ✅
- Animasi floating_navbar (tap/pill) tidak jalan saat idle ✅
- Shimmer hanya saat loading ✅
- `feedHeaderVisibleProvider` bukan scroll listener ✅
- `IndexedStack` anak tidak rebuild saat parent VLB fires (instance stabil) ✅

---

## Catatan Implementasi (untuk step berikutnya)

- Semua perubahan harus menjaga behavior: badge "new chapters", favorit, progres baca, dan reactivity terhadap perubahan data tetap bekerja. Pre-compute/memoize harus di-invalidasi saat notifier (favorites/history/feed/contentMode) memberi sinyal.
- Karena `getMangaUnreadNewChaptersCount` dipakai juga oleh badge di feed tile dan notifikasi (`getTotalUnreadNewChaptersCount`), cache map slug→unread sebaiknya dibangun sekali di `LocalStorage` saat feed/history berubah dan dipakai bersama.
- Verifikasi setelah perubahan: build & run app, scroll cepat di History/Favorit/Umpan, amati frame timing (Flutter DevTools Performance / Timeline). Pastikan tidak ada regression pada badge count.
