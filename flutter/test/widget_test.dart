// Basic smoke test: the app builds and shows the initial loading state.
import 'package:flutter_test/flutter_test.dart';

import 'package:alextv/main.dart';

void main() {
  testWidgets('AlexTV boots into the loading state', (WidgetTester tester) async {
    await tester.pumpWidget(const AlexTvApp());

    // On the first frame the home screen is still fetching data, so the
    // loading message is shown.
    expect(find.text('Loading…'), findsOneWidget);
  });
}
