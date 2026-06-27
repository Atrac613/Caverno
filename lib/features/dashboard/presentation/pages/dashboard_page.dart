import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../widgets/dashboard_view.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('dashboard.title'.tr())),
      body: const DashboardView(),
    );
  }
}
