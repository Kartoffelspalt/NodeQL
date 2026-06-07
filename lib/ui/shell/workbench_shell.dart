import 'package:flutter/material.dart';

import '../../core/update/update_check_gate.dart';
import '../../features/workbench/presentation/workbench_page.dart';

class WorkbenchShell extends StatelessWidget {
  const WorkbenchShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const UpdateCheckGate(child: WorkbenchPage());
  }
}
