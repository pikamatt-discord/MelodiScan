import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/musicxml_score.dart';

class TraditionalScore extends StatefulWidget {
  const TraditionalScore({
    required this.score,
    required this.currentTick,
    super.key,
  });

  final MusicXmlScore score;
  final int currentTick;

  @override
  State<TraditionalScore> createState() => _TraditionalScoreState();
}

class _TraditionalScoreState extends State<TraditionalScore> {
  static const _systemHeight = 176.0;
  final _scrollController = ScrollController();
  int _lastScrolledSystem = 0;

  int _measureIndexAtTick() {
    for (var index = 0; index < widget.score.measures.length; index++) {
      if (widget.currentTick < widget.score.measures[index].endTick) {
        return index;
      }
    }
    return widget.score.measures.length - 1;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measuresPerSystem =
            math.max(1, ((constraints.maxWidth - 68) / 190).floor());
        final systemIndex = _measureIndexAtTick() ~/ measuresPerSystem;
        if (systemIndex != _lastScrolledSystem) {
          _lastScrolledSystem = systemIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollController.hasClients) return;
            final offset = systemIndex * _systemHeight;
            _scrollController.animateTo(
              offset.clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          });
        }

        final systemCount =
            (widget.score.measures.length / measuresPerSystem).ceil();
        return ColoredBox(
          key: const Key('traditional_score_view'),
          color: const Color(0xFFFFFEFA),
          child: ListView.builder(
            controller: _scrollController,
            itemExtent: _systemHeight,
            itemCount: systemCount,
            itemBuilder: (context, systemIndex) {
              final start = systemIndex * measuresPerSystem;
              final end = math.min(
                start + measuresPerSystem,
                widget.score.measures.length,
              );
              return CustomPaint(
                painter: _ScoreSystemPainter(
                  measures: widget.score.measures.sublist(start, end),
                  firstMeasureIndex: start,
                  currentTick: widget.currentTick,
                  textDirection: Directionality.of(context),
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        );
      },
    );
  }
}

class _ScoreSystemPainter extends CustomPainter {
  _ScoreSystemPainter({
    required this.measures,
    required this.firstMeasureIndex,
    required this.currentTick,
    required this.textDirection,
  });

  final List<ScoreMeasure> measures;
  final int firstMeasureIndex;
  final int currentTick;
  final TextDirection textDirection;

  static const _left = 10.0;
  static const _right = 10.0;
  static const _staffTop = 48.0;
  static const _lineGap = 11.0;
  static const _bottomLine = _staffTop + 4 * _lineGap;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xFF171717)
      ..strokeWidth = 1.15;
    final staffWidth = size.width - _left - _right;
    final measureWidth = staffWidth / measures.length;

    for (var line = 0; line < 5; line++) {
      final y = _staffTop + line * _lineGap;
      canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), ink);
    }

    for (var index = 0; index < measures.length; index++) {
      final measure = measures[index];
      final measureLeft = _left + index * measureWidth;
      final measureRight = measureLeft + measureWidth;
      final isFirst = firstMeasureIndex + index == 0;
      final isActive =
          currentTick >= measure.startTick && currentTick < measure.endTick;
      if (isActive) {
        final highlight = Paint()
          ..color = const Color(0xFFFFD54F).withValues(alpha: 0.18);
        canvas.drawRect(
          Rect.fromLTRB(
            measureLeft,
            _staffTop - 15,
            measureRight,
            _bottomLine + 16,
          ),
          highlight,
        );
      }

      if (index > 0) {
        canvas.drawLine(
          Offset(measureLeft, _staffTop),
          Offset(measureLeft, _bottomLine),
          ink,
        );
      }

      _drawText(
        canvas,
        measure.number,
        Offset(measureLeft + 2, 8),
        10,
        const Color(0xFF555555),
      );

      final previousMeasure = index > 0 ? measures[index - 1] : null;
      final clefChanged =
          previousMeasure != null && previousMeasure.clef != measure.clef;
      final keyChanged =
          previousMeasure != null && previousMeasure.fifths != measure.fifths;
      final timeChanged = previousMeasure != null &&
          (previousMeasure.beats != measure.beats ||
              previousMeasure.beatType != measure.beatType);
      final hasSignatureChange = clefChanged || keyChanged || timeChanged;
      final signatureChangeWidth = _signatureChangeWidth(
        measure,
        clefChanged: clefChanged,
        keyChanged: keyChanged,
        timeChanged: timeChanged,
      );
      final contentLeft = measureLeft +
          (isFirst
              ? _headerWidth(measure)
              : hasSignatureChange
                  ? signatureChangeWidth
                  : 18);
      final contentRight = measureRight - 8;
      final accidentalState = <String, int>{};
      if (isFirst) {
        _drawHeader(canvas, measure, measureLeft);
      } else if (hasSignatureChange) {
        _drawChangedSignatures(
          canvas,
          measure,
          measureLeft,
          clefChanged: clefChanged,
          keyChanged: keyChanged,
          timeChanged: timeChanged,
        );
      }

      for (final note in measure.notes) {
        final measureTicks = math.max(1, measure.endTick - measure.startTick);
        final progress = (note.startTick - measure.startTick) / measureTicks;
        final x = contentLeft + progress * (contentRight - contentLeft);
        final isHighlighted =
            currentTick >= note.startTick && currentTick < note.endTick;
        _drawNote(
          canvas,
          note,
          x,
          measure.clef,
          measure.fifths,
          accidentalState,
          isHighlighted,
        );
      }

      if (isActive) {
        final measureTicks = math.max(1, measure.endTick - measure.startTick);
        final progress =
            ((currentTick - measure.startTick) / measureTicks).clamp(0.0, 1.0);
        final x = contentLeft + progress * (contentRight - contentLeft);
        final playhead = Paint()
          ..color = const Color(0xFFE53935)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(x, _staffTop - 12),
          Offset(x, _bottomLine + 12),
          playhead,
        );
      }
    }

    final endX = _left + measures.length * measureWidth;
    canvas.drawLine(
      Offset(endX, _staffTop),
      Offset(endX, _bottomLine),
      ink..strokeWidth = 1.8,
    );
  }

  double _headerWidth(ScoreMeasure measure) =>
      47 + math.min(7, measure.fifths.abs()) * 7.0;

  double _signatureChangeWidth(
    ScoreMeasure measure, {
    required bool clefChanged,
    required bool keyChanged,
    required bool timeChanged,
  }) =>
      10 +
      (clefChanged ? 25 : 0) +
      (keyChanged ? math.min(7, measure.fifths.abs()) * 7.0 : 0) +
      (timeChanged ? 18 : 0);

  void _drawHeader(Canvas canvas, ScoreMeasure measure, double x) {
    _drawClef(canvas, measure.clef, x + 1);
    _drawKeySignature(canvas, measure, x + 24);
    _drawTimeSignature(
      canvas,
      measure,
      x + 27 + math.min(7, measure.fifths.abs()) * 7,
    );
  }

  void _drawChangedSignatures(
    Canvas canvas,
    ScoreMeasure measure,
    double x, {
    required bool clefChanged,
    required bool keyChanged,
    required bool timeChanged,
  }) {
    var cursor = x + 4;
    if (clefChanged) {
      _drawClef(canvas, measure.clef, cursor);
      cursor += 25;
    }
    if (keyChanged) {
      _drawKeySignature(canvas, measure, cursor);
      cursor += math.min(7, measure.fifths.abs()) * 7.0;
    }
    if (timeChanged) {
      _drawTimeSignature(canvas, measure, cursor + 7);
    }
  }

  void _drawClef(Canvas canvas, ScoreClef clef, double x) {
    final symbol = switch (clef) {
      ScoreClef.bass => '𝄢',
      ScoreClef.alto || ScoreClef.tenor => '𝄡',
      ScoreClef.percussion => '𝄥',
      ScoreClef.treble => '𝄞',
    };
    _drawText(canvas, symbol, Offset(x, _staffTop - 13), 37, Colors.black);
  }

  void _drawKeySignature(Canvas canvas, ScoreMeasure measure, double x) {
    final keyGlyph = measure.fifths > 0 ? '♯' : '♭';
    final keyCount = math.min(7, measure.fifths.abs());
    final keySteps = _keySignatureSteps(measure.clef, measure.fifths);
    for (var index = 0; index < keyCount; index++) {
      final y = _yForStep(keySteps[index], measure.clef);
      _drawText(
        canvas,
        keyGlyph,
        Offset(x + index * 7.0, y - 10),
        14,
        Colors.black,
      );
    }
  }

  void _drawTimeSignature(Canvas canvas, ScoreMeasure measure, double x) {
    _drawText(
      canvas,
      '${measure.beats}\n${measure.beatType}',
      Offset(x, _staffTop + 3),
      11,
      Colors.black,
      centered: true,
    );
  }

  void _drawNote(
    Canvas canvas,
    ScoreNote note,
    double x,
    ScoreClef clef,
    int fifths,
    Map<String, int> accidentalState,
    bool highlighted,
  ) {
    final color =
        highlighted ? const Color(0xFFE53935) : const Color(0xFF171717);
    final notePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;
    if (note.isRest) {
      final restGlyph = switch (note.noteType) {
        'whole' => '𝄻',
        'half' => '𝄼',
        'eighth' => '𝄾',
        '16th' || '32nd' || '64th' => '𝄿',
        _ => '𝄽',
      };
      _drawText(
        canvas,
        restGlyph,
        Offset(x - 7, _staffTop + _lineGap),
        22,
        color,
      );
      return;
    }

    final step = _diatonicStep(note.step, note.octave);
    final staffPosition = step - _bottomStep(clef);
    final y = _yForStep(step, clef);
    final keyAlter = _keyAlter(note.step, fifths);
    final accidentalKey = '${note.step}${note.octave}';
    final previousAlter = accidentalState[accidentalKey] ?? keyAlter;
    final accidental = note.accidental != null
        ? _accidentalGlyph(note.accidental!, note.alter)
        : note.alter == previousAlter
            ? null
            : _accidentalGlyph('', note.alter);
    accidentalState[accidentalKey] = note.alter;
    if (accidental != null) {
      _drawText(
        canvas,
        accidental,
        Offset(x - 13, y - 10),
        17,
        color,
      );
    }

    if (staffPosition < 0 || staffPosition > 8) {
      final firstLedger = staffPosition < 0 ? -2 : 10;
      final lastLedger = staffPosition < 0
          ? staffPosition
          : staffPosition - (staffPosition.isEven ? 0 : 1);
      for (var ledger = firstLedger;
          staffPosition < 0 ? ledger >= lastLedger : ledger <= lastLedger;
          ledger += staffPosition < 0 ? -2 : 2) {
        final ledgerY = _yForStep(_bottomStep(clef) + ledger, clef);
        canvas.drawLine(
            Offset(x - 8, ledgerY), Offset(x + 8, ledgerY), notePaint);
      }
    }

    final hollow = note.noteType == 'whole' || note.noteType == 'half';
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.25);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 13, height: 9),
      notePaint..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill,
    );
    canvas.restore();
    notePaint.style = PaintingStyle.fill;

    final isLong = note.noteType == 'whole';
    if (!isLong) {
      final stemDown = staffPosition >= 4;
      final stemX = x + (stemDown ? -6 : 6);
      final stemEnd = y + (stemDown ? 29 : -29);
      canvas.drawLine(Offset(stemX, y), Offset(stemX, stemEnd), notePaint);
      final flagCount = switch (note.noteType) {
        'eighth' => 1,
        '16th' => 2,
        '32nd' => 3,
        '64th' => 4,
        _ => 0,
      };
      for (var flag = 0; flag < flagCount; flag++) {
        final flagY = stemEnd + (stemDown ? -flag * 6.0 : flag * 6.0);
        final path = Path()
          ..moveTo(stemX, flagY)
          ..cubicTo(
            stemX + (stemDown ? 9 : 8),
            flagY + (stemDown ? 5 : 6),
            stemX + (stemDown ? 10 : 9),
            flagY + 13,
            stemX + (stemDown ? 3 : 2),
            flagY + 17,
          );
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.7,
        );
      }
    }

    for (var dot = 0; dot < note.dots; dot++) {
      canvas.drawCircle(Offset(x + 10 + dot * 5, y - 1), 1.5, notePaint);
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    Color color, {
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1,
          fontFamilyFallback: const [
            'Noto Music',
            'Noto Sans Symbols 2',
            'serif',
          ],
        ),
      ),
      textDirection: textDirection,
      textAlign: centered ? TextAlign.center : TextAlign.left,
    )..layout();
    painter.paint(
      canvas,
      centered ? offset - Offset(painter.width / 2, 0) : offset,
    );
  }

  List<int> _keySignatureSteps(ScoreClef clef, int fifths) {
    const trebleSharps = [38, 35, 39, 36, 33, 37, 34];
    const trebleFlats = [34, 37, 33, 36, 32, 35, 31];
    const bassSharps = [24, 21, 25, 22, 19, 23, 20];
    const bassFlats = [20, 23, 19, 22, 18, 21, 17];
    const altoSharps = [31, 28, 32, 29, 26, 30, 27];
    const altoFlats = [27, 30, 26, 29, 25, 28, 24];
    final sharps = switch (clef) {
      ScoreClef.bass => bassSharps,
      ScoreClef.alto || ScoreClef.tenor => altoSharps,
      _ => trebleSharps,
    };
    final flats = switch (clef) {
      ScoreClef.bass => bassFlats,
      ScoreClef.alto || ScoreClef.tenor => altoFlats,
      _ => trebleFlats,
    };
    return fifths >= 0 ? sharps : flats;
  }

  int _bottomStep(ScoreClef clef) => switch (clef) {
        ScoreClef.bass => _diatonicStep('G', 2),
        ScoreClef.alto => _diatonicStep('F', 3),
        ScoreClef.tenor => _diatonicStep('D', 3),
        _ => _diatonicStep('E', 4),
      };

  int _diatonicStep(String step, int octave) {
    const steps = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};
    return octave * 7 + (steps[step] ?? 0);
  }

  double _yForStep(int step, [ScoreClef clef = ScoreClef.treble]) =>
      _bottomLine - (step - _bottomStep(clef)) * (_lineGap / 2);

  int _keyAlter(String step, int fifths) {
    const sharpOrder = ['F', 'C', 'G', 'D', 'A', 'E', 'B'];
    const flatOrder = ['B', 'E', 'A', 'D', 'G', 'C', 'F'];
    final alteredSteps = fifths >= 0 ? sharpOrder : flatOrder;
    return alteredSteps.take(fifths.abs()).contains(step)
        ? fifths >= 0
            ? 1
            : -1
        : 0;
  }

  String _accidentalGlyph(String accidental, int alter) => switch (accidental) {
        'natural' => '♮',
        'sharp' || 'sharp-sharp' => accidental == 'sharp-sharp' ? '𝄪' : '♯',
        'flat' => '♭',
        'double-sharp' => '𝄪',
        'flat-flat' || 'double-flat' => '𝄫',
        _ => switch (alter) {
            2 => '𝄪',
            1 => '♯',
            -1 => '♭',
            -2 => '𝄫',
            _ => '♮',
          },
      };

  @override
  bool shouldRepaint(_ScoreSystemPainter oldDelegate) =>
      oldDelegate.currentTick != currentTick ||
      oldDelegate.measures != measures ||
      oldDelegate.firstMeasureIndex != firstMeasureIndex;
}
