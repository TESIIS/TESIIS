import 'package:flutter/material.dart';

const _kToggleDuration = Duration(milliseconds: 220);

/// The floating search bar: app title / search field, the search toggle,
/// and (when not searching) the locate-me button.
class SearchToolbar extends StatelessWidget {
  const SearchToolbar({
    super.key,
    required this.controller,
    required this.isSearching,
    required this.isLoadingLocation,
    required this.onToggleSearch,
    required this.onLocate,
    required this.onSearchChanged,
  });

  final TextEditingController controller;
  final bool isSearching;
  final bool isLoadingLocation;
  final VoidCallback onToggleSearch;
  final VoidCallback onLocate;
  final ValueChanged<String> onSearchChanged;

  static Widget _crossFade(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: _kToggleDuration,
              transitionBuilder: _crossFade,
              // AnimatedSwitcher's default layoutBuilder centers its child in
              // a Stack; without this the title text shrinks to its own
              // width and sits in the middle of the toolbar instead of
              // flush left.
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: isSearching
                  ? TextField(
                      key: const ValueKey('search-field'),
                      controller: controller,
                      autofocus: false,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 18,
                      ),
                      decoration: InputDecoration(
                        hintText: '搜尋地點、避難所...',
                        hintStyle: TextStyle(
                          color: colorScheme.primary.withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
                          horizontal: 0,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: colorScheme.primary,
                        ),
                      ),
                      onSubmitted: onSearchChanged,
                      onChanged: onSearchChanged,
                    )
                  : Padding(
                      key: const ValueKey('title'),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      child: Text(
                        'TESIIS 臺灣避難收容所地圖',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
          IconButton(
            tooltip: isSearching ? '關閉搜尋' : '搜尋',
            icon: AnimatedSwitcher(
              duration: _kToggleDuration,
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                isSearching ? Icons.close : Icons.search,
                key: ValueKey(isSearching),
                color: colorScheme.primary,
              ),
            ),
            onPressed: onToggleSearch,
          ),
          // AnimatedAlign + widthFactor collapses the locate button smoothly
          // instead of it popping in/out when search toggles.
          ClipRect(
            child: AnimatedAlign(
              duration: _kToggleDuration,
              curve: Curves.easeOut,
              alignment: Alignment.center,
              widthFactor: isSearching ? 0 : 1,
              child: IconButton(
                tooltip: '定位到我的位置',
                icon: isLoadingLocation
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: colorScheme.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(Icons.my_location, color: colorScheme.primary),
                onPressed: isLoadingLocation ? null : onLocate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
