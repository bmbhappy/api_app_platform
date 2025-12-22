import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:nt96650_app/pages/live_view_page.dart';
import 'package:nt96650_app/pages/file_management_page.dart';
import 'package:nt96650_app/pages/settings_page.dart';
import 'package:nt96650_app/pages/wifi_connection_page.dart';

/// 主導航頁面 - 四個主要功能模組
class MainNavigationPage extends StatefulWidget {
  @override
  _MainNavigationPageState createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  int? _previousIndex;
  
  // 緩存已創建的頁面，實現真正的懶加載
  final Map<int, Widget> _pageCache = {};
  
  // FileManagementPage 的 GlobalKey，用於在頁面可見時通知載入數據
  final GlobalKey<FileManagementPageState> _fileManagementKey = GlobalKey<FileManagementPageState>();
  
  // 防止重複調用 onPageVisible() 的標記
  bool _isCallingOnPageVisible = false;
  
  @override
  void initState() {
    super.initState();
    developer.log('[MainNavigation] initState() 開始', name: 'MainNavigation');
    print('[MainNavigation] initState() 開始');
    
    // 熱重載時清理緩存，確保使用新的 Widget 實例
    // 這可以防止熱重載時使用舊的 Widget 實例導致問題
    _pageCache.clear();
    developer.log('[MainNavigation] 已清空頁面緩存（熱重載安全）', name: 'MainNavigation');
    print('[MainNavigation] 已清空頁面緩存（熱重載安全）');
    
    // 不在 initState 中創建頁面，讓 build() 方法來處理
    // 這樣可以避免阻塞主線程
    developer.log('[MainNavigation] initState() 完成', name: 'MainNavigation');
    print('[MainNavigation] initState() 完成');
  }
  
  @override
  void dispose() {
    developer.log('[MainNavigation] dispose() 開始', name: 'MainNavigation');
    print('[MainNavigation] dispose() 開始');
    // 清理頁面緩存，確保資源正確釋放
    // 注意：Widget 的 dispose 會自動調用，這裡只是清理緩存引用
    _pageCache.clear();
    developer.log('[MainNavigation] dispose() 完成', name: 'MainNavigation');
    print('[MainNavigation] dispose() 完成');
    super.dispose();
  }
  
  // 只在首次訪問時創建頁面
  Widget _getOrCreatePage(int index) {
    developer.log('[MainNavigation] _getOrCreatePage($index) 被調用', name: 'MainNavigation');
    print('[MainNavigation] _getOrCreatePage($index) 被調用');
    if (!_pageCache.containsKey(index)) {
      developer.log('[MainNavigation] 頁面 $index 尚未創建，開始創建', name: 'MainNavigation');
      print('[MainNavigation] 頁面 $index 尚未創建，開始創建');
      switch (index) {
        case 0:
          developer.log('[MainNavigation] 創建 LiveViewPage', name: 'MainNavigation');
          print('[MainNavigation] 創建 LiveViewPage');
          _pageCache[0] = LiveViewPage();           // 1. 實時影像瀏覽及錄影照相控制
          break;
        case 1:
          // 檔案管理頁面：只在用戶切換到該頁面時才創建
          // 這樣可以確保頁面創建時不會立即執行任何操作
          developer.log('[MainNavigation] 創建 FileManagementPage', name: 'MainNavigation');
          print('[MainNavigation] 創建 FileManagementPage');
          _pageCache[1] = FileManagementPage(key: _fileManagementKey);     // 2. 檔案瀏覽以及管理
          developer.log('[MainNavigation] FileManagementPage 創建完成', name: 'MainNavigation');
          print('[MainNavigation] FileManagementPage 創建完成');
          break;
        case 2:
          developer.log('[MainNavigation] 創建 SettingsPage', name: 'MainNavigation');
          print('[MainNavigation] 創建 SettingsPage');
          _pageCache[2] = SettingsPage();           // 3. 各式功能參數設定
          break;
        case 3:
          developer.log('[MainNavigation] 創建 WifiConnectionPage', name: 'MainNavigation');
          print('[MainNavigation] 創建 WifiConnectionPage');
          _pageCache[3] = WifiConnectionPage();     // 4. 裝置 Wi-Fi 連結設定
          break;
        default:
          developer.log('[MainNavigation] 創建默認頁面 (LiveViewPage)', name: 'MainNavigation');
          print('[MainNavigation] 創建默認頁面 (LiveViewPage)');
          _pageCache[0] = LiveViewPage();
      }
      developer.log('[MainNavigation] 頁面 $index 創建完成', name: 'MainNavigation');
      print('[MainNavigation] 頁面 $index 創建完成');
    } else {
      developer.log('[MainNavigation] 頁面 $index 已存在於緩存中', name: 'MainNavigation');
      print('[MainNavigation] 頁面 $index 已存在於緩存中');
    }
    return _pageCache[index]!;
  }
  
  // 創建佔位符頁面，用於 IndexedStack
  Widget _getPlaceholderPage(int index) {
    return Container(
      color: Colors.white,
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
  
  void _handlePageChange(int newIndex) {
    developer.log('[MainNavigation] _handlePageChange: $_currentIndex -> $newIndex', name: 'MainNavigation');
    print('[MainNavigation] _handlePageChange: $_currentIndex -> $newIndex');
    final wasFileManagement = _currentIndex == 1;
    final willBeFileManagement = newIndex == 1;
    
    // 如果切換到檔案管理頁面，先創建它（在 setState 之前）
    // 這樣可以確保頁面在切換時才被創建，而不是在應用啟動時
    if (willBeFileManagement && !_pageCache.containsKey(newIndex)) {
      developer.log('[MainNavigation] 準備切換到檔案管理頁面，先創建頁面', name: 'MainNavigation');
      print('[MainNavigation] 準備切換到檔案管理頁面，先創建頁面');
      _getOrCreatePage(newIndex);
    }
    
    // 對於其他頁面，也只在需要時創建
    if (!_pageCache.containsKey(newIndex) && newIndex != 1) {
      developer.log('[MainNavigation] 準備切換到頁面 $newIndex，先創建頁面', name: 'MainNavigation');
      print('[MainNavigation] 準備切換到頁面 $newIndex，先創建頁面');
      _getOrCreatePage(newIndex);
    }
    
    developer.log('[MainNavigation] 執行 setState，切換頁面', name: 'MainNavigation');
    print('[MainNavigation] 執行 setState，切換頁面');
    setState(() {
      _previousIndex = _currentIndex;
      _currentIndex = newIndex;
    });
    developer.log('[MainNavigation] setState 完成，當前頁面: $_currentIndex', name: 'MainNavigation');
    print('[MainNavigation] setState 完成，當前頁面: $_currentIndex');
    
    // 如果切換到檔案管理頁面，通知它載入數據（只在首次切換時）
    // 確保只在用戶主動切換到該頁面時才載入，而不是在應用啟動時
    // 使用標記防止重複調用
    if (willBeFileManagement && _previousIndex != 1 && !wasFileManagement) {
      // 檢查是否已經在延遲調用中，防止重複
      if (!_isCallingOnPageVisible) {
        _isCallingOnPageVisible = true;
        developer.log('[MainNavigation] 切換到檔案管理頁面，準備調用 onPageVisible()', name: 'MainNavigation');
        print('[MainNavigation] 切換到檔案管理頁面，準備調用 onPageVisible()');
        // 使用延遲確保頁面切換動畫完成後再載入
        Future.delayed(Duration(milliseconds: 300), () {
          developer.log('[MainNavigation] 延遲後檢查，mounted=$mounted, _currentIndex=$_currentIndex', name: 'MainNavigation');
          print('[MainNavigation] 延遲後檢查，mounted=$mounted, _currentIndex=$_currentIndex');
          _isCallingOnPageVisible = false; // 重置標記
          if (mounted && _currentIndex == 1) {
            developer.log('[MainNavigation] 調用 FileManagementPage.onPageVisible()', name: 'MainNavigation');
            print('[MainNavigation] 調用 FileManagementPage.onPageVisible()');
            _fileManagementKey.currentState?.onPageVisible();
          } else {
            developer.log('[MainNavigation] 跳過調用 onPageVisible()，因為頁面已切換或未掛載', name: 'MainNavigation');
            print('[MainNavigation] 跳過調用 onPageVisible()，因為頁面已切換或未掛載');
          }
        });
      } else {
        developer.log('[MainNavigation] 跳過調用 onPageVisible()，因為已經在調用中', name: 'MainNavigation');
        print('[MainNavigation] 跳過調用 onPageVisible()，因為已經在調用中');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // 使用 debugPrint 和 print 雙重輸出，確保日誌可見
    debugPrint('[MainNavigation] build() 被調用，當前頁面索引: $_currentIndex');
    print('[MainNavigation] build() 被調用，當前頁面索引: $_currentIndex');
    
    try {
      // 確保當前頁面已創建，但使用異步方式避免阻塞主線程
      if (!_pageCache.containsKey(_currentIndex)) {
        debugPrint('[MainNavigation] 當前頁面 $_currentIndex 尚未創建，準備異步創建');
        print('[MainNavigation] 當前頁面 $_currentIndex 尚未創建，準備異步創建');
        // 使用 addPostFrameCallback 異步創建頁面，避免阻塞主線程
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_pageCache.containsKey(_currentIndex)) {
            debugPrint('[MainNavigation] 異步創建頁面 $_currentIndex');
            print('[MainNavigation] 異步創建頁面 $_currentIndex');
            _getOrCreatePage(_currentIndex);
            if (mounted) {
              setState(() {}); // 觸發重建以顯示頁面
            }
          }
        });
      }
      
      debugPrint('[MainNavigation] 構建 IndexedStack，頁面緩存狀態: [0:${_pageCache.containsKey(0)}, 1:${_pageCache.containsKey(1)}, 2:${_pageCache.containsKey(2)}, 3:${_pageCache.containsKey(3)}]');
      print('[MainNavigation] 構建 IndexedStack，頁面緩存狀態: [0:${_pageCache.containsKey(0)}, 1:${_pageCache.containsKey(1)}, 2:${_pageCache.containsKey(2)}, 3:${_pageCache.containsKey(3)}]');
      
      // 構建 IndexedStack 的子元素列表
      // 重要：只有已創建的頁面才會被放入，未創建的頁面使用佔位符
      // 這樣可以確保檔案管理頁面只有在用戶切換到它時才會被創建
      debugPrint('[MainNavigation] 開始構建 children 列表');
      print('[MainNavigation] 開始構建 children 列表');
      
      // 使用延遲構建，避免阻塞主線程
      final children = <Widget>[];
      for (int i = 0; i < 4; i++) {
        try {
          if (_pageCache.containsKey(i)) {
            debugPrint('[MainNavigation] 頁面 $i 已創建，使用緩存的頁面');
            print('[MainNavigation] 頁面 $i 已創建，使用緩存的頁面');
            children.add(_pageCache[i]!);
          } else {
            debugPrint('[MainNavigation] 頁面 $i 未創建，使用佔位符');
            print('[MainNavigation] 頁面 $i 未創建，使用佔位符');
            children.add(_getPlaceholderPage(i));
          }
        } catch (e) {
          debugPrint('[MainNavigation] 構建頁面 $i 時出錯: $e');
          print('[MainNavigation] 構建頁面 $i 時出錯: $e');
          children.add(_getPlaceholderPage(i));
        }
      }
      
      debugPrint('[MainNavigation] IndexedStack children 構建完成，children 數量: ${children.length}');
      print('[MainNavigation] IndexedStack children 構建完成，children 數量: ${children.length}');
      debugPrint('[MainNavigation] 開始返回 Scaffold');
      print('[MainNavigation] 開始返回 Scaffold');
      
      // 使用 IndexedStack 確保只有當前頁面會被構建和顯示
      // 這樣可以防止後台頁面執行不必要的操作
      return Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: children,
        ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: _handlePageChange,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam),
            label: '實時影像',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: '檔案管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '參數設定',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.wifi),
            label: 'Wi-Fi 連接',
          ),
        ],
      ),
    );
    } catch (e, stackTrace) {
      developer.log('[MainNavigation] build() 出錯: $e', name: 'MainNavigation', error: e, stackTrace: stackTrace);
      print('[MainNavigation] build() 出錯: $e');
      print('[MainNavigation] 堆棧: $stackTrace');
      // 返回一個簡單的錯誤頁面，避免完全卡住
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('頁面構建錯誤', style: TextStyle(fontSize: 18)),
              SizedBox(height: 8),
              Text('$e', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: _handlePageChange,
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.videocam), label: '實時影像'),
            BottomNavigationBarItem(icon: Icon(Icons.folder), label: '檔案管理'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '參數設定'),
            BottomNavigationBarItem(icon: Icon(Icons.wifi), label: 'Wi-Fi 連接'),
          ],
        ),
      );
    }
  }
}


