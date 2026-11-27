import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// Thin bar above results found on the device, shown while the online search
/// is still running: without it the short list would read as the whole answer.
class OnlineSearchProgress extends StatelessWidget {
  const OnlineSearchProgress({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(
      horizontal: Dimens.spacing8,
      vertical: Dimens.spacing4,
    ),
    child: LinearProgressIndicator(),
  );
}
