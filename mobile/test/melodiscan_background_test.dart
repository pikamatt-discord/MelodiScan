import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodiscan_mobile/widgets/melodiscan_background.dart';

void main() {
  testWidgets('paints the background across its available area',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MelodiScanBackground(
          child: SizedBox.expand(),
        ),
      ),
    );

    final background = find.byType(CustomPaint).first;
    expect(tester.getSize(background), const Size(360, 800));
    expect(tester.takeException(), isNull);
  });
}
