import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forage/main.dart' as forage;
import 'package:forage/security_activity_page.dart';

import 'atelier_glass_test.dart' show testLiquidStage;

void main() {
  testWidgets(
    'sale correction preloads the original sale and removes an attachment by position',
    (tester) async {
      final original = forage.Sale(
        id: 'sale-1',
        productId: 'product',
        depotId: 'depot',
        clientId: 'client',
        pieces: 2,
        quantity: 2,
        unit: forage.InventoryUnit.piece,
        images: [],
        createdAt: DateTime(2026, 11, 28),
      );
      final photos = forage.ValidationDraftPhotos(count: 3, previews: []);
      forage.Sale? corrected;
      await tester.pumpWidget(
        MaterialApp(
          theme: forage.atelierTheme(),
          builder: testLiquidStage,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  corrected = await Navigator.of(context).push<forage.Sale>(
                    MaterialPageRoute(
                      builder: (_) => forage.SaleForm(
                        products: const [
                          forage.Product(
                            id: 'product',
                            name: 'Tôle acier',
                            reference: 'AC-12',
                            width: 1,
                            lengthMeters: 2,
                            lengthUnit: forage.LengthUnit.meter,
                            thickness: 2,
                            kind: forage.ProductKind.standard,
                            initialStock: 100,
                            initialDepotId: 'depot',
                            material: forage.MaterialType.steel,
                          ),
                        ],
                        categories: const [],
                        depots: const [
                          forage.Depot(id: 'depot', name: 'Dépôt principal'),
                        ],
                        clients: const [
                          forage.Client(
                            id: 'client',
                            name: 'Client démo',
                            company: '',
                            phone: '',
                            ice: '',
                            images: [],
                          ),
                        ],
                        available: (_, _) => 100,
                        onAddClient: null,
                        allowGallery: false,
                        initialDraft: original,
                        existingPhotos: photos,
                      ),
                    ),
                  );
                },
                child: const Text('Modifier'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier la vente'), findsOneWidget);
      expect(find.text('Client démo'), findsOneWidget);
      final remove = find.byTooltip('Retirer la photo 2');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(photos.removed, {1});
      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.text('Photo 2'), findsNothing);
      expect(find.text('Photo 3'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      final save = find.text('Enregistrer les modifications');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(corrected?.id, original.id);
      expect(corrected?.createdAt, original.createdAt);
      expect(corrected?.quantity, original.quantity);
      expect(corrected?.draft, isTrue);
    },
  );

  testWidgets(
    'security journal shows old and new values and filters by changed field',
    (tester) async {
      Map<String, dynamic> correction(
        String kind,
        String actor,
        Map<String, dynamic> changes,
      ) => {
        'event': 'validation_edit',
        'actor_id': actor,
        'target': 'op-$kind',
        'occurred_at': '2026-11-28T12:00:00Z',
        'details': {'actor_name': actor, 'kind': kind, 'changes': changes},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: SecurityActivityPage(
            loadEvents: () async => [
              correction('sale', 'Camille', {
                'images': {
                  'before': 10,
                  'after': 9,
                  'removed': [4],
                },
              }),
              correction('purchase', 'Amine', {
                'quantity': {'before': 5, 'after': 4},
              }),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correction de validation · Vente'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Photos retirées : 4'), findsOneWidget);
      expect(find.textContaining('Avant : 10'), findsOneWidget);
      expect(find.textContaining('Après : 9'), findsOneWidget);
      await tester.tap(find.text('Correction de validation · Vente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filtres'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Champ modifié'));
      await tester.pumpAndSettle();
      final photosOption = find.widgetWithText(
        SimpleDialogOption,
        'Photos jointes',
      );
      await tester.ensureVisible(photosOption);
      await tester.pumpAndSettle();
      await tester.tap(photosOption);
      await tester.pumpAndSettle();
      final apply = find.text('Appliquer');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.text('Correction de validation · Vente'), findsOneWidget);
      expect(find.text('Correction de validation · Achat'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
