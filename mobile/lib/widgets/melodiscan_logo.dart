import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MelodiScanLogo extends StatelessWidget {
  const MelodiScanLogo({
    super.key,
    this.size = 120,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        'assets/images/melodiscan_logo.svg',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        semanticsLabel: 'Logo MelodiScan',
      ),
    );
  }
}
