import 'package:flutter/material.dart';

/// Static skeleton mirroring the loaded detail body — hero row (cover +
/// title lines + pill chips), action row, chapter search, chapter rows —
/// while the controller materializes the series. Same convention as the
/// browse skeleton (Plan/08): flat surfaceContainerHighest blocks,
/// deliberately NOT animated so widget tests stay FakeAsync-safe.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block({double? width, double? height}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: shade,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    Widget pill({required double width, required double height}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: shade,
            borderRadius: BorderRadius.circular(999),
          ),
        );

    return Column(
      children: [
        // Hero row: cover + two title lines + original-title line + chips.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 96,
                height: 136,
                decoration: BoxDecoration(
                  color: shade,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(width: double.infinity, height: 18),
                    const SizedBox(height: 8),
                    block(width: 160, height: 14),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        pill(width: 72, height: 22),
                        const SizedBox(width: 6),
                        pill(width: 56, height: 22),
                        const SizedBox(width: 6),
                        pill(width: 64, height: 22),
                      ],
                    ),
                    const SizedBox(height: 12),
                    block(width: 220, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Action row (site switcher + primary actions) + chapter search.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              pill(width: 132, height: 36),
              const SizedBox(width: 8),
              pill(width: 108, height: 36),
              const SizedBox(width: 8),
              pill(width: 64, height: 36),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: shade,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              pill(width: 40, height: 40),
            ],
          ),
        ),
        // Chapter rows: title line + date stub.
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: 8,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Expanded(child: block(height: 14)),
                  const SizedBox(width: 16),
                  block(width: 72, height: 11),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
