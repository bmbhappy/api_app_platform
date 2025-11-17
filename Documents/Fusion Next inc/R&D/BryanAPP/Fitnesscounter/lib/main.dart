import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'fitness_counter_app.dart';

void main() {
  // 设置全局错误处理
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // 记录错误但不让应用崩溃
  };
  
  // 捕获异步错误
  PlatformDispatcher.instance.onError = (error, stack) {
    // 记录错误但不让应用崩溃
    return true;
  };
  
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // 设置屏幕方向为竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    runApp(const MyApp());
  }, (error, stack) {
    // 捕获未处理的错误
    // 不抛出错误，避免崩溃
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '健身语音计数器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const FitnessCounterApp(),
    );
  }
}

