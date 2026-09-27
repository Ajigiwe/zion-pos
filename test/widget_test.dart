import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_providers.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';
import 'package:instrument_pos/home_shell.dart';

void main() {
  testWidgets(
    'products page shows empty state and opens the new-product form',
    (tester) async {
      // Tall enough that the full product form is visible without scrolling.
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override the DB-backed providers so no SQLite is opened in tests.
            productsProvider.overrideWith(
              (ref, query) => Stream.value(const <ProductWithStock>[]),
            ),
            categoriesProvider.overrideWith(
              (ref) => Stream.value(const <Category>[]),
            ),
            brandsProvider.overrideWith((ref) => Stream.value(const <Brand>[])),
            // Sales is now the landing page, so keep its DB-backed history out
            // of the widget test.
            recentSalesProvider.overrideWith(
              (ref) => Stream.value(const <Sale>[]),
            ),
            lowStockCountProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: const MaterialApp(home: HomeShell()),
        ),
      );
      await tester.pumpAndSettle();

      // Open the Products section and verify the empty state.
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();
      expect(
        find.text('No products yet. Add your first product.'),
        findsOneWidget,
      );

      // The New Product action opens the create form.
      await tester.tap(find.text('New Product'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Product'), findsNothing);
      expect(find.text('New Product'), findsOneWidget);
      expect(find.text('Product name *'), findsOneWidget);
      expect(find.text('Create Product'), findsOneWidget);
    },
  );
}
