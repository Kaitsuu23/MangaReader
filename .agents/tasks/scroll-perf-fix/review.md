# Scroll-performance refactor: listener flattening, badge pre-compute, RepaintBoundary/itemExtent

This change lightens scroll by removing the per-card `ListenableBuilder` from `MangaCard`, flattening the nested `ValueListenableBuilder`s in `main_screen` and `feed_screen` into single merged listeners, dropping the redundant `listenFeed` from the history and favorites listeners, and adding a `RepaintBoundary` to `MangaCard` plus an `itemExtent` to the compact favorites list. Favorite/progress/unread badge values are now pre-computed in the parent `itemBuilder` and passed into `MangaCard`/`_HistoryCard` as optional parameters, so the per-card `LocalStorage` re-query no longer runs on every rebuild. The main library screens keep reacting to favorites/history/contentMode changes, and `lastRead` is now derived from the already-fetched history list instead of a second full box scan. `flutter analyze lib/` reports no issues.

Watch for: dropping `MangaCard`'s internal listener removes live badge reactivity in the three screens that use `MangaCard` without a wrapping data listener — explore "Saran Bacaan", the source-catalog grid, and manga-details "Komik Serupa" — so favorite/progress/unread badges there go stale after the card's first build (`source_view` is unaffected; it wraps its build in favorites+history+feed). Separately, per the P1 instruction, history/favorites unread badges intentionally no longer live-update on background feed-box changes, while the navbar unread badge stays feed-reactive.

**Verdict**: NEEDS_CHANGES

## High-level view

**MangaCard listener removal and the pre-compute contract.** `MangaCard` no longer subscribes to favorites/history/feed; it computes `isFavorite`/`readProgress`/`unreadCount` once per `build`, using caller-supplied values when the new optional params are non-null and falling back to a `LocalStorage` query otherwise. History and favorites pre-compute the three values in their `itemBuilder` and pass them in, and `source_view` keeps its own favorites+history+feed wrapper so its cards stay reactive. The contract holds wherever a parent wraps the list in a data listener — but `explore_screen`, `source_catalog_screen`, and `manga_details_screen` do not, so their `MangaCard`s lose live badge updates after the initial build.

**Sanctioned feed-listener tradeoff (P1).** History and favorites dropped `listenFeed` from their merged listener, so a background feed-box change no longer rebuilds those screens. Content, sort, favorite hearts, and reading progress remain reactive (favorites/history/contentMode are still listened); only the unread-new-chapters badge stops live-updating from feed changes. The navbar unread badge in `main_screen` still listens to feed, so it stays live. This matches the task's explicit P1 instruction.

**lastRead from the fetched list.** `history_screen` replaced the second `getHistory(sortOrder: 'last_read')` full scan with `_mostRecentRead(all)`, which walks the already-fetched list for the max `updatedAt`. `getHistory`'s dedupe is sort-independent and `'last_read'` sorts by `updatedAt` descending, so this is equivalent to the old `.first` (the only difference is an unspecified tie-break when two items share the same millisecond, which is negligible).

**main_screen and feed_screen flattening.** `main_screen`'s three nested VLBs are now one `ListenableBuilder.merge([settings, contentMode, feed])` with `IndexedStack` passed as the `child`, so listener ticks rebuild only the navbar and `unreadCount`, not the tab bodies — which didn't rebuild under the old nested form either, since the `_screens` instances are stable and element-reused. `feed_screen`'s two nested VLBs collapsed to one `merge([contentMode, feed])` with the same coverage.

**RepaintBoundary and compact itemExtent.** `MangaCard` wraps its root in `RepaintBoundary` for paint isolation, and the compact favorites list gets `itemExtent: 56.0`, which matches the item's measured natural height (44px cover + 12px vertical padding). The fixed extent can clip the title/subtitle at very large accessibility font scales, where the text rows outgrow the 44px cover.

<details>
<summary>Issues (2)</summary>

1. **MangaCard reactivity lost in unwrapped call sites** [confirmed] — `explore_screen` ("Saran Bacaan"), `source_catalog_screen` (catalog grid), and `manga_details_screen` ("Komik Serupa") use `MangaCard` with no wrapping favorites/history/feed listener, so after this PR their cards no longer live-update favorite/progress/unread badges when the underlying boxes change (first-build values are still correct). Wrap those lists in a `ListenableBuilder.merge([listenFavorites, listenHistory, listenFeed])` matching `source_view_screen`'s existing pattern, or consciously accept the staleness for these discovery surfaces.
2. **Compact itemExtent may clip at large font scale** [possible] — `itemExtent: 56.0` fixes the compact favorites row height; at normal font scale it matches the natural height exactly, but at large accessibility font scales the one-line title/subtitle can exceed the 44px cover and clip. Verify with system font scale at ~1.5–2x; if clipping shows, raise the extent or drop to `prototypeItem`/auto-size for that case.

</details>

<details><summary>Details</summary>

### MangaCard: listener removed, badges pre-computed

The old `MangaCard` wrapped its entire subtree in `ListenableBuilder(Listenable.merge([listenFavorites, listenHistory, listenFeed]))`, so every visible card held three subscriptions and re-ran `isFavorite`, `getHistoryProgress`, and `getMangaUnreadNewChaptersCount` on every box notification. The new card has no listener; `build` runs the three queries once (or uses the optional `isFavorite`/`readProgress`/`unreadCount` params when the caller supplies them), and a `RepaintBoundary` sits at the root.

The optional-params design is backward-compatible by construction: callers that don't pass the values (currently `explore_screen`, `source_catalog_screen`, `manga_details_screen`, and the test widgets) get the same values via the `?? LocalStorage.…` fallback, just without a subscription. What it does not preserve is *live* reactivity for callers whose parent never rebuilds on a data change.

Checking every call site:

```
favorites grid     → merge([favorites, history, contentMode])  + itemBuilder pre-computes  ✓ reactive
history list       → _HistoryCard, merge([history, favorites, contentMode]) + pre-computes  ✓ reactive
source_view grids  → merge([favorites, history, feed])  whole-build wrapper              ✓ reactive
explore "Saran"    → NO data listener anywhere in file                                   ✗ stale after build
source_catalog     → NO data listener anywhere in file                                   ✗ stale after build
manga_details recs → only a title-opacity VLB, no data listener                          ✗ stale after build
```

`explore_screen` is a `ConsumerStatefulWidget` whose `initState` only loads suggestions and prefs (no `addListener`); `source_catalog_screen` and `manga_details_screen` likewise have no favorites/history/feed listener (confirmed by search). So those cards render correct badges on first build but go stale the moment a box changes — favoriting a "Saran Bacaan" manga from its detail page no longer lights up the heart on the explore card until explore rebuilds, and a background feed check no longer surfaces a new unread badge there. The "Komik Serupa" carousel in `manga_details_screen` is the same: stale within a single detail-screen session, refreshed only on re-open.

This is the one place the task's premise ("the parent screens already wrap the list with a listener") doesn't hold. `source_view_screen` proves the intended fix is cheap and consistent with the task's own philosophy: wrap those three lists in the same `merge([favorites, history, feed])` builder, and the cards regain live updates without reintroducing per-card subscriptions.

### History and favorites: listener narrowing and the feed tradeoff

Both screens reduced their merged listener from four to three by removing `listenFeed`. The consequence is deliberate and was called out by the task: a feed-box change (a background "check for new chapters" run) no longer rebuilds history or favorites, so the unread-new-chapters badge on their cards won't tick over live from feed updates.

What still drives rebuilds — and therefore still refreshes badges — is `listenFavorites`, `listenHistory`, and `listenContentMode`. That covers the cases that actually change a card's badges in normal use: toggling a favorite rebuilds favorites (heart/category) and history (heart); reading or progressing a chapter rebuilds both (progress updates, and unread count drops because `listenHistory` fires); switching content mode rebuilds both (different item set). The only gap is "new chapters appeared in the feed for a manga I haven't touched," which is exactly the feed-only path the task chose to drop.

The navbar unread badge is unaffected because `main_screen` keeps `listenFeed` in its merge, so the total unread count there still updates live. The history/favorites unread badge still recomputes correctly the next time anything else triggers a rebuild (including scrolling new cards into view, whose `itemBuilder` re-queries). The value is never wrong, only occasionally delayed on those two screens.

### lastRead derived from the fetched list

The old code called `getHistory` twice per rebuild — once with the active `_sortOrder` for the list, once with `'last_read'` to grab `.first` for the "Lanjut" FAB. The new code calls it once and derives `lastRead` via `_mostRecentRead(all)`, a single O(n) pass for the maximum `updatedAt`.

This is equivalent because `getHistory` collects and dedupes the same item set regardless of `sortOrder` — the dedupe key is `source::slug` and runs in the collection loop, before the sort — and the `'last_read'` case orders by `updatedAt` descending, so `.first` is exactly the max-`updatedAt` item that `_mostRecentRead` returns. The empty case matches too: `_mostRecentRead` returns `null` when the list is empty, matching the old `.firstOrNull`. The only divergence is when two history entries share the same `updatedAt` millisecond: `List.sort` isn't stable in Dart, so the old `.first` picked an unspecified one, and `_mostRecentRead` picks the first encountered with that max — both are defensible "most recent" choices and the situation is effectively unreachable.

### main_screen and feed_screen: listener flattening

`main_screen` replaced `listenSettings → listenContentMode → listenFeed` with one `ListenableBuilder.merge([settings, contentMode, feed])`, and moved `IndexedStack` into the builder's `child` so the tab bodies aren't rebuilt when the listener fires — only the `Scaffold` shell, the two `FloatingNavbar` branches, and `unreadCount` are. The tab bodies didn't rebuild under the old nested VLBs either (stable `_screens` instances are element-reused), and the navbar still refreshes on settings (floating/labels), contentMode, and feed (unread badge) changes. `getTotalUnreadNewChaptersCount` is still called inside the builder on every feed tick; the task's P2 didn't ask to cache it, so that pre-existing O(n) call is unchanged.

`feed_screen` collapsed `listenContentMode` + `listenFeed` into one `merge([contentMode, feed])` with identical coverage. The per-rebuild regrouping and per-tile `getUnreadNewChaptersCount` re-query are unchanged here — they're pre-existing and outside this task's P0–P3 scope.

### RepaintBoundary and compact itemExtent

`MangaCard` now wraps its root `InkWell` in a `RepaintBoundary`, isolating each card's paint so a repaint on one card doesn't force its siblings to repaint — a direct fix for the investigation's "no RepaintBoundary around any grid/list item" finding. `_HistoryCard` was not wrapped; the task's P3 scoped RepaintBoundary to `MangaCard` only.

The compact favorites `ListView.builder` gets `itemExtent: 56.0`. The item's natural height is the `Row`'s tallest child (the 44×44 cover, since both texts are `maxLines: 1` and stay under 44px at normal scale) plus the container's 12px vertical padding = 56px, so the extent is exact at default font scale and just enables lazy height calculation. Because the extent is fixed, it will clip the text rows if a large accessibility font scale makes the one-line title/subtitle taller than the 44px cover — a behavior change from the old auto-sizing list, which would have simply grown the row. It's low-impact and sanctioned by the task's "~56dp" instruction, but worth confirming against large-font configs.

### Test coverage

The existing widget tests (`card_badges_test.dart`, `favorites_selection_test.dart`, `favorite_metadata_healing_test.dart`) construct `MangaCard` with `item`/`onTap` only, which still compiles because the new badge params are optional with `null` defaults. Nothing in the suite exercises the removed per-card listener or asserts that badges update on a box change, so the reactivity regression in the unwrapped call sites isn't caught automatically. The `lastRead` equivalence and the `itemExtent` clipping are likewise untested. `flutter analyze lib/` is clean per the coder's run; it was not re-run here.

</details>

<details><summary>File map</summary>

- `lib/shared/widgets/manga_card.dart` — removed per-card `ListenableBuilder`; added optional `isFavorite`/`readProgress`/`unreadCount` params with `LocalStorage` fallback; wrapped root in `RepaintBoundary`.
- `lib/features/history/history_screen.dart` — merged listener down to history+favorites+contentMode; single `getHistory` + `_mostRecentRead` for `lastRead`; `_HistoryCard` takes optional `isFavorite`/`unreadCount`; itemBuilders pre-compute badges.
- `lib/features/favorites/favorites_screen.dart` — merged listener down to favorites+history+contentMode; grid itemBuilder pre-computes badges into `MangaCard`; compact list gets `itemExtent: 56.0`.
- `lib/features/main/main_screen.dart` — three nested VLBs → one `ListenableBuilder.merge([settings, contentMode, feed])` with `IndexedStack` as `child`.
- `lib/features/feed/feed_screen.dart` — two nested VLBs → one `ListenableBuilder.merge([contentMode, feed])`.

Comparison source: investigation report at `.agents/tasks/scroll-performance-investigation.md` (documents the "before" state with code excerpts) vs. the current files. This is not a git repo, so there is no `git diff`.

</details>
