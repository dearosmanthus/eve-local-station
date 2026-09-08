import 'package:flutter/material.dart';

import '../domain/universe.dart';
import 'theme.dart';

class SystemPicker extends StatefulWidget {
  const SystemPicker({
    required this.title,
    required this.universe,
    this.recentIds = const [],
    super.key,
  });

  final String title;
  final Universe universe;
  final List<int> recentIds;

  @override
  State<SystemPicker> createState() => _SystemPickerState();
}

class _SystemPickerState extends State<SystemPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late List<_SearchEntry> _index;
  late List<_SearchEntry> _matches;
  List<SolarSystem> _recent = const [];
  String _query = '';
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _buildIndex();
    _readRecent();
  }

  @override
  void didUpdateWidget(covariant SystemPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.universe, widget.universe)) _buildIndex();
    _readRecent();
  }

  void _buildIndex() {
    _index = widget.universe.systems.map(_SearchEntry.new).toList()
      ..sort((a, b) {
        final byName = a.sortName.compareTo(b.sortName);
        return byName != 0 ? byName : a.system.id.compareTo(b.system.id);
      });
    _filter();
  }

  void _readRecent() {
    final seen = <int>{};
    final recent = <SolarSystem>[];
    for (final id in widget.recentIds) {
      final system = widget.universe.byId[id];
      if (system == null || !seen.add(id)) continue;
      recent.add(system);
      if (recent.length == 6) break;
    }
    _recent = recent;
  }

  void _filter() {
    if (_query.isEmpty) {
      _matches = _index;
      return;
    }
    final words = _query.split(' ');
    final exact = <_SearchEntry>[];
    final partial = <_SearchEntry>[];
    for (final entry in _index) {
      if (!words.every(entry.aliases.contains)) continue;
      (entry.exactAliases.contains(_query) ? exact : partial).add(entry);
    }
    // Both buckets retain the cached order; keystrokes never sort all systems.
    _matches = [...exact, ...partial];
  }

  void _changeQuery(String text) {
    final normalized =
        text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final hasText = text.isNotEmpty;
    if (normalized == _query && hasText == _hasText) return;
    setState(() {
      _hasText = hasText;
      if (normalized != _query) {
        _query = normalized;
        _filter();
      }
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _choose(SolarSystem system) => Navigator.pop(context, system);

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('system-picker-keyboard-padding'),
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48,
              child: Row(children: [
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Text('${_matches.length} 个',
                    style: const TextStyle(
                        color: StationColors.muted, fontSize: 11)),
                const SizedBox(width: 4),
                SizedBox.square(
                  key: const ValueKey('system-picker-close'),
                  dimension: 44,
                  child: IconButton(
                    tooltip: '关闭星系选择',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ),
              ]),
            ),
            TextField(
              key: const ValueKey('system-picker-search'),
              controller: _search,
              onChanged: _changeQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: '星系、星域、星座中英文或 ID',
                suffixIconConstraints:
                    const BoxConstraints.tightFor(width: 44, height: 44),
                suffixIcon: _hasText
                    ? SizedBox.square(
                        key: const ValueKey('system-picker-clear'),
                        dimension: 44,
                        child: IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            _search.clear();
                            _changeQuery('');
                          },
                          icon: const Icon(Icons.clear, size: 18),
                        ),
                      )
                    : null,
              ),
            ),
            if (_query.isEmpty && _recent.isNotEmpty)
              SizedBox(
                key: const ValueKey('system-picker-recent'),
                height: 52,
                child: Row(children: [
                  const Text('最近',
                      style:
                          TextStyle(color: StationColors.muted, fontSize: 11)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _recent.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final system = _recent[index];
                        return ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxWidth: 170, minHeight: 44),
                          child: OutlinedButton(
                            key: ValueKey('recent-system-${system.id}'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => _choose(system),
                            child: Text(system.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
              )
            else
              const SizedBox(height: 6),
            Expanded(
              child: _matches.isEmpty
                  ? const Center(
                      child: Text('没有匹配的星系',
                          style: TextStyle(color: StationColors.muted)))
                  : ListView.builder(
                      key: const ValueKey('system-picker-list'),
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemExtent: 60,
                      itemCount: _matches.length,
                      itemBuilder: (context, index) {
                        final system = _matches[index].system;
                        final color = system.isHighSecurity
                            ? StationColors.cyan
                            : system.isLowSecurity
                                ? StationColors.amber
                                : StationColors.red;
                        final location = [
                          system.regionDisplayName,
                          if (system.constellationDisplayName.isNotEmpty)
                            system.constellationDisplayName,
                        ].where((name) => name.isNotEmpty).join(' · ');
                        return InkWell(
                          key: ValueKey('system-option-${system.id}'),
                          onTap: () => _choose(system),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: color.withValues(alpha: 0.12),
                              child: Text(
                                  system.displayedSecurity.toStringAsFixed(1),
                                  style: TextStyle(color: color, fontSize: 10)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(system.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14)),
                                  if (location.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(location,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: StationColors.muted,
                                            fontSize: 11)),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 18, color: StationColors.muted),
                          ]),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
}

class _SearchEntry {
  _SearchEntry(this.system)
      : sortName = system.displayName.toLowerCase(),
        aliases = system.searchAliases.join('\n').toLowerCase(),
        exactAliases = {
          system.name.toLowerCase(),
          system.displayName.toLowerCase(),
          '${system.id}',
        };

  final SolarSystem system;
  final String sortName;
  final String aliases;
  final Set<String> exactAliases;
}
