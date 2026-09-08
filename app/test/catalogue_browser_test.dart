import 'dart:io';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/catalogue_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Catalogue catalogue;
  setUpAll(() {
    catalogue = Catalogue.decode(
      File('assets/data/catalogue.json').readAsStringSync(),
    );
  });

  test(
      'official ship classes and faction paths contain only candidate branches',
      () {
    final rifter = catalogue.byId[587]!;
    final caracal = catalogue.byId[621]!;
    final browser = CatalogueBrowser(catalogue, [rifter, caracal]);
    expect(rifter.marketGroupId, 64);
    expect(browser.rootGroups.map((group) => group.id), [4]);
    expect(
        browser.childrenOf(4).map((group) => group.id).toSet(), {1361, 1367});
    expect(browser.pathTo(64).map((group) => group.displayName),
        ['舰船', '护卫舰', '标准护卫舰', '米玛塔尔']);
    expect(browser.pathTo(64).map((group) => group.name),
        ['Ships', 'Frigates', 'Standard Frigates', 'Minmatar']);
    expect(browser.typesIn(1361).map((type) => type.id), [587]);
    expect(browser.typesIn(4, includeDescendants: false), isEmpty);
    expect(browser.typesIn(64, includeDescendants: false).single.id, 587);
    expect(browser.countIn(4), 2);
    expect(browser.countIn(1361), 1);
    expect(browser.childrenOf(9), isEmpty); // unrelated equipment pruned
  });

  test(
      'official weapon family and size are preserved after candidate filtering',
      () {
    final gun = catalogue.byId[2889]!;
    final browser = CatalogueBrowser(catalogue, [gun]);
    expect(browser.pathTo(gun.marketGroupId!).map((group) => group.displayName),
        ['舰船装备', '炮台和发射器', '射弹炮台', '自动加农炮', '小型']);
    expect(browser.childrenOf(10).map((group) => group.id), [87]);
    expect(browser.countIn(10), 1);
    expect(browser.typesIn(null).single.id, 2889);
  });

  test('real unclassified types remain accessible and counts are deduplicated',
      () {
    final missing =
        catalogue.byId.values.firstWhere((type) => type.marketGroupId == null);
    final rifter = catalogue.byId[587]!;
    final browser = CatalogueBrowser(catalogue, [missing, rifter, rifter]);
    expect(browser.ungroupedTypes.single.id, missing.id);
    expect(browser.countIn(null), 2);
    expect(browser.countIn(4), 1);
    expect(browser.typesIn(null).map((type) => type.id), [missing.id, 587]);
  });

  test(
      'cycles, missing parents and old catalogues terminate without losing types',
      () {
    // Synthetic category graph deliberately malformed; not game data.
    EveType type(int id, int group) => EveType(
          id: id,
          name: 'Synthetic $id',
          kind: 'ship',
          data: {'market_group_id': group},
        );
    final candidates = [type(9001, 1), type(9002, 3), type(9003, 99)];
    final synthetic = Catalogue(
      ships: candidates,
      modules: [],
      drones: [],
      charges: [],
      marketGroups: const {
        1: MarketGroup(id: 1, parentId: 2, name: 'Cycle A'),
        2: MarketGroup(id: 2, parentId: 1, name: 'Cycle B'),
        3: MarketGroup(id: 3, parentId: 88, name: 'Orphan'),
      },
    );
    final browser = CatalogueBrowser(synthetic, candidates);
    expect(browser.pathTo(1), isEmpty);
    expect(browser.pathTo(3), isEmpty);
    expect(browser.rootGroups, isEmpty);
    expect(browser.ungroupedTypes.map((type) => type.id), [9001, 9002, 9003]);
    expect(browser.typesIn(null), hasLength(3));
    final old = Catalogue(
      ships: candidates,
      modules: [],
      drones: [],
      charges: [],
    );
    expect(CatalogueBrowser(old, candidates).ungroupedTypes, hasLength(3));
  });
}
