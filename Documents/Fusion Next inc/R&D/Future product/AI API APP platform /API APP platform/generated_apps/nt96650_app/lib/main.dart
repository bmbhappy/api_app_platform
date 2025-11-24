import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nt96650_app/pages/main_navigation.dart';
import 'package:nt96650_app/state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 延遲初始化 media_kit，避免阻塞應用啟動
  // 實際使用時再初始化（在 LiveViewPage 中）
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'NT96650 行車記錄器控制',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: MainNavigationPage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
