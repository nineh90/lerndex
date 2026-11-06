import 'package:flutter/material.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';

class TimeSep extends StatelessWidget {
  const TimeSep({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 3, right: 3),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.purple.shade300,
        ),
      ),
    );
  }
}
