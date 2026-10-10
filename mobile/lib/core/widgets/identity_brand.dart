import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class IdentityBrand extends StatelessWidget {
  const IdentityBrand({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.verified_user, color: color ?? AppTheme.primary, size: 25),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          'Identity',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color ?? AppTheme.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class PrivacyNote extends StatelessWidget {
  const PrivacyNote({
    required this.text,
    this.textAlign = TextAlign.center,
    super.key,
  });

  final String text;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: textAlign == TextAlign.center
        ? MainAxisAlignment.center
        : MainAxisAlignment.start,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(Icons.lock_outline, size: 16, color: AppTheme.muted),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
