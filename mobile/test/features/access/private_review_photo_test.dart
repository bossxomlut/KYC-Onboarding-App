import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/access/presentation/widgets/private_review_photo.dart';

void main() {
  testWidgets(
    'review photos are evicted from shared cache when the route closes',
    (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PrivateReviewPhoto(
            bytes: bytes,
            label: 'Private identity document',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image)).image;
      final key = await image.obtainKey(ImageConfiguration.empty);
      expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    },
  );
}
