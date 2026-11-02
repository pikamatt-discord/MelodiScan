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

  Future<List<String>> _render(String musicXml) {
    return (widget.renderer ?? _renderWithVerovio)(musicXml);
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
            ),
          ),
        );
      },
    );
  }
}
