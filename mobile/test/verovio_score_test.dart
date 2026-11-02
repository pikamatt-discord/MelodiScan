import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodiscan_mobile/widgets/verovio_score.dart';

void main() {
  testWidgets('renders Verovio SVG pages from MusicXML', (tester) async {
    var receivedMusicXml = '';
    await tester.pumpWidget(
      MaterialApp(
        home: VerovioScore(
          musicXml: '<score-partwise/>',
          renderer: (musicXml) async {
            receivedMusicXml = musicXml;
            return [
              '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
                  '<path d="M 0 0 L 10 10"/>'
                  '</svg>',
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(receivedMusicXml, '<score-partwise/>');
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('shows Verovio rendering errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VerovioScore(
          musicXml: '<invalid/>',
          renderer: (_) async => throw StateError('invalid score'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('invalid score'), findsOneWidget);
  });
}
