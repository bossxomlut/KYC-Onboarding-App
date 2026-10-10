import 'package:flutter/material.dart';
import 'app/di/dependencies.dart';
import 'app/kyc_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KycApp(dependencies: configureDependencies()));
}
