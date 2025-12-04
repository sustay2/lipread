import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Subscription'),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: const Center(
        child: Text(
          'Manage your subscription',
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
