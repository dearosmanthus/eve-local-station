import 'catalogue.dart';

/// A candidate-specific view of the official static market category tree.
/// This provides navigation only; it never requests prices or market orders.
class CatalogueBrowser {
  CatalogueBrowser(this.catalogue, Iterable<EveType> candidates)
      : candidates = List.unmodifiable({
          for (final type in candidates) type.id: type,
        }.values) {
    final ungrouped = <EveType>[];
    for (final type in this.candidates) {
      final path = type.marketGroupId == null
          ? const <MarketGroup>[]
          : pathTo(type.marketGroupId!);
      if (path.isEmpty) {
        ungrouped.add(type);
        continue;
      }
      for (final group in path) {
        _typesByGroup.putIfAbsent(group.id, () => []).add(type);
      }
      _directTypes.putIfAbsent(path.last.id, () => []).add(type);
    }
    ungroupedTypes = List.unmodifiable(ungrouped);
    for (final id in _typesByGroup.keys) {
      final group = catalogue.marketGroups[id]!;
      _children.putIfAbsent(group.parentId, () => []).add(group);
    }
    for (final children in _children.values) {
      children.sort((a, b) {
        final byName = a.displayName.compareTo(b.displayName);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    }
  }

  final Catalogue catalogue;
  final List<EveType> candidates;
  late final List<EveType> ungroupedTypes;
  final Map<int, List<MarketGroup>> _paths = {};
  final Map<int?, List<MarketGroup>> _children = {};
  final Map<int, List<EveType>> _typesByGroup = {};
  final Map<int, List<EveType>> _directTypes = {};

  List<MarketGroup> get rootGroups => childrenOf(null);

  /// Only direct child categories containing at least one supplied candidate.
  List<MarketGroup> childrenOf(int? parentId) =>
      List.unmodifiable(_children[parentId] ?? const <MarketGroup>[]);

  /// Full root-to-leaf path. Missing parents or cycles yield an empty path;
  /// affected candidates stay available through [ungroupedTypes].
  List<MarketGroup> pathTo(int groupId) => _paths.putIfAbsent(groupId, () {
        final reverse = <MarketGroup>[];
        final visited = <int>{};
        int? current = groupId;
        while (current != null) {
          if (!visited.add(current)) return const <MarketGroup>[];
          final group = catalogue.marketGroups[current];
          if (group == null) return const <MarketGroup>[];
          reverse.add(group);
          current = group.parentId;
        }
        return List.unmodifiable(reverse.reversed);
      });

  /// Null means all candidates, including unclassified types. false includes
  /// only types assigned directly to this category, not its descendants.
  List<EveType> typesIn(int? groupId, {bool includeDescendants = true}) =>
      groupId == null
          ? candidates
          : List.unmodifiable(
              (includeDescendants ? _typesByGroup : _directTypes)[groupId] ??
                  const <EveType>[]);

  int countIn(int? groupId) =>
      groupId == null ? candidates.length : _typesByGroup[groupId]?.length ?? 0;
}
