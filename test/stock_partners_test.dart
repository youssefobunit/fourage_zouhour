import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forage/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'atelier_glass_test.dart' show testLiquidStage;

const _supplier = Supplier(
  id: 'partner-1',
  name: 'Salma Alaoui',
  company: 'Équipement Atlas',
  contact: '+212 600 000 001',
  fax: '+212 500 000 002',
  ice: '001234567890123',
  images: [],
);

const _legacySupplier = Supplier(
  id: 'partner-2',
  name: 'Salma Alaoui',
  company: 'Autre société',
  contact: 'Contact historique',
  images: [],
);

const _client = Client(
  id: 'partner-1',
  name: 'Omar',
  company: 'Société Safi',
  phone: '+212 600 000 003',
  ice: '001234567890456',
  images: [],
);

void main() {
  test(
    'keeps supplier contact, fax and ICE across a workshop snapshot',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final database = AppDatabase(databasePath: inMemoryDatabasePath);
      addTearDown(database.close);
      await database.insertSupplier(_supplier);
      await database.insertSupplier(_legacySupplier);
      final snapshot = await database.exportSyncSnapshot();
      final supplierRows = snapshot['suppliers']!;
      expect(
        supplierRows.firstWhere(
          (row) => row['id'] == _legacySupplier.id,
        )['contact'],
        _legacySupplier.contact,
      );

      await database.replaceFromSyncSnapshot(snapshot);
      final partners = (await database.loadWorkshop()).suppliers;
      final updated = partners.firstWhere((item) => item.id == _supplier.id);
      final legacy = partners.firstWhere(
        (item) => item.id == _legacySupplier.id,
      );
      expect(
        (updated.contact, updated.fax, updated.ice),
        (_supplier.contact, _supplier.fax, _supplier.ice),
      );
      expect(
        (legacy.contact, legacy.fax, legacy.ice),
        (_legacySupplier.contact, '', ''),
      );
    },
  );

  testWidgets('supplier form supports personal and company details', (
    tester,
  ) async {
    Supplier? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: atelierTheme(),
        builder: testLiquidStage,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<Supplier>(
                  MaterialPageRoute(builder: (_) => const SupplierForm()),
                );
              },
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();

    Finder field(String label) => find.widgetWithText(TextField, label);
    final name = field('Nom');
    final phone = field('N° de téléphone (facultatif)');
    final fax = field('Fax (facultatif)');
    final ice = field('ICE (facultatif)');
    expect(phone, findsNothing);
    expect(fax, findsNothing);
    await tester.enterText(name, 'Salma');
    await tester.pumpAndSettle();
    expect(phone, findsOneWidget);

    await tester.enterText(field('Nom de société'), 'Atlas');
    await tester.enterText(name, '');
    await tester.pumpAndSettle();
    expect(phone, findsNothing);
    await tester.enterText(fax, _supplier.fax);
    await tester.enterText(ice, _supplier.ice);
    final save = find.text('Enregistrer le fournisseur');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      (saved?.name, saved?.company, saved?.fax, saved?.ice),
      ('', 'Atlas', _supplier.fax, _supplier.ice),
    );
  });

  for (final admin in [true, false]) {
    testWidgets(
      'looks up partners and respects transaction photo permissions (admin: $admin)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final user = AppUser(
          id: 'operator',
          username: 'test',
          password: '',
          fullName: 'Test',
          admin: admin,
          role: UserRole.visitor,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: atelierTheme(),
            builder: testLiquidStage,
            home: ForageHome(
              user: user,
              users: [user],
              database: _DirectoryDatabase(),
              onUserAdded: (user) async => user,
              onUserUpdated: (_) async {},
              onLogout: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(MobileGlassNavigation),
            matching: find.text('Stock'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fournisseurs et clients'));
        await tester.pumpAndSettle();

        expect(
          find.byTooltip('Ajouter un fournisseur'),
          admin ? findsOneWidget : findsNothing,
        );
        await tester.enterText(find.byType(TextField), 'equipement atlas');
        await tester.pumpAndSettle();
        expect(find.text(_legacySupplier.company), findsNothing);
        await tester.tap(find.text(_supplier.company));
        await tester.pumpAndSettle();
        expect(find.text(_supplier.fax), findsOneWidget);
        expect(find.text(_supplier.ice), findsOneWidget);
        expect(find.text('Historique des achats (1)'), findsOneWidget);
        expect(find.textContaining('Bon n° A-001'), findsOneWidget);
        expect(
          find.byTooltip('Voir les photos jointes'),
          admin ? findsOneWidget : findsNothing,
        );

        await tester.tap(find.byTooltip('Retour'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clients'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'omar');
        await tester.pumpAndSettle();
        await tester.tap(find.text(_client.name));
        await tester.pumpAndSettle();
        expect(find.text(_client.phone), findsOneWidget);
        expect(find.text('Historique des ventes (1)'), findsOneWidget);
        expect(find.text('Historique des achats (1)'), findsNothing);
        expect(
          find.byTooltip('Voir les photos jointes'),
          admin ? findsOneWidget : findsNothing,
        );
      },
    );
  }
}

class _DirectoryDatabase extends AppDatabase {
  @override
  Future<WorkshopData> loadWorkshop() async => WorkshopData(
    products: const [],
    depots: const [],
    categories: const [],
    catalogFamilies: const [],
    machines: const [],
    operations: const [],
    stockAdditions: [
      for (final (supplierId, receipt) in [
        (_supplier.id, 'A-001'),
        (_legacySupplier.id, 'A-002'),
      ])
        StockAddition(
          productId: 'product',
          depotId: 'depot',
          pieces: 1,
          receiptNumber: receipt,
          quantity: 1,
          unit: InventoryUnit.piece,
          images: const [],
          supplierId: supplierId,
          addedAt: DateTime(2026, 11, 20),
        ),
    ],
    suppliers: [_supplier, _legacySupplier],
    clients: [_client],
    competitors: const [],
    transactionPayments: const [],
    sales: [
      Sale(
        id: 's-1',
        productId: 'product',
        depotId: 'depot',
        clientId: _client.id,
        pieces: 1,
        quantity: 1,
        unit: InventoryUnit.piece,
        images: const [],
        createdAt: DateTime(2026, 11, 20),
      ),
    ],
    stockTransfers: const [],
    saleReturns: const [],
    payments: const [],
    received: const {},
  );

  @override
  Future<double> meterRate() async => 7;

  @override
  Future<void> setAutomaticBackupsEnabled(bool enabled) async {}
}
