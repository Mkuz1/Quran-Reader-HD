import 'dart:ui' show DisplayFeatureState, DisplayFeatureType, PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/quran.dart';
import 'common.dart';
import 'page_widget.dart';

/// A vertical hinge or fold, in global coordinates, that a two-page spread should straddle.
Rect? verticalFold(MediaQueryData mq) {
  for (final f in mq.displayFeatures) {
    if (f.type == DisplayFeatureType.cutout) continue;
    if (f.bounds.height >= mq.size.height * 0.9 && f.bounds.width < mq.size.width / 3) return f.bounds;
  }
  return null;
}

/// A horizontal fold (a foldable half-opened like a laptop), in global coordinates.
Rect? horizontalFold(MediaQueryData mq) {
  for (final f in mq.displayFeatures) {
    if (f.type == DisplayFeatureType.cutout || f.state != DisplayFeatureState.postureHalfOpened) continue;
    if (f.bounds.width >= mq.size.width * 0.9 && f.bounds.height < mq.size.height / 3) return f.bounds;
  }
  return null;
}

/// One page or a two-page spread, turned right-to-left like the printed mushaf.
class MushafReader extends StatefulWidget {
  /// The hinge, when the reader spans the whole screen width on an unfolded device.
  final Rect? fold;

  /// Space kept free at the bottom for the floating dock, so it never covers the page.
  final double bottomInset;

  /// Full screen: the page gets nearly all the room, with only a hairline margin.
  final bool edgeToEdge;
  const MushafReader({super.key, this.fold, this.bottomInset = 0, this.edgeToEdge = false});

  @override
  State<MushafReader> createState() => _MushafReaderState();
}

class _MushafReaderState extends State<MushafReader> {
  PageController? _controller;
  bool? _dual;
  DateTime _lastWheel = DateTime(0);

  static int _index(int page, bool dual) => dual ? (page - 1) ~/ 2 : page - 1;
  static int _pageAt(int index, bool dual) => dual ? index * 2 + 1 : index + 1;

  @override
  void initState() {
    super.initState();
    model.addListener(_sync);
  }

  @override
  void dispose() {
    model.removeListener(_sync);
    _controller?.dispose();
    super.dispose();
  }

  /// Follows page changes made elsewhere (sidebar, slider, recitation).
  void _sync() {
    final c = _controller, dual = _dual;
    if (c == null || dual == null || !c.hasClients || c.page == null) return;
    final target = _index(model.page, dual);
    final shown = c.page!.round();
    if (shown == target) return;
    if ((shown - target).abs() <= 2) {
      c.animateToPage(target, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      c.jumpToPage(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final ratio = box.maxWidth / box.maxHeight;
      final fold = widget.fold;
      // Two pages side by side need a landscape-ish area; a hinge down the middle makes a natural spread.
      final dual = model.dualPage && (ratio > 0.95 || (fold != null && ratio > 0.7));
      model.effectiveDual = dual;
      if (_dual != dual) {
        _controller?.dispose();
        _controller = PageController(initialPage: _index(model.page, dual));
        _dual = dual;
      }
      final count = dual ? (Quran.pageCount + 1) ~/ 2 : Quran.pageCount;
      return ModelBuilder(builder: (context) {
        final background = switch (model.theme) {
          PageTheme.classic =>
            Theme.of(context).brightness == Brightness.dark ? AppColors.paperDark : AppColors.paperLight,
          PageTheme.coloured =>
            Theme.of(context).brightness == Brightness.dark ? AppColors.deskDark : AppColors.parchmentDesk,
          PageTheme.night => AppColors.night,
        };
        return Container(
          color: background,
          child: Stack(fit: StackFit.expand, children: [
            Listener(
              onPointerSignal: (e) {
                // Mouse wheel: one notch turns one page (or spread).
                if (e is! PointerScrollEvent || e.scrollDelta.dy.abs() < e.scrollDelta.dx.abs()) return;
                final now = DateTime.now();
                if (now.difference(_lastWheel).inMilliseconds < 350) return;
                _lastWheel = now;
                model.turn(forward: e.scrollDelta.dy > 0);
              },
              child: ScrollConfiguration(
                behavior: const _DragAnywhere(),
                child: Directionality(
                  // Book order: page 1 on the right, later pages slide in from the left.
                  textDirection: TextDirection.ltr,
                  child: PageView.builder(
                    controller: _controller,
                    reverse: true,
                    physics: model.swipeEnabled ? const PageScrollPhysics() : const NeverScrollableScrollPhysics(),
                    itemCount: count,
                    onPageChanged: (i) {
                      final p = _pageAt(i, dual);
                      // Keep the exact page within a spread when it is already showing.
                      if (!dual || _index(model.page, true) != i) model.goTo(p);
                    },
                    itemBuilder: (context, i) => _spread(context, _pageAt(i, dual), dual),
                  ),
                ),
              ),
            ),
            // The original's brightness control: dims the page without touching the app chrome.
            IgnorePointer(child: Container(color: Colors.black.withValues(alpha: (1 - model.brightness) * 0.75))),
          ]),
        );
      });
    });
  }

  Widget _spread(BuildContext context, int first, bool dual) {
    final coloured = model.theme == PageTheme.coloured;
    final side = widget.edgeToEdge ? 4.0 : 12.0;
    final bottom = widget.edgeToEdge ? side : (coloured ? 14.0 : 22.0) + widget.bottomInset;
    final pad = EdgeInsets.fromLTRB(side, side + 2, side, bottom);
    if (!dual) {
      return Padding(padding: pad, child: Center(child: MushafPage(page: first, outerEdgeIsRight: true)));
    }
    final right = first, left = first + 1 <= Quran.pageCount ? first + 1 : null;
    final fold = widget.fold;
    Widget pageBox(int? p, bool rightSide) => p == null
        ? const SizedBox()
        : Align(
            alignment: rightSide ? Alignment.centerLeft : Alignment.centerRight,
            child: MushafPage(page: p, outerEdgeIsRight: rightSide),
          );
    if (fold != null) {
      // Each page on its own half of the hinge.
      final width = MediaQuery.sizeOf(context).width;
      return Padding(
        padding: pad,
        child: Row(children: [
          SizedBox(width: fold.left - pad.left, child: pageBox(left, false)),
          SizedBox(width: fold.width),
          SizedBox(width: width - fold.right - pad.right, child: pageBox(right, true)),
        ]),
      );
    }
    return Padding(
      padding: pad,
      child: Row(children: [
        Expanded(child: pageBox(left, false)),
        if (!coloured)
          Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: Colors.black12)
        else
          const SizedBox(width: 6),
        Expanded(child: pageBox(right, true)),
      ]),
    );
  }
}

/// Lets the mouse drag pages as well as touch, like a swipe.
class _DragAnywhere extends MaterialScrollBehavior {
  const _DragAnywhere();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
