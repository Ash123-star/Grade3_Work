import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/state/session_bootstrap.dart';
import 'shared/pandora_splash.dart';
import 'core/assets/oss_asset_bundle.dart';
import 'core/config.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final assets = OssAssetBundle.instance;
  await assets
      .initialize(enabled: !AppConfig.mock)
      .timeout(const Duration(seconds: 4), onTimeout: () {});
  unawaited(assets.loadDisplayFont());
  runApp(
    DefaultAssetBundle(
      bundle: assets,
      child: const PandoraSplash(
        child: ProviderScope(child: SessionBootstrap(child: PandoraApp())),
      ),
    ),
  );
}
