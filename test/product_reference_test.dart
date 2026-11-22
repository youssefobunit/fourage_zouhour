import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forage/main.dart';

void main() {
  for (final kind in ProductKind.values) {
    testWidgets('configures the reference for ${kind.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ProductForm(
            kind: kind,
            depots: const [Depot(id: 'general-depot', name: 'Dépôt général')],
            categories: [
              ProductCategory(
                id: 'steel',
                name: 'Acier',
                productIds: const [],
                image: Uint8List(0),
              ),
            ],
          ),
        ),
      );

      final referenceField = find.widgetWithText(TextFormField, 'Référence *');
      if (kind == ProductKind.standard) {
        expect(referenceField, findsNothing);
        await tester.tap(find.text('Famille *'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Sans famille').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Catégorie *'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Acier').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        for (final (label, value) in [
          ('Longueur *', '2'),
          ('Largeur *', '1.5'),
          ('Épaisseur *', '3'),
        ]) {
          await tester.enterText(
            find.widgetWithText(TextFormField, label),
            value,
          );
        }
        await tester.pump();
        expect(find.textContaining('Référence : Acier 2000*1500*3'), findsOne);
        return;
      }

      expect(referenceField, findsOne);
      final form = tester.state<FormState>(find.byType(Form));
      await tester.enterText(referenceField, '   ');
      form.validate();
      await tester.pump();
      expect(
        find.descendant(
          of: referenceField,
          matching: find.text('Champ obligatoire'),
        ),
        findsOne,
      );

      await tester.enterText(referenceField, 'REF-402');
      form.validate();
      await tester.pump();
      expect(
        find.descendant(
          of: referenceField,
          matching: find.text('Champ obligatoire'),
        ),
        findsNothing,
      );
    });
  }
}
