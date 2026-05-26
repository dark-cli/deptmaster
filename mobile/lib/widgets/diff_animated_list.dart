import 'package:flutter/material.dart';

typedef ItemId<T> = String Function(T item);
typedef AnimatedItemBuilder<T> = Widget Function(BuildContext context, T item, Animation<double> animation);

/// A small helper around `AnimatedList` that applies insert/remove animations
/// when the `items` list changes (based on stable item ids).
///
/// Notes:
/// - Insertions/removals animate.
/// - Reorders can be disabled to avoid moves.
class DiffAnimatedList<T> extends StatefulWidget {
  final List<T> items;
  final ItemId<T> itemId;
  final AnimatedItemBuilder<T> itemBuilder;
  final Duration duration;
  final EdgeInsetsGeometry? padding;
  final bool animateReorder;

  const DiffAnimatedList({
    super.key,
    required this.items,
    required this.itemId,
    required this.itemBuilder,
    this.duration = const Duration(milliseconds: 800),
    this.padding,
    this.animateReorder = false,
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

    final currentIds = _items.map(widget.itemId).toList(growable: false);
    final currentSet = currentIds.toSet();
    final newIds = widget.items.map(widget.itemId).toList(growable: false);
    final newSet = newIds.toSet();

    final sameOrder = currentIds.length == newIds.length && _listEquals(currentIds, newIds);
    final sameSet = currentSet.length == newSet.length && currentSet.containsAll(newSet);

    if (sameOrder) {
      bool contentChanged = false;
      for (var i = 0; i < widget.items.length; i++) {
        if (_items[i] != widget.items[i]) {
          _items[i] = widget.items[i];
          contentChanged = true;
        }
      }
      if (contentChanged) {
        setState(() {});
      }
      return;
    }

    if (sameSet && !widget.animateReorder) {
      setState(() {
        _items = List<T>.from(widget.items);
      });
      return;
    }

    // Naive diff algorithm that handles moves by Remove+Insert
    // This allows animations to play for reordering
    
    final newIdSet = newSet;

    // 1. Removals
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

    // 2. Insertions and Moves
    // We iterate through the NEW list and ensure _items matches it by inserting/moving
    for (var i = 0; i < widget.items.length; i++) {
      final newItem = widget.items[i];
      final newId = widget.itemId(newItem);
      
      if (i >= _items.length) {
        // Append new item
        _items.insert(i, newItem);
        _listKey.currentState?.insertItem(i, duration: widget.duration);
      } else {
        final currentItem = _items[i];
        final currentId = widget.itemId(currentItem);
        
        if (currentId != newId) {
          // Mismatch!
          // Check if the current item at i is supposed to be later in the new list?
          // Or if the new item at i is somewhere else in _items?
          
          final existingIndex = _items.indexWhere((item) => widget.itemId(item) == newId, i + 1);
          
          if (existingIndex != -1) {
            if (widget.animateReorder) {
              // "Move" detected: The item we want (newItem) exists later in _items.
              // We simulate a move by removing it from the old position and inserting it here.
              final movedItem = _items.removeAt(existingIndex);
              _listKey.currentState?.removeItem(
                existingIndex,
                (context, animation) => widget.itemBuilder(context, movedItem, animation),
                duration: widget.duration,
              );
              
              _items.insert(i, newItem);
              _listKey.currentState?.insertItem(i, duration: widget.duration);
            }
          } else {
            // New Item (Insert)
            _items.insert(i, newItem);
            _listKey.currentState?.insertItem(i, duration: widget.duration);
          }
        } else {
          // ID match: Update item data if changed (for text glitch)
          if (_items[i] != newItem) {
            _items[i] = newItem;
            // Force rebuild of visible items to reflect data change
            // (AnimatedList doesn't automatically rebuild existing items on state change unless setState called)
          }
        }
      }
    }
    
    // Cleanup: Remove any trailing items that shouldn't be there (should be caught by step 1, but safety)
    while (_items.length > widget.items.length) {
      final index = _items.length - 1;
      final removed = _items.removeAt(index);
      _listKey.currentState?.removeItem(
        index,
        (context, animation) => widget.itemBuilder(context, removed, animation),
        duration: widget.duration,
      );
    }

    if (!widget.animateReorder) {
      setState(() {
        _items = List<T>.from(widget.items);
      });
      return;
    }

    // Force rebuild to show updated data for existing items
    setState(() {});
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
