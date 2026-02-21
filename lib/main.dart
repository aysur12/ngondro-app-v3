import 'package:flutter/material.dart';
import 'di/injection.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const NgondroApp());
}
