import 'package:flutter/material.dart';

typedef ItemId<T> = String Function(T item);
typedef AnimatedItemBuilder<T> = Widget Function(BuildContext context, T item, Animation<double> animation);

/// A small helper around `AnimatedList` that applies insert/remove animations
/// when the `items` list changes (based on stable item ids).
///
/// Notes:
/// - Insertions/removals animate.
/// - Reorders fall back to a non-animated reset (keeps correctness; avoids complex move logic).
class DiffAnimatedList<T> extends StatefulWidget {
  final List<T> items;
  final ItemId<T> itemId;
  final AnimatedItemBuilder<T> itemBuilder;
  final Duration duration;
  final EdgeInsetsGeometry? padding;

  const DiffAnimatedList({
    super.key,
    required this.items,
    required this.itemId,
    required this.itemBuilder,
    this.duration = const Duration(milliseconds: 250),
    this.padding,
  });

  @override
  State<DiffAnimatedList<T>> createState() => _DiffAnimatedListState<T>();
}

class _DiffAnimatedListState<T> extends State<DiffAnimatedList<T>> {
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<T> _items;

  @override
  void initState() {
    super.initState();
    _items = List<T>.from(widget.items);
  }

  @override
  void didUpdateWidget(covariant DiffAnimatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldIds = oldWidget.items.map(widget.itemId).toList(growable: false);
    final newIds = widget.items.map(widget.itemId).toList(growable: false);

    final oldSet = oldIds.toSet();
    final newSet = newIds.toSet();

    final sameSet = oldSet.length == newSet.length && oldSet.containsAll(newSet);
    final sameOrder = oldIds.length == newIds.length && _listEquals(oldIds, newIds);
    final reorderOnly = sameSet && !sameOrder;

    if (reorderOnly) {
      // Reset without animation to keep logic simple.
      setState(() {
        _items = List<T>.from(widget.items);
        _listKey = GlobalKey<AnimatedListState>();
      });
      return;
    }

    final newIdSet = newSet;

    // Removals (walk backwards to keep indices valid)
    for (var i = _items.length - 1; i >= 0; i--) {
      final id = widget.itemId(_items[i]);
      if (!newIdSet.contains(id)) {
        final removed = _items.removeAt(i);
        _listKey.currentState?.removeItem(
          i,
          (context, animation) => widget.itemBuilder(context, removed, animation),
          duration: widget.duration,
        );
      }
    }

    final oldIdSetAfterRemovals = _items.map(widget.itemId).toSet();

    // Insertions + updates (iterate new list order)
    for (var i = 0; i < widget.items.length; i++) {
      final nextItem = widget.items[i];
      final id = widget.itemId(nextItem);

      if (!oldIdSetAfterRemovals.contains(id)) {
        _items.insert(i, nextItem);
        _listKey.currentState?.insertItem(i, duration: widget.duration);
      } else {
        // Update in place if id exists at the same index.
        if (i < _items.length && widget.itemId(_items[i]) == id) {
          _items[i] = nextItem;
        }
      }
    }

    // Final fallback: if lengths mismatch due to complex changes, hard reset.
    if (_items.length != widget.items.length) {
      setState(() {
        _items = List<T>.from(widget.items);
        _listKey = GlobalKey<AnimatedListState>();
      });
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      padding: widget.padding,
      itemBuilder: (context, index, animation) {
        final item = _items[index];
        return widget.itemBuilder(context, item, animation);
      },
    );
  }
}

