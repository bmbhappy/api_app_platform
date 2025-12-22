import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nt96650_app/pages/main_navigation.dart';
import 'package:nt96650_app/state/app_state.dart';

void main() {
  // 使用多種方式輸出日誌，確保在 logcat 中可見
  developer.log('========================================', name: 'App');
  developer.log('[App] main() 開始執行', name: 'App');
  developer.log('========================================', name: 'App');
  debugPrint('========================================');
  debugPrint('[App] main() 開始執行');
  debugPrint('========================================');
  print('========================================');
  print('[App] main() 開始執行');
  print('========================================');
  
  try {
    WidgetsFlutterBinding.ensureInitialized();
    developer.log('[App] WidgetsFlutterBinding.ensureInitialized() 完成', name: 'App');
    debugPrint('[App] WidgetsFlutterBinding.ensureInitialized() 完成');
    print('[App] WidgetsFlutterBinding.ensureInitialized() 完成');
    
    // 延遲初始化 media_kit，避免阻塞應用啟動
    // 實際使用時再初始化（在 LiveViewPage 中）
    developer.log('[App] 準備運行 MyApp', name: 'App');
    debugPrint('[App] 準備運行 MyApp');
    print('[App] 準備運行 MyApp');
    runApp(MyApp());
    developer.log('[App] runApp() 已調用', name: 'App');
    debugPrint('[App] runApp() 已調用');
    print('[App] runApp() 已調用');
  } catch (e, stackTrace) {
    developer.log('[App] main() 出錯: $e', name: 'App', error: e, stackTrace: stackTrace);
    debugPrint('[App] main() 出錯: $e');
    debugPrint('[App] 堆棧: $stackTrace');
    print('[App] main() 出錯: $e');
    print('[App] 堆棧: $stackTrace');
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    developer.log('[App] MyApp.build() 被調用', name: 'App');
    debugPrint('[App] MyApp.build() 被調用');
    print('[App] MyApp.build() 被調用');
    try {
      return ChangeNotifierProvider(
        create: (_) {
          developer.log('[App] 創建 AppState', name: 'App');
          debugPrint('[App] 創建 AppState');
          print('[App] 創建 AppState');
          return AppState();
        },
        child: MaterialApp(
          title: 'NT96650 行車記錄器控制',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: Builder(
            builder: (context) {
              developer.log('[App] 創建 MainNavigationPage', name: 'App');
              debugPrint('[App] 創建 MainNavigationPage');
              print('[App] 創建 MainNavigationPage');
              try {
                return MainNavigationPage();
              } catch (e, stackTrace) {
                developer.log('[App] 創建 MainNavigationPage 出錯: $e', name: 'App', error: e, stackTrace: stackTrace);
                debugPrint('[App] 創建 MainNavigationPage 出錯: $e');
                debugPrint('[App] 堆棧: $stackTrace');
                print('[App] 創建 MainNavigationPage 出錯: $e');
                print('[App] 堆棧: $stackTrace');
                // 返回一個簡單的錯誤頁面
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text('應用啟動錯誤', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 8),
                        Text('$e', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
          debugShowCheckedModeBanner: false,
        ),
      );
    } catch (e, stackTrace) {
      developer.log('[App] MyApp.build() 出錯: $e', name: 'App', error: e, stackTrace: stackTrace);
      debugPrint('[App] MyApp.build() 出錯: $e');
      debugPrint('[App] 堆棧: $stackTrace');
      // 返回一個簡單的錯誤頁面
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text('應用構建錯誤', style: TextStyle(fontSize: 18)),
                SizedBox(height: 8),
                Text('$e', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }
  }
}
