import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:verovio_flutter/verovio_flutter.dart';

typedef MusicXmlSvgRenderer = Future<List<String>> Function(String musicXml);

class VerovioScore extends StatefulWidget {
  const VerovioScore({
    required this.musicXml,
    this.renderer,
    super.key,
  });

  final String musicXml;
  final MusicXmlSvgRenderer? renderer;

  @override
  State<VerovioScore> createState() => _VerovioScoreState();
}

class _VerovioScoreState extends State<VerovioScore> {
  late Future<List<String>> _pages;

  @override
  void initState() {
    super.initState();
    _pages = _render(widget.musicXml);
  }

  @override
  void didUpdateWidget(covariant VerovioScore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.musicXml != widget.musicXml ||
        oldWidget.renderer != widget.renderer) {
      _pages = _render(widget.musicXml);
    }
  }

  Future<List<String>> _render(String musicXml) async {
    final pages = await (widget.renderer ?? _renderWithVerovio)(musicXml);
    return pages.map(_normalizeVerovioSvg).toList(growable: false);
  }

  Future<List<String>> _renderWithVerovio(String musicXml) async {
    final resourcePath =
        await VerovioResourceManager.ensureVerovioAssetsReady();
    final service = await VerovioAsyncService.spawn(resourcePath: resourcePath);
    try {
      await service.loadData(musicXml);
      final pageCount = await service.pageCount;
      if (pageCount < 1) {
        throw StateError('Verovio n’a généré aucune page.');
      }

      final pages = <String>[];
      for (var pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
        pages.add(await service.renderToSvg(pageNumber));
      }
      return pages;
    } finally {
      await service.dispose();
    }
  }

  String _normalizeVerovioSvg(String svg) {
    // flutter_svg does not apply SVG stylesheets or nested page viewports.
    final rootMatch = RegExp(r'<svg\b[^>]*>').firstMatch(svg);
    if (rootMatch == null) return svg;

    final nestedMatches = RegExp(
      r'<svg\b(?=[^>]*\bclass="definition-scale")[^>]*>',
    ).allMatches(svg).where((match) => match.start >= rootMatch.end);
    if (nestedMatches.isEmpty) return svg;
    final nestedMatch = nestedMatches.first;

    final nestedTag = nestedMatch.group(0)!;
    final viewBoxMatch = RegExp(r'\bviewBox="([^"]+)"').firstMatch(nestedTag);
    if (viewBoxMatch == null) return svg;

    final flattenedGroup = nestedTag
        .replaceFirst(RegExp(r'^<svg\b'), '<g')
        .replaceFirst(viewBoxMatch.group(0)!, '');
    var normalized = svg.replaceRange(
      nestedMatch.start,
      nestedMatch.end,
      flattenedGroup,
    );

    final rootClosingTag = normalized.lastIndexOf('</svg>');
    if (rootClosingTag < 0) return svg;
    final nestedClosingTag =
        normalized.lastIndexOf('</svg>', rootClosingTag - 1);
    if (nestedClosingTag <= nestedMatch.start) return svg;
    normalized = normalized.replaceRange(
      nestedClosingTag,
      nestedClosingTag + '</svg>'.length,
      '</g>',
    );

    final rootTag = rootMatch.group(0)!;
    if (!RegExp(r'\bviewBox=').hasMatch(rootTag)) {
      final rootWithViewBox =
          rootTag.replaceFirst('>', ' viewBox="${viewBoxMatch[1]}">');
      normalized = normalized.replaceRange(
        rootMatch.start,
        rootMatch.end,
        rootWithViewBox,
      );
    }

    normalized = normalized.replaceAll(
      RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
      '',
    );
    return normalized.replaceAllMapped(
      RegExp(r'<(path|ellipse|polygon|polyline|rect)\b([^>]*)>'),
      (match) {
        final name = match[1]!;
        final attributes = match[2]!;
        if (RegExp(r'\bstroke\s*=').hasMatch(attributes)) {
          return match[0]!;
        }

        final trimmedAttributes = attributes.trimRight();
        final selfClosing = trimmedAttributes.endsWith('/');
        final cleanAttributes = selfClosing
            ? trimmedAttributes.substring(0, trimmedAttributes.length - 1)
            : attributes;
        return '<$name$cleanAttributes stroke="currentColor"'
            '${selfClosing ? ' />' : '>'}';
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      key: const Key('traditional_score_view'),
      future: _pages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Impossible de rendre la partition : ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          );
        }
        final pages = snapshot.data;
        if (pages == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return ColoredBox(
          color: const Color(0xFFFFFEFA),
          child: ListView.separated(
            itemCount: pages.length,
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => SvgPicture.string(
              pages[index],
              fit: BoxFit.contain,
              semanticsLabel: 'Partition, page ${index + 1}',
              placeholderBuilder: (_) => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorBuilder: (context, error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Impossible d’afficher la partition : $error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
