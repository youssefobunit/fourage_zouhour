import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forage/main.dart' as forage;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('transaction attachment controls require the admin action', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 25);
    final opened = <(bool, String?)>[];
    Future<void> openRecords(forage.OpenTransactionPhotos? open) async {
      await tester.pumpWidget(
        MaterialApp(
          home: forage.StockRecordsPage(
            key: ValueKey(open != null),
            products: const [],
            additions: [
              forage.StockAddition(
                id: 42,
                productId: 'bit',
                depotId: 'depot',
                pieces: 3,
                quantity: 3,
                unit: forage.InventoryUnit.piece,
                receiptNumber: 'A-42',
                images: const [],
                addedAt: date,
              ),
            ],
            sales: [
              forage.Sale(
                id: 'sale-42',
                productId: 'bit',
                clientId: 'client',
                depotId: 'depot',
                pieces: 1,
                quantity: 1,
                unit: forage.InventoryUnit.piece,
                images: const [],
                createdAt: date,
              ),
            ],
            transfers: const [],
            depots: const [],
            saleReturns: const [],
            suppliers: const [],
            clients: const [],
            depotName: (id) => id,
            canReturn: false,
            onReturn: (_, _) async => null,
            canReturnPurchase: false,
            onReturnPurchase: (_, _) async => null,
            onOpenAttachments: open,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final attachment = find.byTooltip('Voir les photos jointes');
    await openRecords(null);
    expect(attachment, findsNothing);
    await tester.tap(find.text('Ventes'));
    await tester.pumpAndSettle();
    expect(attachment, findsNothing);

    await openRecords((_, sale, id, _) => opened.add((sale, id)));
    await tester.tap(attachment);
    await tester.tap(find.text('Ventes'));
    await tester.pumpAndSettle();
    await tester.tap(attachment);
    expect(opened, [(false, '42'), (true, 'sale-42')]);
  });

  final category = forage.ProductCategory(
    id: 'drilling',
    name: 'Forage',
    image: Uint8List(0),
    productIds: const ['hammer', 'dth', 'tricone', 'accessory'],
    families: const [
      forage.ProductFamily(id: 'a', name: 'Marteaux', productIds: ['hammer']),
      forage.ProductFamily(id: 'b', name: 'Taillants', productIds: ['dth']),
      forage.ProductFamily(id: 'c', name: 'Tricônes', productIds: ['tricone']),
    ],
  );

  test(
    'persists the product membership in SQLite and the sync snapshot',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final database = forage.AppDatabase(databasePath: inMemoryDatabasePath);
      addTearDown(database.close);
      await database.insertCategory(category);
      final added = catalogItem('new-item', 'TRI-01');
      await database.insertCatalogProduct(added, category.id, 'c');
      await database.saveCatalogFamily(
        forage.CatalogFamily(
          id: 'root',
          name: 'Forage',
          categoryIds: [category.id],
        ),
      );
      await database.saveCatalogFamily(
        forage.CatalogFamily(
          id: 'root-2',
          name: 'Pièces',
          categoryIds: [category.id],
        ),
      );
      await database.insertCategoryInFamily(
        testCategory('new', 'Marteaux', []),
        'root',
      );

      final snapshot = await database.exportSyncSnapshot();
      await database.replaceFromSyncSnapshot(snapshot);
      final workshop = await database.loadWorkshop();
      final stored = workshop.categories.singleWhere(
        (item) => item.id == category.id,
      );
      expect(stored.productIds, contains(added.id));
      expect(stored.families.last.productIds, ['tricone', added.id]);
      expect(
        workshop.catalogFamilies
            .singleWhere((item) => item.id == 'root')
            .categoryIds,
        ['new'],
      );
      expect(
        workshop.catalogFamilies
            .singleWhere((item) => item.id == 'root-2')
            .categoryIds,
        [category.id],
      );
      expect(
        workshop.products.map((product) => product.id),
        contains(added.id),
      );

      snapshot['categories']!
          .singleWhere((item) => item['id'] == category.id)
          .remove('families');
      await database.replaceFromSyncSnapshot(snapshot);
      final restored = (await database.loadWorkshop()).categories.singleWhere(
        (item) => item.id == category.id,
      );
      expect(restored.families, isEmpty);
    },
  );

  testWidgets('shows two categories then opens the requested category', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: forage.CatalogProductBrowser(
              products: [
                catalogItem('hammer', 'HAM-001'),
                catalogItem('dth', 'DTH-115'),
                catalogItem('tricone', 'TRI-17'),
                catalogItem('legacy', 'OLD-001'),
              ],
              categories: [
                testCategory('h', 'Marteaux', ['hammer']),
                testCategory('d', 'Taillants', ['dth']),
                testCategory('t', 'Tricônes', ['tricone']),
              ],
              catalogFamilies: const [
                forage.CatalogFamily(
                  id: 'forage',
                  name: 'Forage',
                  categoryIds: ['h', 'd', 't'],
                ),
              ],
              buildProducts: (items) => Column(
                children: [
                  for (final item in items) Text(item.displayReference),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Marteaux'), findsOne);
    expect(find.text('Taillants'), findsOne);
    expect(find.text('Tricônes'), findsNothing);
    expect(find.text('TRI-17'), findsNothing);
    await tester.tap(find.text('Forage'));
    await tester.pump();
    expect(find.text('Tricônes'), findsOne);
    await tester.tap(find.text('Tricônes'));
    await tester.pump();
    expect(find.text('TRI-17'), findsOne);
    expect(find.text('HAM-001'), findsNothing);
    await tester.tap(find.text('Catégories'));
    await tester.pump();
    await tester.tap(find.text('Familles'));
    await tester.pump();
    await tester.tap(find.text('Sans famille'));
    await tester.pump();
    await tester.tap(find.text('Sans catégorie'));
    await tester.pump();
    expect(find.text('OLD-001'), findsOne);
  });

  testWidgets('changing family clears the selected category', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: forage.ProductForm(
          kind: forage.ProductKind.diameter,
          depots: const [],
          categories: [
            testCategory('a', 'Forets', []),
            testCategory('b', 'Raccords', []),
          ],
          catalogFamilies: const [
            forage.CatalogFamily(id: 'one', name: 'Forage', categoryIds: ['a']),
            forage.CatalogFamily(
              id: 'two',
              name: 'Accessoires',
              categoryIds: ['b'],
            ),
          ],
        ),
      ),
    );

    Future<void> choose(String field, String option) async {
      await tester.tap(
        find.widgetWithText(forage.LiquidSelectFormField<String>, field),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(option).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Catégorie *'), findsNothing);
    await choose('Famille *', 'Forage');
    await choose('Catégorie *', 'Forets');
    expect(find.text('Forets'), findsOne);
    await choose('Famille *', 'Accessoires');
    expect(find.text('Forets'), findsNothing);
    tester.state<FormState>(find.byType(Form)).validate();
    await tester.pump();
    expect(find.text('Choisissez une catégorie.'), findsOne);
    await choose('Catégorie *', 'Raccords');
    expect(find.text('Raccords'), findsOne);
  });

  test('transfer filter matches one depot or both, in either direction', () {
    final item = forage.StockTransfer(
      id: 'transfer',
      productId: 'foret',
      sourceDepotId: 'a',
      destinationDepotId: 'b',
      pieces: 3,
      createdAt: DateTime(2026),
    );
    expect(forage.transferMatchesDepots(item, 'a', null), isTrue);
    expect(forage.transferMatchesDepots(item, 'b', null), isTrue);
    expect(forage.transferMatchesDepots(item, 'b', 'a'), isTrue);
    expect(forage.transferMatchesDepots(item, 'a', 'c'), isFalse);
  });

  testWidgets(
    'Excel applies one period and the selected partners to the exported sheets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<forage.ExcelSheetData>? saved;
      final start = DateTime(2025, 1, 1);
      final end = DateTime(2025, 1, 2, 23, 59);
      final outside = DateTime(2025, 1, 3);
      forage.Sale sold(String client, DateTime date) => forage.Sale(
        id: 'sale-$client-${date.day}',
        productId: 'drill',
        depotId: 'depot',
        clientId: client,
        pieces: 1,
        quantity: 1,
        unit: forage.InventoryUnit.piece,
        images: const [],
        createdAt: date,
      );
      forage.Client buyer(String id, String name) => forage.Client(
        id: id,
        name: name,
        company: '',
        phone: '',
        ice: '',
        images: const [],
      );
      forage.StockAddition purchase(String? supplier, DateTime date) =>
          forage.StockAddition(
            productId: 'drill',
            depotId: 'depot',
            pieces: 1,
            receiptNumber: 'BON-${supplier ?? 'sans-fournisseur'}',
            quantity: 1,
            unit: forage.InventoryUnit.piece,
            images: const [],
            supplierId: supplier,
            addedAt: date,
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: forage.ExcelExportDialog(
              products: [
                catalogItem('drill', 'DRILL'),
                catalogItem('hose', 'HOSE'),
              ],
              categories: [
                testCategory('a', 'Forets', ['drill']),
                testCategory('b', 'Tuyaux', ['hose']),
              ],
              depots: const [],
              stockAdditions: [
                purchase('primary', end),
                purchase('primary', outside),
                purchase('secondary', start),
                purchase(null, start),
              ],
              sales: [
                sold('one', start),
                sold('two', end),
                sold('one', outside),
                sold('three', start),
              ],
              operations: const [],
              transfers: const [],
              returns: const [],
              machines: const [],
              suppliers: const [
                forage.Supplier(
                  id: 'secondary',
                  name: 'Souss',
                  company: '',
                  contact: '',
                  images: [],
                ),
              ],
              clients: [buyer('one', 'Ali'), buyer('three', 'Fatima')],
              productName: (id) => id,
              depotName: (id) => id,
              clientName: (id) => id == 'two' ? 'Atelier Étoile' : id,
              supplierName: (id) => id == 'primary' ? 'Atlas' : id,
              saveSheets: (sheets) async {
                saved = sheets;
              },
            ),
          ),
        ),
      );

      final categoryFilter = find.widgetWithText(
        forage.SearchChoiceField,
        'Catégories',
      );
      final clientFilter = find.widgetWithText(
        forage.SearchChoiceField,
        'Clients',
      );
      final supplierFilter = find.widgetWithText(
        forage.SearchChoiceField,
        'Fournisseurs',
      );
      expect(categoryFilter, findsNothing);
      expect(clientFilter, findsNothing);
      expect(supplierFilter, findsNothing);
      final allDates = find.text('Toutes les dates');
      expect(allDates, findsOneWidget);
      expect(
        tester.getTopLeft(allDates).dy,
        lessThan(tester.getTopLeft(find.text('Produits')).dy),
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Produits'));
      await tester.pumpAndSettle();
      await tester.tap(categoryFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Forets'));
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Achats'));
      await tester.pumpAndSettle();
      await tester.tap(supplierFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Atlas'));
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Ventes'));
      await tester.pumpAndSettle();
      await tester.tap(clientFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Ali'));
      await tester.enterText(find.byType(TextField), 'etoil');
      await tester.pump();
      expect(find.widgetWithText(CheckboxListTile, 'Fatima'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Atelier Étoile'));
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(allDates, findsOneWidget);
      await tester.tap(allDates);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, '01/01/2025');
      await tester.enterText(fields.last, '01/02/2025');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Effacer la période'), findsOneWidget);
      await tester.tap(find.text('Créer le fichier Excel'));
      await tester.pumpAndSettle();

      expect(saved!.map((sheet) => sheet.name), [
        'Produits',
        'Achats',
        'Ventes',
      ]);
      expect(saved!.first.rows.single[0], 'DRILL');
      expect(saved![1].rows.single[7], 'Atlas');
      expect(saved![1].rows.single[0], end);
      expect(saved!.last.rows.map((row) => row[3]), ['one', 'Atelier Étoile']);
      expect(saved!.last.rows.map((row) => row[0]), [start, end]);
    },
  );

  testWidgets(
    'Excel exports products from the selected families and categories',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<forage.ExcelSheetData>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: forage.ExcelExportDialog(
              products: [
                catalogItem('drill', 'DRILL'),
                catalogItem('drill-made', 'DRILL-MADE', parentId: 'drill'),
                catalogItem('hose', 'HOSE'),
                catalogItem('legacy-a', 'OLD-A'),
                catalogItem('legacy-b', 'OLD-B'),
                catalogItem('loose', 'LOOSE'),
              ],
              categories: [
                testCategory('drill', 'Forets', ['drill']),
                testCategory('hose', 'Tuyaux', ['hose']),
                forage.ProductCategory(
                  id: 'old',
                  name: 'Pièces anciennes',
                  image: Uint8List(0),
                  productIds: const ['legacy-a', 'legacy-b'],
                  families: const [
                    forage.ProductFamily(
                      id: 'a',
                      name: 'Série A',
                      productIds: ['legacy-a'],
                    ),
                    forage.ProductFamily(
                      id: 'b',
                      name: 'Série B',
                      productIds: ['legacy-b'],
                    ),
                  ],
                ),
              ],
              catalogFamilies: const [
                forage.CatalogFamily(
                  id: 'forage',
                  name: 'Forage',
                  categoryIds: ['drill'],
                ),
                forage.CatalogFamily(
                  id: 'tubes',
                  name: 'Tuyauterie',
                  categoryIds: ['hose'],
                ),
              ],
              depots: const [],
              stockAdditions: const [],
              sales: const [],
              operations: const [],
              transfers: const [],
              returns: const [],
              machines: const [],
              suppliers: const [],
              clients: const [],
              productName: (id) => id,
              depotName: (id) => id,
              clientName: (id) => id,
              supplierName: (id) => id,
              saveSheets: (sheets) async => saved = sheets,
            ),
          ),
        ),
      );

      final families = find.widgetWithText(
        forage.SearchChoiceField,
        'Familles',
      );
      final categories = find.widgetWithText(
        forage.SearchChoiceField,
        'Catégories',
      );
      Finder choice(String text) => find.widgetWithText(CheckboxListTile, text);
      Future<void> open(Finder field) async {
        await tester.tap(field);
        await tester.pumpAndSettle();
      }

      expect(families, findsNothing);
      await open(choice('Achats'));
      expect(find.text('Aucun fournisseur disponible'), findsOneWidget);
      await open(choice('Achats'));
      await open(choice('Ventes'));
      expect(find.text('Aucun client disponible'), findsOneWidget);
      await open(choice('Ventes'));
      await open(choice('Produits'));
      await open(categories);
      await tester.tap(choice('Tuyaux'));
      await open(find.text('Appliquer'));
      await open(families);
      for (final family in [
        'Forage',
        'Tuyauterie',
        'Série A',
        'Série B',
        'Sans famille',
      ]) {
        expect(choice(family), findsOneWidget);
      }
      await tester.tap(choice('Forage'));
      await tester.tap(choice('Série A'));
      await open(find.text('Appliquer'));
      expect(find.text('Tuyaux'), findsNothing);
      await open(categories);
      expect(choice('Tuyaux'), findsNothing);
      await tester.tap(choice('Forets'));
      await tester.tap(choice('Pièces anciennes'));
      await open(find.text('Appliquer'));
      await open(find.text('Créer le fichier Excel'));

      expect(saved!.single.rows.map((row) => row[0]), [
        'DRILL',
        'DRILL-MADE',
        'OLD-A',
      ]);
    },
  );
}

forage.ProductCategory testCategory(
  String id,
  String name,
  List<String> products,
) => forage.ProductCategory(
  id: id,
  name: name,
  productIds: products,
  image: Uint8List(0),
);

forage.Product catalogItem(String id, String reference, {String? parentId}) =>
    forage.Product(
      id: id,
      name: reference,
      reference: reference,
      width: 0,
      lengthMeters: 0,
      lengthUnit: forage.LengthUnit.meter,
      thickness: 0,
      kind: parentId == null
          ? forage.ProductKind.diameter
          : forage.ProductKind.manufactured,
      parentProductId: parentId,
      initialStock: 0,
      initialDepotId: 'general-depot',
      material: forage.MaterialType.steel,
    );
