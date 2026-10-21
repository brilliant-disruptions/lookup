import 'package:flutter/material.dart';

/// Dearly's gold-foil headline, re-cut in starlight: a cool metallic sheen
/// clipped to text. Reserve it for one moment per screen.
class FoilText extends StatelessWidget {
  const FoilText(this.text, {super.key, this.style, this.textAlign, this.gold = false});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Use Dearly's actual aged-brass foil (for the share card / celebratory
  /// moments) instead of the default starlight silver-blue.
  final bool gold;

  static const starlight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7FA6D9),
      Color(0xFFE6EEFF),
      Color(0xFFFFFFFF),
      Color(0xFF9CC3FF),
      Color(0xFFDDE8FF),
      Color(0xFF5E86BF),
    ],
    stops: [0, 0.32, 0.48, 0.62, 0.82, 1],
  );

  static const goldFoil = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF8C6D2F),
      Color(0xFFD8B97E),
      Color(0xFFF0DCAE),
      Color(0xFFB5904C),
      Color(0xFFE4C98F),
      Color(0xFF997739),
    ],
    stops: [0, 0.32, 0.48, 0.62, 0.82, 1],
  );

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => (gold ? goldFoil : starlight).createShader(r),
        child: Text(text, style: (style ?? const TextStyle()).copyWith(color: Colors.white), textAlign: textAlign),
      );
}
