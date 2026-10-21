import 'package:flutter/material.dart';

import '../theme.dart';
import 'grain.dart';

/// Dearly's invitation frame: a double hairline (accent outer, muted inner)
/// with breathing room between. Here the outer line is a faint blue.
class InviteFrame extends StatelessWidget {
  const InviteFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.outer = const Color(0x663C9DFF),
    this.inner = LookUpColors.line,
    this.fill = LookUpColors.panel,
    this.grain = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color outer;
  final Color inner;
  final Color fill;
  final bool grain;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const rOuter = BorderRadius.all(Radius.circular(8));
    const rInner = BorderRadius.all(Radius.circular(4));
    final body = Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: rOuter,
        border: Border.all(color: outer),
        boxShadow: const [
          BoxShadow(color: Color(0x332F6BB8), blurRadius: 36, spreadRadius: -8, offset: Offset(0, 14)),
          BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Stack(
        children: [
          if (grain) const Positioned.fill(child: Grain(borderRadius: rInner)),
          Container(
            decoration: BoxDecoration(borderRadius: rInner, border: Border.all(color: inner)),
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: rOuter, onTap: onTap, child: body),
    );
  }
}
