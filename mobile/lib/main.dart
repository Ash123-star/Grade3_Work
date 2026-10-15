import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/state/session_bootstrap.dart';
import 'shared/pandora_splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const PandoraSplash(
      child: ProviderScope(child: SessionBootstrap(child: PandoraApp())),
    ),
  );
}
