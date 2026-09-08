import 'package:flutter/material.dart';

import '../domain/catalogue.dart';
import '../domain/catalogue_browser.dart';
import 'theme.dart';

Future<EveType?> pickType(
  BuildContext context, {
  required String title,
  required List<EveType> types,
  Catalogue? catalogue,
  String? hint,
  String? Function(EveType)? incompatibility,
}) =>
    showModalBottomSheet<EveType>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: StationColors.panel,
      showDragHandle: false,
      builder: (context) => FractionallySizedBox(
          heightFactor: 0.96,
          child: TypePicker(
              title: title,
              types: types,
              catalogue: catalogue,
              hint: hint,
              incompatibility: incompatibility)),
    );

class TypePicker extends StatefulWidget {
  const TypePicker(
      {required this.title,
      required this.types,
      this.catalogue,
      this.hint,
      this.incompatibility,
      super.key});
  final String title;
  final List<EveType> types;
  final Catalogue? catalogue;
  final String? hint;
  final String? Function(EveType)? incompatibility;
  @override
  State<TypePicker> createState() => _TypePickerState();
}

class _TypePickerState extends State<TypePicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  bool _compatibleOnly = true;
  bool _listMode = false;
  bool _ungrouped = false;
  bool _manualNavigation = false;
  int? _groupId;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int? group, {bool ungrouped = false}) {
    setState(() {
      _groupId = group;
      _ungrouped = ungrouped;
      _manualNavigation = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
    FocusScope.of(context).unfocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  int? _baseGroup(CatalogueBrowser browser) {
    int? parent;
    final seen = <int>{};
    if (browser.ungroupedTypes.isNotEmpty) return null;
    while (true) {
      final children = browser.childrenOf(parent);
      if (children.length != 1 || !seen.add(children.single.id)) return parent;
      if (parent != null &&
          browser.typesIn(parent, includeDescendants: false).isNotEmpty) {
        return parent;
      }
      parent = children.single.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.types
        .where((type) =>
            !_compatibleOnly || widget.incompatibility?.call(type) == null)
        .toList();
    final catalogue = widget.catalogue;
    final browser = catalogue == null || catalogue.marketGroups.isEmpty
        ? null
        : CatalogueBrowser(catalogue, candidates);
    final searching = _query.trim().isNotEmpty;
    final base = browser == null ? null : _baseGroup(browser);
    final current = _manualNavigation ? _groupId : base;
    final path = current == null || browser == null
        ? <MarketGroup>[]
        : browser.pathTo(current);
    final canGoBack = _ungrouped || (_manualNavigation && current != null);
    void back() {
      if (_ungrouped || path.length < 2) {
        _move(null);
      } else {
        _move(path[path.length - 2].id);
      }
    }

    final browse = browser != null && !_listMode && !searching;
    final groups =
        browse && !_ungrouped ? browser.childrenOf(current) : <MarketGroup>[];
    final List<EveType> items;
    if (searching) {
      items = candidates.where((type) => type.matchesQuery(_query)).toList();
    } else if (!browse) {
      items = candidates.toList();
    } else if (_ungrouped) {
      items = browser.ungroupedTypes.toList();
    } else {
      items = current == null
          ? <EveType>[]
          : browser.typesIn(current, includeDescendants: false).toList();
    }
    items.sort((a, b) => a.displayName.compareTo(b.displayName));
    final showUngrouped = browse &&
        !_ungrouped &&
        current == null &&
        browser.ungroupedTypes.isNotEmpty;
    final count = searching || _listMode || browser == null
        ? items.length
        : _ungrouped
            ? items.length
            : browser.countIn(current);
    final rowCount = groups.length + items.length + (showUngrouped ? 1 : 0);
    return PopScope(
      canPop: !searching && (!browse || !canGoBack),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (searching) {
          _clearSearch();
        } else {
          back();
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            12, 0, 12, MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              height: 48,
              child: Row(children: [
                if (browse && canGoBack)
                  IconButton(
                      tooltip: '返回上级分类',
                      onPressed: back,
                      icon: const Icon(Icons.arrow_back, size: 20)),
                Expanded(
                    child: Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600))),
                Text('$count 项', style: Theme.of(context).textTheme.bodySmall),
                if (widget.hint != null)
                  IconButton(
                      tooltip: widget.hint,
                      icon: const Icon(Icons.info_outline, size: 18),
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                                  title: const Text('选择提示'),
                                  content: Text(widget.hint!),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('知道了')),
                                  ]))),
                IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20)),
              ])),
          TextField(
            controller: _search,
            onChanged: (value) {
              setState(() => _query = value);
              if (_scroll.hasClients) _scroll.jumpTo(0);
            },
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: '搜索全部分类 · 中文 / 英文 / ID',
                hintStyle: const TextStyle(fontSize: 12),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: '清空搜索',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close, size: 18))
                    : null),
          ),
          if (widget.incompatibility != null)
            SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('仅显示兼容物品', style: TextStyle(fontSize: 12)),
                value: _compatibleOnly,
                onChanged: (value) {
                  setState(() {
                    _compatibleOnly = value;
                    _groupId = null;
                    _ungrouped = false;
                    _manualNavigation = false;
                  });
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                }),
          if (browser != null && !searching)
            SizedBox(
                height: 44,
                child: Row(children: [
                  for (final entry in {false: '分类浏览', true: '全部物品'}.entries)
                    Expanded(
                        child: TextButton(
                      key: ValueKey(
                          'picker-mode-${entry.key ? 'list' : 'categories'}'),
                      style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          foregroundColor: _listMode == entry.key
                              ? StationColors.cyan
                              : StationColors.muted,
                          backgroundColor: _listMode == entry.key
                              ? StationColors.elevated
                              : null,
                          shape: const RoundedRectangleBorder()),
                      onPressed: () {
                        setState(() => _listMode = entry.key);
                        if (_scroll.hasClients) _scroll.jumpTo(0);
                      },
                      child: Text(entry.value,
                          style: const TextStyle(fontSize: 12)),
                    )),
                ])),
          if (browse)
            SizedBox(
                height: 44,
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(children: [
                      TextButton(
                          onPressed: () => _move(null),
                          child: const Text('全部分类',
                              style: TextStyle(fontSize: 11))),
                      for (final group in path) ...[
                        const Icon(Icons.chevron_right,
                            size: 14, color: StationColors.muted),
                        TextButton(
                            onPressed: () => _move(group.id),
                            child: Text(group.displayName,
                                style: const TextStyle(fontSize: 11))),
                      ],
                      if (_ungrouped)
                        const Text('› 未分类', style: TextStyle(fontSize: 11)),
                    ]))),
          if (searching)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('全部分类搜索 · ${items.length} 项结果',
                    style: Theme.of(context).textTheme.bodySmall)),
          const Divider(),
          Expanded(
              child: rowCount == 0
                  ? Center(
                      child: Text(searching ? '没有匹配的本地物品' : '此分类没有符合条件的物品'))
                  : ListView.separated(
                      key: const ValueKey('picker-results'),
                      controller: _scroll,
                      itemCount: rowCount,
                      separatorBuilder: (_, index) => const Divider(),
                      itemBuilder: (context, index) {
                        if (index < groups.length) {
                          final group = groups[index];
                          return _categoryRow(
                              group.displayName, browser!.countIn(group.id),
                              key: ValueKey('picker-group-${group.id}'),
                              onTap: () => _move(group.id));
                        }
                        if (showUngrouped && index == groups.length) {
                          return _categoryRow(
                              '未分类', browser.ungroupedTypes.length,
                              key: const ValueKey('picker-ungrouped'),
                              onTap: () => _move(null, ungrouped: true));
                        }
                        return _itemRow(items[
                            index - groups.length - (showUngrouped ? 1 : 0)]);
                      })),
        ]),
      ),
    );
  }

  Widget _categoryRow(String title, int count,
          {required Key key, required VoidCallback onTap}) =>
      ListTile(
        key: key,
        dense: true,
        minVerticalPadding: 10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: const Icon(Icons.folder_outlined,
            color: StationColors.cyan, size: 22),
        title: Text(title, maxLines: 2, style: const TextStyle(fontSize: 14)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$count',
              style: const TextStyle(fontSize: 11, color: StationColors.muted)),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 18),
        ]),
        onTap: onTap,
      );

  Widget _itemRow(EveType type) {
    final reason = widget.incompatibility?.call(type);
    return ListTile(
      key: ValueKey('picker-type-${type.id}'),
      dense: true,
      minVerticalPadding: 6,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
          type.kind == 'ship'
              ? Icons.navigation_outlined
              : type.kind == 'drone'
                  ? Icons.grain
                  : Icons.memory_outlined,
          color: StationColors.cyan,
          size: 22),
      title: Tooltip(
          message: '${type.displayName}\n${type.name}',
          child: Text(type.displayName,
              maxLines: 2, style: const TextStyle(fontSize: 13))),
      subtitle: Text(
          reason ??
              (type.group.isEmpty ? '物品 ${type.id}' : type.groupDisplayName),
          style: TextStyle(
              fontSize: 11,
              color:
                  reason == null ? StationColors.muted : StationColors.amber)),
      trailing: Icon(
          reason == null
              ? Icons.add_circle_outline
              : Icons.warning_amber_rounded,
          size: 20,
          color: reason == null ? StationColors.cyan : StationColors.amber),
      onTap: () => Navigator.pop(context, type),
    );
  }
}
