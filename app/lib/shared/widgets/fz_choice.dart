import 'package:flutter/material.dart';

import '../theme/fz_theme.dart';

/// Stadium choice chip: amber when selected (categories, seconds, scopes).
class FzChoice extends StatelessWidget {
  const FzChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? FzColors.bg : FzColors.ink;
    return Material(
      color: selected ? FzColors.ac : FzColors.panel,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? FzColors.ac : FzColors.line),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: FzTheme.of(context).m(12.5, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
