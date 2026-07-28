import 'package:flutter/material.dart';

/// ParkiWell's monoline brain-blossom mark.
///
/// Renders the transparent brand asset tinted with [color] so the mark can
/// adapt to light and dark surfaces.
class ParkiWellMark extends StatelessWidget {
  final double size;
  final Color color;

  const ParkiWellMark({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'ParkiWell logo',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Image.asset(
            'images/logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            color: color,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
