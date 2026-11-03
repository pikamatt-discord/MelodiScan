import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodiscan_mobile/widgets/verovio_score.dart';

void main() {
  testWidgets('renders SVG structure produced by Verovio', (tester) async {
    const verovioSvg = '''
<svg width="2100px" height="2970px" version="1.1"
  xmlns="http://www.w3.org/2000/svg"
  xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs>
    <g id="notehead"><path d="M0 0 L10 0 L10 10 Z" /></g>
  </defs>
  <style type="text/css">svg path { stroke: currentColor }</style>
  <svg class="definition-scale" color="black" font-family="Times, serif"
    viewBox="0 0 21000 29700">
    <g class="page-margin" transform="translate(500, 500)">
      <use xlink:href="#notehead" transform="translate(1000, 1000)" />
    </g>
  </svg>
</svg>
''';
    await tester.pumpWidget(
      MaterialApp(
        home: VerovioScore(
          musicXml: 'diagnostic',
          renderer: (_) async => [verovioSvg],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('shows SVG decoding errors instead of a blank page',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VerovioScore(
          musicXml: '<score-partwise/>',
          renderer: (_) async => ['<invalid/>'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Impossible d’afficher la partition'),
        findsOneWidget);
  });
}
