# Reader performance fixes: memory caps, scroll-path simplification, ValueNotifier HUD, repaint isolation

The change applies five performance fixes to the webtoon and paged reading paths in `manga_reader_screen.dart`, all aimed at the scroll heaviness reported in the investigation. Paged-mode pages now decode at a screen-relative resolution cap instead of full native size; the webtoon scroll handler no longer runs a per-frame `findRenderObject` loop over every page; the clock and battery HUD moved off `setState` onto `ValueNotifier`; the reader body and the three HUD bars are wrapped in `RepaintBoundary`; and paged-mode precache dropped the redundant `+2` page. No functional behavior was changed — page tracking, the slider, pull-to-chapter, and zoom paths are untouched.

Watch for: the `RepaintBoundary` wrap isolates repaint but not rebuild — the HUD-toggle `setState` still reconciles the `_buildReaderBody()` subtree, which is the deliberate trade-off the brief chose over extracting the body into a separate widget.

**Verdict**: APPROVED

## High-level view

Paged and legacy webtoon page images now pass `memCacheWidth`/`memCacheHeight` sized to ~2.2× the screen. This is the biggest win for paged-mode heaviness: pages stop decoding at native 1000–2000px and cap at roughly double the viewport, shrinking the ~3 resident bitmaps `PageView` keeps alive.

`_onWebtoonScroll` shed its O(n) per-frame loop. Page detection now runs only against the cumulative `_pageHeights`/`_estimatedPageHeight` sum, with the top and end edge cases kept; the removed `findRenderObject` block was the fallback path's peer, so behavior is preserved.

The clock and battery HUD left `setState`: they are `ValueNotifier`s updated by the 30-second timers without rebuilding the tree, and the combined battery + time `Text` is wrapped in scoped `ValueListenableBuilder`s. The static battery icon stays outside the builder since it never varied with level.

The reader body and each HUD bar sit in their own `RepaintBoundary`, so a HUD toggle reuses the reader's image layers instead of repainting them. Fix 3 already removed the only periodic rebuild, leaving the user-initiated HUD toggle as the residual rebuild trigger.

Paged precache dropped from `+1, +2, -1` to `+1, -1`; the `+2` was redundant because `PageView` already mounts the immediate neighbors.

<details>
<summary>Issues (0)</summary>

No blocking findings. The repaint-vs-rebuild note above is informational context about a deliberate trade-off the brief chose, not a defect to fix.

</details>

<details>
<summary>Details</summary>

### Memory caps on paged and legacy page images

Previously both image builders resolved to uncapped decode — the standard path used `width: double.infinity, height: double.infinity, fit: BoxFit.contain` and the legacy webtoon path used `fit: BoxFit.fitWidth, width: double.infinity`, and per `cached_cover.dart`'s derivation both yield null caps. Both now pass `memCacheWidth`/`memCacheHeight` at `(MediaQuery.sizeOf(context).width * 2.2).round()` and `(MediaQuery.sizeOf(context).height * 2.2).round()`, clamping decode to ~2.2× the viewport on each axis. `MediaQuery.sizeOf` (not `of`) is the right choice here: it reads size without registering a dependency, so a metrics change like the landscape toggle won't rebuild these images; the cap recomputes from the live `context` per build, so orientation changes pick up new dimensions for subsequently built pages.

### Webtoon scroll handler simplified to cumulative heights

`_onWebtoonScroll` no longer runs the per-frame loop that called `_pageKeys[i]?.currentContext?.findRenderObject()` and `box.localToGlobal(Offset.zero)` across pages until it found the visible one. The cumulative sum over `_pageHeights[i] ?? _estimatedPageHeight` is now the only detection path, preceded by the same `offset <= 10 → 0` and `isAtEnd → pages.length - 1` edge cases. The design decision worth stating plainly: the removed render-box search was the "preferred" path but the cumulative path was already its fallback, and `_onPageHeightMeasured` keeps `_pageHeights` accurate as each page lays out, so the cumulative result matches what the render-box search returned for rendered pages. The per-frame O(n) layout queries — the dominant webtoon scroll cost — are gone.

### Clock/battery HUD on ValueNotifier

`_currentTime`/`_batteryLevel` are now `late final ValueNotifier<String> _currentTimeNotifier` and `ValueNotifier<int?> _batteryLevelNotifier`, initialized in `initState`, disposed in `dispose`, and set via `.value` in `_updateClock`/`_getBatteryLevel` with no `setState`. The HUD renders them through a `ValueListenableBuilder<int?>` (battery) nesting a `ValueListenableBuilder<String>` (time) around the single `Text` showing `"${batteryLevel ?? 70}%  $currentTime"`. Only that text changes every 30 seconds, so only it rebuilds. The battery icon is a `const Icon(Icons.battery_5_bar_rounded)` outside the builders; it was always static and never reflected the level, so it never needed the builder. No plain `_currentTime`/`_batteryLevel` field references remain in the file.

### Repaint isolation for reader body and HUD

`_buildReaderBody()` is wrapped in `RepaintBoundary` as the first `Stack` child, and the top info bar (`if (!_showControls) Positioned`), top app bar, and bottom docked bar (`AnimatedPositioned`s) each wrap their `Container` in `RepaintBoundary`. On a HUD-toggle `setState` (`_toggleControls`, `_hideControls`) the element tree is reused (same controllers/keys), so images aren't re-decoded and the reader body's layer is reused rather than repainted — but the subtree is still reconciled on every toggle, which is the repaint-not-rebuild limitation flagged in the Watch-for line.

### Static analysis

`flutter analyze lib/` reports 0 errors and 0 issues in `manga_reader_screen.dart`. It also reports 3 `info`-level lints (`curly_braces_in_flow_control_structures`) in `lib/features/details/manga_details_screen.dart` — a file this change does not touch, so they are pre-existing, out of scope, and infos rather than errors; the brief's "0 errors" criterion is satisfied for the changed file. No git history or coder commit record was available to read the recorded analyze result (`base.sha` is `NO-GIT-REPO` and the workspace is not under version control), so this was verified by running the analyzer directly on the changed file set.

</details>

<details>
<summary>File map</summary>

- `lib/features/reader/manga_reader_screen.dart` — all five fixes in one file: `memCacheWidth`/`memCacheHeight` added to `_buildStandardPageImage` and `_buildLegacyPageImage`; `findRenderObject` loop removed from `_onWebtoonScroll`; clock/battery converted to `ValueNotifier` with a scoped `ValueListenableBuilder`; `RepaintBoundary` around the reader body and the three HUD bars; `_precacheSurroundingPages` reduced to `+1`/`-1`.

No diff is available to link — the workspace has no git repository (`base.sha` = `NO-GIT-REPO`), so the review was performed against the working tree compared to the brief.

</details>
