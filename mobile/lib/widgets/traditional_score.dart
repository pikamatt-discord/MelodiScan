import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/musicxml_score.dart';

class TraditionalScore extends StatefulWidget {
  const TraditionalScore({
    required this.score,
    required this.currentTick,
    super.key,
  });

  final MusicXmlScore score;
  final ValueListenable<int> currentTick;

  @override
  State<TraditionalScore> createState() => _TraditionalScoreState();
}

class _TraditionalScoreState extends State<TraditionalScore>
    with SingleTickerProviderStateMixin {
  static const _singleStaffHeight = 176.0;
  static const _grandStaffHeight = 176.0;
  final _scrollController = ScrollController();
  late final AnimationController _cursorController;
  late final ValueNotifier<double> _smoothTick;
  late Animation<double> _cursorAnimation;
  late DateTime _lastPositionUpdate;
  int _lastScrolledSystem = 0;
  int _measuresPerSystem = 1;

  double get _systemHeight =>
      widget.score.hasGrandStaff ? _grandStaffHeight : _singleStaffHeight;

  int _measureIndexAtTick() {
    if (widget.score.measures.isEmpty) return 0;
    for (var index = 0; index < widget.score.measures.length; index++) {
      if (widget.currentTick.value < widget.score.measures[index].endTick) {
        return index;
      }
    }
    return widget.score.measures.length - 1;
  }

  @override
  void initState() {
    super.initState();
    final tick = widget.currentTick.value.toDouble();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..addListener(_updateSmoothedTick);
    _smoothTick = ValueNotifier<double>(tick);
    _cursorAnimation = AlwaysStoppedAnimation<double>(tick);
    _lastPositionUpdate = DateTime.now();
    widget.currentTick.addListener(_handlePositionChanged);
  }

  @override
  void didUpdateWidget(covariant TraditionalScore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTick != widget.currentTick) {
      oldWidget.currentTick.removeListener(_handlePositionChanged);
      widget.currentTick.addListener(_handlePositionChanged);
      _cursorController.stop();
      _smoothTick.value = widget.currentTick.value.toDouble();
      _lastPositionUpdate = DateTime.now();
    }
  }

  void _updateSmoothedTick() {
    _smoothTick.value = _cursorAnimation.value;
  }

  void _handlePositionChanged() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastPositionUpdate);
    _lastPositionUpdate = now;
    final duration = Duration(
      milliseconds: elapsed.inMilliseconds.clamp(24, 120).toInt(),
    );
    _cursorController
      ..stop()
      ..duration = duration;
    _cursorAnimation = Tween<double>(
      begin: _smoothTick.value,
      end: widget.currentTick.value.toDouble(),
    ).animate(_cursorController);
    _cursorController.forward(from: 0);
    _scrollToActiveSystem();
  }

  void _scrollToActiveSystem() {
    final systemIndex = _measureIndexAtTick() ~/ _measuresPerSystem;
    if (systemIndex == _lastScrolledSystem) return;
    _lastScrolledSystem = systemIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final offset = systemIndex * _systemHeight;
      _scrollController.animateTo(
        offset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    widget.currentTick.removeListener(_handlePositionChanged);
    _cursorController.removeListener(_updateSmoothedTick);
    _cursorController.dispose();
    _smoothTick.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _measuresPerSystem =
            math.max(1, ((constraints.maxWidth - 68) / 190).floor());
        _scrollToActiveSystem();

        final systemCount =
            (widget.score.measures.length / _measuresPerSystem).ceil();
        return ColoredBox(
          key: const Key('traditional_score_view'),
          color: const Color(0xFFFFFEFA),
          child: ListView.builder(
            controller: _scrollController,
            itemExtent: _systemHeight,
            itemCount: systemCount,
            itemBuilder: (context, systemIndex) {
              final start = systemIndex * _measuresPerSystem;
              final end = math.min(
                start + _measuresPerSystem,
                widget.score.measures.length,
              );
              final measures = widget.score.measures.sublist(start, end);
              return Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _ScoreSystemPainter(
                        measures: measures,
                        firstMeasureIndex: start,
                        isGrandStaff: widget.score.hasGrandStaff,
                        textDirection: Directionality.of(context),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _ScorePlaybackPainter(
                        measures: measures,
                        firstMeasureIndex: start,
                        currentTick: _smoothTick,
                        isGrandStaff: widget.score.hasGrandStaff,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
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
    required this.isGrandStaff,
    required this.textDirection,
  });

  final List<ScoreMeasure> measures;
  final int firstMeasureIndex;
  final bool isGrandStaff;
  final TextDirection textDirection;

  static const _left = 10.0;
  static const _right = 10.0;
  static const _staffTop = 48.0;
  static const _lineGap = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xFF171717)
      ..strokeWidth = 1.15;
    final staffWidth = size.width - _left - _right;
    final measureWidth = staffWidth / measures.length;
    final tieStarts = <(int, String, int, int), (double, double)>{};

    for (var staff = 1; staff <= (isGrandStaff ? 2 : 1); staff++) {
      final top = _staffTopFor(staff);
      for (var line = 0; line < 5; line++) {
        final y = top + line * _lineGap;
        canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), ink);
      }
    }

    if (isGrandStaff) {
      final upperTop = _staffTopFor(1);
      final lowerBottom = _staffTopFor(2) + 4 * _lineGap;
      final bracket = Paint()
        ..color = const Color(0xFF171717)
        ..strokeWidth = 1.6;
      canvas.drawLine(Offset(4, upperTop), Offset(4, lowerBottom), bracket);
      canvas.drawLine(Offset(4, upperTop), Offset(_left, upperTop), bracket);
      canvas.drawLine(
          Offset(4, lowerBottom), Offset(_left, lowerBottom), bracket);
    }

    for (var index = 0; index < measures.length; index++) {
      final measure = measures[index];
      final measureLeft = _left + index * measureWidth;
      final measureRight = measureLeft + measureWidth;
      final isSystemStart = index == 0;

      if (index > 0) {
        for (var staff = 1; staff <= (isGrandStaff ? 2 : 1); staff++) {
          final top = _staffTopFor(staff);
          canvas.drawLine(
            Offset(measureLeft, top),
            Offset(measureLeft, top + 4 * _lineGap),
            ink,
          );
        }
        if (isGrandStaff) {
          canvas.drawLine(
            Offset(measureLeft, _staffTopFor(1) + 4 * _lineGap),
            Offset(measureLeft, _staffTopFor(2)),
            ink,
          );
        }
      }

      _drawText(
        canvas,
        measure.number,
        Offset(measureLeft + 2, 8),
        10,
        const Color(0xFF555555),
      );

      final previousMeasure = index > 0 ? measures[index - 1] : null;
      final clefChanged = previousMeasure != null &&
          _staffClefsChanged(previousMeasure, measure);
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
          (isSystemStart
              ? _headerWidth(measure)
              : hasSignatureChange
                  ? signatureChangeWidth
                  : 18);
      final contentRight = measureRight - 8;
      final accidentalState = <int, Map<String, int>>{};
      if (isSystemStart) {
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

      final tupletNotesRemaining = <(int, String, int, int), int>{};
      for (final note in measure.notes) {
        final measureTicks = math.max(1, measure.endTick - measure.startTick);
        final progress = (note.startTick - measure.startTick) / measureTicks;
        final x = contentLeft + progress * (contentRight - contentLeft);
        final noteClef = measure.clefForStaff(note.staff);
        final staffTop = _staffTopFor(note.staff);
        final noteY = note.isRest
            ? staffTop + _lineGap
            : _noteY(note, noteClef, staffTop);
        final tieKey = (note.staff, note.step, note.octave, note.alter);
        if (note.ties.contains('stop')) {
          final tieStart = tieStarts.remove(tieKey);
          if (tieStart != null) {
            _drawTie(canvas, tieStart, (x, noteY));
          }
        }
        if (note.ties.contains('start')) {
          tieStarts[tieKey] = (x, noteY);
        }
        final actualNotes = note.actualNotes;
        final normalNotes = note.normalNotes;
        if (actualNotes != null &&
            normalNotes != null &&
            actualNotes > 1 &&
            actualNotes != normalNotes) {
          final group = (note.staff, note.voice, actualNotes, normalNotes);
          final remaining = tupletNotesRemaining[group] ?? 0;
          if (remaining == 0) {
            _drawText(
              canvas,
              '$actualNotes:$normalNotes',
              Offset(x, staffTop - 13),
              8,
              const Color(0xFF555555),
              centered: true,
            );
          }
          tupletNotesRemaining[group] =
              (remaining == 0 ? actualNotes : remaining) - 1;
        }
        _drawNote(
          canvas,
          note,
          x,
          noteClef,
          measure.fifths,
          accidentalState.putIfAbsent(note.staff, () => {}),
          false,
          staffTop,
        );
      }
    }

    final endX = _left + measures.length * measureWidth;
    ink.strokeWidth = 1.8;
    for (var staff = 1; staff <= (isGrandStaff ? 2 : 1); staff++) {
      final top = _staffTopFor(staff);
      canvas.drawLine(Offset(endX, top), Offset(endX, top + 4 * _lineGap), ink);
    }
    if (isGrandStaff) {
      canvas.drawLine(
        Offset(endX, _staffTopFor(1) + 4 * _lineGap),
        Offset(endX, _staffTopFor(2)),
        ink,
      );
    }
  }

  double _staffTopFor(int staff) => !isGrandStaff
      ? _staffTop
      : staff == 2
          ? 108
          : 34;

  double _noteY(ScoreNote note, ScoreClef clef, double staffTop) =>
      staffTop +
      4 * _lineGap -
      (_diatonicStep(note.step, note.octave) - _bottomStep(clef)) *
          (_lineGap / 2);

  void _drawTie(
    Canvas canvas,
    (double, double) start,
    (double, double) end,
  ) {
    final fromX = start.$1 + 6;
    final toX = end.$1 - 6;
    if (toX <= fromX) return;
    final y = (start.$2 + end.$2) / 2 + 5;
    final curve = math.min(10.0, math.max(3.0, (toX - fromX) * 0.1));
    final path = Path()
      ..moveTo(fromX, start.$2 + 4)
      ..cubicTo(
        fromX + (toX - fromX) / 3,
        y + curve,
        fromX + 2 * (toX - fromX) / 3,
        y + curve,
        toX,
        end.$2 + 4,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF171717)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  int _staffCount(ScoreMeasure measure) => math.max(
        measure.staves,
        measure.notes.fold(1, (count, note) => math.max(count, note.staff)),
      );

  bool _staffClefsChanged(ScoreMeasure previous, ScoreMeasure current) {
    for (var staff = 1; staff <= _staffCount(current); staff++) {
      if (previous.clefForStaff(staff) != current.clefForStaff(staff)) {
        return true;
      }
    }
    return false;
  }

  double _headerWidth(ScoreMeasure measure) =>
      (isGrandStaff ? 67 : 47) + math.min(7, measure.fifths.abs()) * 7.0;

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
    for (var staff = 1; staff <= _staffCount(measure); staff++) {
      final top = _staffTopFor(staff);
      final clefX = x + (isGrandStaff ? 12 : 1);
      final keyX = x + (isGrandStaff ? 35 : 24);
      _drawClef(canvas, measure.clefForStaff(staff), clefX, top);
      _drawKeySignature(canvas, measure, keyX, top, staff);
      _drawTimeSignature(
        canvas,
        measure,
        x + (isGrandStaff ? 38 : 27) + math.min(7, measure.fifths.abs()) * 7,
        top,
      );
    }
  }

  void _drawChangedSignatures(
    Canvas canvas,
    ScoreMeasure measure,
    double x, {
    required bool clefChanged,
    required bool keyChanged,
    required bool timeChanged,
  }) {
    for (var staff = 1; staff <= _staffCount(measure); staff++) {
      var cursor = x + 4;
      final top = _staffTopFor(staff);
      if (clefChanged) {
        _drawClef(canvas, measure.clefForStaff(staff), cursor, top);
        cursor += 25;
      }
      if (keyChanged) {
        _drawKeySignature(canvas, measure, cursor, top, staff);
        cursor += math.min(7, measure.fifths.abs()) * 7.0;
      }
      if (timeChanged) {
        _drawTimeSignature(canvas, measure, cursor + 7, top);
      }
    }
  }

  void _drawClef(
    Canvas canvas,
    ScoreClef clef,
    double x,
    double staffTop,
  ) {
    final symbol = switch (clef) {
      ScoreClef.bass => '𝄢',
      ScoreClef.alto || ScoreClef.tenor => '𝄡',
      ScoreClef.percussion => '𝄥',
      ScoreClef.treble => '𝄞',
    };
    _drawText(canvas, symbol, Offset(x, staffTop - 13), 37, Colors.black);
  }

  void _drawKeySignature(
    Canvas canvas,
    ScoreMeasure measure,
    double x,
    double staffTop,
    int staff,
  ) {
    final keyGlyph = measure.fifths > 0 ? '♯' : '♭';
    final keyCount = math.min(7, measure.fifths.abs());
    final keySteps =
        _keySignatureSteps(measure.clefForStaff(staff), measure.fifths);
    for (var index = 0; index < keyCount; index++) {
      final y = _yForStep(
        keySteps[index],
        measure.clefForStaff(staff),
        staffTop,
      );
      _drawText(
        canvas,
        keyGlyph,
        Offset(x + index * 7.0, y - 10),
        14,
        Colors.black,
      );
    }
  }

  void _drawTimeSignature(
    Canvas canvas,
    ScoreMeasure measure,
    double x,
    double staffTop,
  ) {
    _drawText(
      canvas,
      '${measure.beats}\n${measure.beatType}',
      Offset(x, staffTop + 3),
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
    double staffTop,
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
        Offset(x - 7, staffTop + _lineGap),
        22,
        color,
      );
      for (var dot = 0; dot < note.dots; dot++) {
        canvas.drawCircle(
          Offset(x + 7 + dot * 5, staffTop + _lineGap + 2),
          1.5,
          notePaint,
        );
      }
      return;
    }

    final step = _diatonicStep(note.step, note.octave);
    final staffPosition = step - _bottomStep(clef);
    final y = _yForStep(step, clef, staffTop);
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
        final ledgerY = _yForStep(_bottomStep(clef) + ledger, clef, staffTop);
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

  double _yForStep(
    int step,
    ScoreClef clef,
    double staffTop,
  ) =>
      staffTop + 4 * _lineGap - (step - _bottomStep(clef)) * (_lineGap / 2);

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
      oldDelegate.measures != measures ||
      oldDelegate.firstMeasureIndex != firstMeasureIndex;
}

class _ScorePlaybackPainter extends CustomPainter {
  _ScorePlaybackPainter({
    required this.measures,
    required this.firstMeasureIndex,
    required this.currentTick,
    required this.isGrandStaff,
  }) : super(repaint: currentTick);

  final List<ScoreMeasure> measures;
  final int firstMeasureIndex;
  final ValueListenable<double> currentTick;
  final bool isGrandStaff;

  static const _left = 10.0;
  static const _right = 10.0;
  static const _staffTop = 48.0;
  static const _lineGap = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (measures.isEmpty) return;
    final measureWidth = (size.width - _left - _right) / measures.length;
    final tick = currentTick.value;

    for (var index = 0; index < measures.length; index++) {
      final measure = measures[index];
      if (tick < measure.startTick || tick >= measure.endTick) continue;

      final measureLeft = _left + index * measureWidth;
      final measureRight = measureLeft + measureWidth;
      final isSystemStart = index == 0;
      final previous = index > 0 ? measures[index - 1] : null;
      final clefChanged =
          previous != null && _staffClefsChanged(previous, measure);
      final keyChanged = previous != null && previous.fifths != measure.fifths;
      final timeChanged = previous != null &&
          (previous.beats != measure.beats ||
              previous.beatType != measure.beatType);
      final signatureChangeWidth = 10 +
          (clefChanged ? 25 : 0) +
          (keyChanged ? math.min(7, measure.fifths.abs()) * 7.0 : 0) +
          (timeChanged ? 18 : 0);
      final contentLeft = measureLeft +
          (isSystemStart
              ? (isGrandStaff ? 67 : 47) +
                  math.min(7, measure.fifths.abs()) * 7.0
              : clefChanged || keyChanged || timeChanged
                  ? signatureChangeWidth
                  : 18);
      final contentRight = measureRight - 8;
      final activeHighlight = Paint()
        ..color = const Color(0xFFFFD54F).withValues(alpha: 0.10);
      final upperTop = _staffTopFor(1);
      final lowerBottom = _staffTopFor(isGrandStaff ? 2 : 1) + 4 * _lineGap;
      canvas.drawRect(
        Rect.fromLTRB(
          measureLeft,
          upperTop - 15,
          measureRight,
          lowerBottom + 16,
        ),
        activeHighlight,
      );

      final measureTicks = math.max(1, measure.endTick - measure.startTick);
      final progress =
          ((tick - measure.startTick) / measureTicks).clamp(0.0, 1.0);
      final x = contentLeft + progress * (contentRight - contentLeft);
      final playhead = Paint()
        ..color = const Color(0xFFE53935)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(x, upperTop - 12),
        Offset(x, lowerBottom + 12),
        playhead,
      );

      for (final note in measure.notes) {
        if (note.isRest || tick < note.startTick || tick >= note.endTick) {
          continue;
        }
        final noteProgress =
            (note.startTick - measure.startTick) / measureTicks;
        final noteX = contentLeft + noteProgress * (contentRight - contentLeft);
        final step = _diatonicStep(note.step, note.octave);
        final staffTop = _staffTopFor(note.staff);
        final clef = measure.clefForStaff(note.staff);
        final y = staffTop +
            4 * _lineGap -
            (step - _bottomStep(clef)) * (_lineGap / 2);
        final noteHead = Paint()
          ..color = const Color(0xFFE53935)
          ..style = PaintingStyle.fill;
        canvas.save();
        canvas.translate(noteX, y);
        canvas.rotate(-0.25);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 13, height: 9),
          noteHead,
        );
        canvas.restore();
      }
      return;
    }
  }

  double _staffTopFor(int staff) => !isGrandStaff
      ? _staffTop
      : staff == 2
          ? 108
          : 34;

  bool _staffClefsChanged(ScoreMeasure previous, ScoreMeasure current) {
    for (var staff = 1;
        staff <= math.max(previous.staves, current.staves);
        staff++) {
      if (previous.clefForStaff(staff) != current.clefForStaff(staff)) {
        return true;
      }
    }
    return false;
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

  @override
  bool shouldRepaint(_ScorePlaybackPainter oldDelegate) =>
      oldDelegate.measures != measures ||
      oldDelegate.firstMeasureIndex != firstMeasureIndex ||
      oldDelegate.currentTick != currentTick;
}
