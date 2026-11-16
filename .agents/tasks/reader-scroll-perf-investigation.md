# Reader Scroll Performance Investigation

## Summary answer

Both reading modes are heavy, but for different reasons.

- **Webtoon heaviness is dominated by per-frame work in `_onWebtoonScroll`** (`manga_reader_screen.dart:693`). It is registered as a `ScrollController` listener, has **no throttle**, and on **every scroll frame** loops over all pages calling `findRenderObject()` + `localToGlobal()` (`:728-757`) to find the visible page, then cancels/recreates a `Timer` via `_scheduleSaveProgress()` (`:764`). A second per-frame handler, `_handleWebtoonScrollNotification` (`:3485`), runs in parallel through a `NotificationListener` on the same `ListView`, so each scroll frame is handled twice. The list itself is fine — it is a lazy `ListView.builder` with `cacheExtent: 3800` (`:3222-3226`).
- **Standard (paged) heaviness is dominated by full-resolution image decoding.** `_buildStandardPageImage` (`:3892`) builds a `CachedCover` with `width: double.infinity, height: double.infinity, fit: BoxFit.contain` and **no `memCacheWidth`/`memCacheHeight`**. In `CachedCover` that combination yields `isMangaCover=false`, `hasBoundedWidth=false`, `hasBoundedHeight=false`, so both memory caps resolve to `null` (`cached_cover.dart:514-538`). Each page is therefore decoded at its native resolution; `PageView` keeps ~3 pages alive → 3 large bitmaps resident. The same no-cap situation hits the webtoon legacy fallback (`_buildLegacyPageImage:3790` → `WebtoonSafeImage`).
- The page indicator is **already** on `ValueNotifier` (`_currentPageNotifier`, `_pullTopNotifier`, `_pullBottomNotifier`) via `ValueListenableBuilder`, so it does **not** rebuild the tree on scroll — that part is good. The clock/battery HUD is **not**; `_updateClock` (`:593`) and `_getBatteryLevel` (`:602`) call `setState`, rebuilding the entire reader tree every 30 s.
- The HUD toggle (`_showControls`) uses `setState` (`_hideControls:1736`, `_toggleControls:1743`), which rebuilds the whole `Stack` including `_buildReaderBody()`; neither the HUD bars nor the reader body are isolated with `RepaintBoundary`.

Primary fixes, in impact order: (1) set `memCacheWidth`/`memCacheHeight` on the paged (and legacy webtoon) page images; (2) throttle `_onWebtoonScroll` and drop its per-frame `findRenderObject` loop; (3) move clock/battery to `ValueNotifier`; (4) isolate the reader body and HUD with `RepaintBoundary`.

---

## Evidence

### 1. Webtoon scroll — build overhead per page

- The webtoon body is built at `_buildReaderBody()` (`:3159`), webtoon branch starts `:3196`. It uses **`ListView.builder`** (`:3222`) — lazy, good — with `cacheExtent: 3800.0` (`:3226`) and `padding: EdgeInsets.zero` (`:3227`). `cacheExtent 3800` keeps ~3–4 pages alive above/below a ~1200 px page, which is reasonable.
- Each item is a `KeyedSubtree` keyed by a `GlobalKey` from `_pageKeys` (`:3231-3233`) wrapping `_buildWebtoonPageImage` (`:3698`). `_buildWebtoonPageImage` returns a `MeasuredPageWidget` wrapping `_buildPageImage` (`:3700-3702`). `_buildPageImage` (`:3769`) builds a `SlicedPageImage` (native-slice path) with a `ReaderPageTranslatorWrapper` around it (`:3771-3785`).
- `ListView.builder` defaults `addRepaintBoundaries: true`, so **each webtoon page item already gets an automatic `RepaintBoundary`**; `SlicedPageImage` (`sliced_page_image.dart:139`) and `WebtoonSafeImage` (`webtoon_safe_image.dart:113,129`) each add their own `RepaintBoundary` too. Page-level repaint isolation is adequate.
- `_onPageHeightMeasured` (`:767`) and `_onPageImageLoaded` (`:787`) do **not** call `setState` — they only mutate maps/sets and notifiers. So height measurement does not rebuild the tree. Good.
- `webtoon_safe_image.dart` has **no `LayoutBuilder`**; it renders slices with `RawImage` (`:107-135`). `sliced_page_image.dart` **does** use a `LayoutBuilder` (`:142-160`) but only to pick a fitted width during layout, not per scroll frame — acceptable.
- Conclusion for this point: the webtoon *build* is not the problem. The per-frame scroll handler is (see #2).

### 2. `setState` that fires too often / no throttle

All `setState` call sites and their trigger conditions:

| Symbol | Line | Trigger | Rebuilds whole tree? |
|---|---|---|---|
| `_onWebtoonScroll` → `_hideControls()` | `:704-705` | first scroll frame while controls visible | yes, once per show→hide |
| `_updateClock` | `:593` | `Timer.periodic` every 30 s | **yes, every 30 s** |
| `_getBatteryLevel` | `:602` | `Timer.periodic` every 30 s | **yes, every 30 s** |
| `_hideControls` | `:1739` | scroll start / auto-hide timer | yes |
| `_toggleControls` | `:1746` | tap on reader | yes |
| `_showAutoScrollPanelOverlay`/`_hideAutoScrollPanel` | `:2079,2084` | FAB toggle | yes |
| various settings sheet / auto-scroll controls | `:2169,2207,2271,...` | user interaction | local to sheet |

- **`_onWebtoonScroll` has no throttle** (`:693-765`). It is added as a `ScrollController` listener in `initState` (`:334`), so it runs on **every** scroll frame. Per frame it:
  1. reads `_scrollController.offset`, `maxScrollExtent`, `extentAfter` (`:709-717`);
  2. **loops over all pages** (`:728`) calling `_pageKeys[i]?.currentContext?.findRenderObject()` and `box.localToGlobal(Offset.zero)` (`:731-737`) until it finds a page whose top is `<=180` and bottom `>60` — O(currentPageIndex) layout queries every frame;
  3. if no visible index found, falls back to summing `_pageHeights`/`_estimatedPageHeight` (`:745-757`);
  4. calls `_scheduleSaveProgress()` (`:764`).
- `_scheduleSaveProgress` (`:861`) **is debounced** (280 ms, cancels+recreates the `Timer`), so saving itself is not per-frame heavy — but the `Timer` cancel/recreate happens on every frame. Minor waste, not the main cost.
- The expensive part is step 2: `findRenderObject()` + `localToGlobal()` per page per frame. The cumulative-height fallback (step 3) is cheap and already correct, so the `findRenderObject` loop is redundant overhead.
- **No throttle / no `SchedulerBinding` frame gating** anywhere in `_onWebtoonScroll`.

### 3. `ValueNotifier` vs `setState`

- Page indicator is correct: `_currentPageNotifier` (`:89`) drives the top HUD via `ValueListenableBuilder<int>` (`:2541`) and the bottom slider via `ValueListenableBuilder<int>` (`:2842`). `_onWebtoonScroll` updates it with `_currentPageNotifier.value = newIndex` (`:763`) only when the index changes (`:762`) — no `setState`.
- Pull-to-chapter indicators are correct: `_pullTopNotifier`/`_pullBottomNotifier` (`:152-153`) drive `_buildPullFeedbackPill` via `ValueListenableBuilder<double>` (`:3618`); updates happen only on overscroll (`:3485-3612`).
- **Clock/battery are wrong**: `_currentTime` (`:136`) and `_batteryLevel` (`:137`) are plain instance fields rendered directly in a `Text` (`:2626`). Updating them requires `setState` (`:593,602`), which rebuilds the entire `Scaffold`/`Stack`/`_buildReaderBody()` every 30 s while reading — a periodic full rebuild of the reader tree (the `ListView`/`PageView` element is reused, so images are not re-decoded, but the whole subtree is reconciled).

### 4. Standard (paged) mode

- Paged body is built at `_buildReaderBody` paged branch (`:3267+`). Uses **`PageView.builder`** (`:3302`) with `PageScrollPhysics(parent: ClampingScrollPhysics(...))` (`:3305`) and `itemBuilder` returning `_ZoomablePageItem` → `Center` → `_buildStandardPageImage` (`:3317-3327`).
- `onPageChanged` (`:3308`) is **not** synchronously heavy: it sets `_currentPageIndex`/`_currentPageNotifier.value`, schedules save, calls `_prefetchNextPages(index)` (async network), and in a post-frame callback calls `_precacheSurroundingPages(index)` (`:3313-3316`).
- `_precacheSurroundingPages` (`:818`) precaches pages `+1, +2, -1` via `precacheImage` (`:820-859`) on **every page change** — that is three image downloads+decodes per turn. It is off-thread but adds network/decode churn; could be reduced to `+1` only (the PageView already keeps neighbors mounted).
- The real cost is `_buildStandardPageImage` (`:3892`): it builds a `CachedCover` with `width: double.infinity, height: double.infinity, fit: BoxFit.contain` (`:3899-3907`) and **passes no `memCacheWidth`/`memCacheHeight`**. Per `cached_cover.dart:514-538`, with infinite width/height, `BoxFit.contain`, and `slug==null`: `hasBoundedWidth=false`, `hasBoundedHeight=false`, `isMangaCover=false` ⇒ `effectiveMemCacheWidth=null` and `effectiveMemCacheHeight=null`. **Each page decodes at full native resolution.** For 1000–2000 px pages this is large; with `PageView` caching ~3 pages, 3 full-res bitmaps stay resident. This is the principal cause of "mode standar juga berat."
- `_ZoomablePageItem` (`:3975`) wraps each page in its own `InteractiveViewer` with a per-item `TransformationController` and a listener that calls `setState` only on zoom-state change (`:3992-4000`). Idle cost is negligible.

### 5. Image loading / memory caps

- **Primary webtoon path** `_buildPageImage` (`:3769`) → `SlicedPageImage` decodes small **native slices** via `Image.file` (`sliced_page_image.dart:155-166`). `memCacheWidth` is not applicable here because slices are already small. This path is efficient.
- **Webtoon fallback** `_buildLegacyPageImage` (`:3790`) → `CachedCover` (`:3792`, `fit: BoxFit.fitWidth, width: double.infinity`, no slug) ⇒ same no-cap resolution ⇒ **full-res decode**, then `WebtoonSafeImage` (`:3807`) resolves the full image via `imageProvider.resolve()` and slices it **synchronously on the UI thread** with `Canvas.drawImageRect` + `PictureRecorder.toImageSync` (`webtoon_safe_image.dart:73-91`). For tall webtoon strips (3000+ px) this synchronous slice work plus full-res decode causes visible jank whenever the fallback path is taken (i.e., whenever native slicing is unavailable on the platform/format).
- `sliced_page_image.dart` creates **one tile per native slice** (a handful per page, sized to stay under the GPU texture limit), stacked with `AspectRatio` (`:155-166`) — count is reasonable, not excessive.
- `cached_cover.dart` *does* set memory caps for actual covers (`isMangaCover` true or bounded dims), but reader pages satisfy neither condition, so reader pages get **no cap**.

### 6. HUD overlay toggle

- `build()` (`:2521`) returns a `Scaffold` whose `body` is a `Stack` whose **first child** is `_buildReaderBody()` (`:2556`). The HUD bars (`AnimatedPositioned` top bar `:2655`, bottom bar `:2821`) are later stack children.
- `_showControls` is toggled by `setState` in `_hideControls` (`:1739`) and `_toggleControls` (`:1746`). Because the whole `Stack` is one `build()`, **toggling the HUD rebuilds `_buildReaderBody()`** — a fresh `ListView.builder`/`PageView.builder` widget subtree is reconciled every toggle (and on the 30 s clock/battery ticks). The list/page element state is reused (same `controller`/keys), so images are not re-decoded, but the entire subtree is rebuilt and re-measured.
- The first scroll frame while controls are visible also calls `_hideControls()` (`:704`), adding one full rebuild at gesture start.

### 7. `RepaintBoundary`

- Webtoon pages: covered (ListView automatic + per-widget, see #1).
- **HUD bars are not wrapped in `RepaintBoundary`** (top info bar `:2536`, top app bar `:2655`, bottom docked bar `:2821`). The reader body and HUD sit in the same `Stack` with no boundary between them, so invalidations are not isolated.
- The reader body is not wrapped in an explicit `RepaintBoundary` separating it from the HUD; the `Stack` siblings provide some layering, but the 30 s `setState` and HUD-toggle `setState` still mark the whole `Stack` dirty.

### 8. `ScrollController` listener + `NotificationListener`

- Two per-frame paths fire on every scroll frame in webtoon mode:
  1. `_scrollController.addListener(_onWebtoonScroll)` (`:334`) — page tracking + save scheduling (the expensive one, see #2).
  2. `NotificationListener<ScrollNotification>(onNotification: _handleWebtoonScrollNotification, ...)` on the `ListView` (`:3220`) — pull-to-chapter overscroll handling (`:3485`). During normal (non-overscroll) scrolling it mostly reads metrics and early-returns after zeroing notifiers (`:3536-3541`), so it is cheap, but it still runs every frame and duplicates `_lastKnownScrollOffset`/`_isAtEndKnown` work already done in `_onWebtoonScroll`.
- In **paged** mode the same `NotificationListener` is attached to the `PageView` (`:3300`), so page-fling scroll also runs `_handleWebtoonScrollNotification` each frame — cheap, but redundant for paged mode where pull-to-chapter is the only consumer.
- Net: the two handlers overlap on `_lastKnownScrollOffset`/`_isAtEndKnown`/`maxScrollExtent` reads every frame; consolidating them removes one redundant per-frame pass.

---

## Conclusions and recommendations

### Recommendation 1 — Add memory caps to reader page images (biggest paged-mode win)
In `_buildStandardPageImage` (`manga_reader_screen.dart:3892`) pass explicit caps to `CachedCover`, e.g. `memCacheWidth: (MediaQuery.sizeOf(context).width * 2.2).round()` and `memCacheHeight: (MediaQuery.sizeOf(context).height * 2.2).round()`. This caps decode resolution to ~2× screen; text stays sharp and resident bitmaps shrink dramatically. Apply the same in `_buildLegacyPageImage` (`:3790`) so the webtoon fallback also stops decoding full-res. Verify: scroll a long chapter in paged mode — fewer decode hitches and lower memory (DevTools memory tab).

### Recommendation 2 — Throttle `_onWebtoonScroll` and drop the `findRenderObject` loop (biggest webtoon-scroll win)
`_onWebtoonScroll` (`:693`) should not run its full body every frame. Two options, pick one:
- (a) Gate page-index computation on a frame throttle (e.g., run at most every ~80–120 ms via a stored timestamp, or only on `ScrollEndNotification` + a coarse in-flight update), and rely on the existing cumulative-height path (`:745-757`) for the coarse value.
- (b) Remove the `findRenderObject()`/`localToGlobal()` loop (`:728-744`) entirely and always use the cumulative `_pageHeights`/`_estimatedPageHeight` sum — it is already implemented as the fallback and is correct now that `_onPageHeightMeasured` keeps heights accurate. This removes the per-frame O(n) layout queries outright.
Either keeps the slider/HUD accurate and removes per-frame layout work. Verify: webtoon scroll feels smooth; slider still tracks the right page.

### Recommendation 3 — Consolidate the two per-frame scroll handlers
Move page tracking into `_handleWebtoonScrollNotification` (`:3485`) (which already runs per frame) and remove `_scrollController.addListener(_onWebtoonScroll)` (`:334`), or vice-versa. Eliminating the duplicate per-frame pass halves per-frame listener cost. Verify: page indicator and pull-to-chapter both still work after the merge.

### Recommendation 4 — Move clock/battery to `ValueNotifier`
Replace `_currentTime`/`_batteryLevel` fields (`:136-137`) with `ValueNotifier<String>`/`ValueNotifier<int?>`, update them in `_updateClock` (`:593`)/`_getBatteryLevel` (`:602`) **without `setState`**, and wrap the battery/time `Text` (`:2626`) in a `ValueListenableBuilder`. This stops the every-30 s full rebuild of the reader tree. Verify: clock still updates; no 30 s frame hitch during reading.

### Recommendation 5 — Isolate HUD and reader body from each other
- Wrap each HUD bar (`AnimatedPositioned` top `:2655`, bottom `:2821`) and the top info bar (`:2536`) in `RepaintBoundary` so they do not repaint with the reader.
- Extract `_buildReaderBody()` into its own `const`-friendly `StatelessWidget` (or wrap its result in `RepaintBoundary`) so `_showControls`/clock `setState`s no longer rebuild the `ListView`/`PageView` subtree. Verify: toggling HUD no longer reconciles the whole reader tree (DevTools "Rebuild stats").

### Recommendation 6 — Reduce per-turn precache churn (minor)
`_precacheSurroundingPages` (`:818`) precaches `+1, +2, -1` on every `PageView` page change (`:3314`). Reduce to `+1` only (the PageView already mounts neighbors). Verify: faster page turns in paged mode.

### Recommendation 7 — Make the webtoon fallback slicing non-blocking (minor, only if fallback path is common)
If `SlicedPageImage` native slicing is unavailable on some sources, `_buildLegacyPageImage` (`:3790`) hits `WebtoonSafeImage`, which slices synchronously on the UI thread (`webtoon_safe_image.dart:73-91`). Combined with Recommendation 1's memory cap, decode cost drops; additionally consider moving the slice loop off the UI thread or preferring the existing native-slice path. Verify: fallback pages load without a frame stall.

---

## Files inspected

- `lib/features/reader/manga_reader_screen.dart` (build `:2521`, `_buildReaderBody:3159`, webtoon `ListView.builder:3222`, paged `PageView.builder:3302`, `_onWebtoonScroll:693`, `_onPageHeightMeasured:767`, `_onPageImageLoaded:787`, `_prefetchNextPages:797`, `_precacheSurroundingPages:818`, `_scheduleSaveProgress:861`, `_handleWebtoonScrollNotification:3485`, `_buildPullFeedbackPill:3613`, `_buildWebtoonPageImage:3698`, `_buildPageImage:3769`, `_buildLegacyPageImage:3790`, `_buildStandardPageImage:3892`, `_ZoomablePageItem:3975`, `MeasuredPageWidget:4031`, `WebtoonSmoothScrollPhysics:4290`).
- `lib/shared/widgets/webtoon_safe_image.dart` (sync slicing `:73-91`, `RepaintBoundary:113,129`).
- `lib/shared/widgets/sliced_page_image.dart` (`PageSliceCache`, `LayoutBuilder:142-160`, `RepaintBoundary:139`).
- `lib/shared/widgets/cached_cover.dart` (mem-cache derivation `:514-538`, passed to `CachedNetworkImage` `:564-565`).
- `lib/features/translator/widgets/reader_page_translator_wrapper.dart` (lightweight; resolves file async, returns `widget.child` when translate disabled — no per-frame cost).
