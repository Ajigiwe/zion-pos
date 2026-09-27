import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/features/products/presentation/product_edit_page.dart';

void main() {
  testWidgets('new-product form is centered with a max width on wide windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProductEditPage())),
    );
    await tester.pumpAndSettle();

    final constraints = tester
        .widget<ConstrainedBox>(
          find.byWidgetPredicate(
            (w) =>
                w is ConstrainedBox &&
                w.constraints.maxWidth < 1000 &&
                w.constraints.maxWidth > 300,
          ),
        )
        .constraints;
    expect(constraints.maxWidth, 560);

    // The form column itself renders at the constrained width, not the
    // full 1600px window.
    final column = tester.getSize(
      find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 560,
      ),
    );
    expect(column.width, 560);

    expect(find.text('New Product'), findsOneWidget);
    expect(find.text('Product name *'), findsOneWidget);
    expect(find.text('Tracking type'), findsOneWidget);
  });
}
