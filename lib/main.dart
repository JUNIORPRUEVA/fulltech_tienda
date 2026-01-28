import 'package:flutter/material.dart';

import 'app/fulltech_app.dart';
import 'data/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.init();
  runApp(const FullTechApp());
}
