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
    return SvgPicture.asset(
      'assets/images/melodiscan_logo.svg',
      width: size,
      height: size,
      semanticsLabel: 'Logo MelodiScan',
    );
  }
}
