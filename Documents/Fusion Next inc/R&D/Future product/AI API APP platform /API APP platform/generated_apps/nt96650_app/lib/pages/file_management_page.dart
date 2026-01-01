import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nt96650_app/services/device_service.dart';
import 'package:nt96650_app/pages/playback_page.dart';
import 'package:nt96650_app/state/app_state.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 檔案類型篩選
enum FileFilterType {
  all,
  photo,
  video,
}

/// 排序方式
enum SortType {
  dateDesc,  // 日期降序（最新的在前）
  dateAsc,   // 日期升序
  sizeDesc,  // 大小降序
  sizeAsc,   // 大小升序
  nameAsc,   // 名稱升序
  nameDesc,  // 名稱降序
}

/// 2. 檔案瀏覽以及管理
class FileManagementPage extends StatefulWidget {
  const FileManagementPage({Key? key}) : super(key: key);
  
  @override
  FileManagementPageState createState() => FileManagementPageState();
}

class FileManagementPageState extends State<FileManagementPage> {
  final DeviceService _deviceService = DeviceService();
  List<Map<String, dynamic>> _fileList = [];
  List<Map<String, dynamic>> _filteredFileList = [];
  bool _isLoading = false;
  Map<String, Uint8List?> _thumbnails = {}; // 緩存縮圖
  Map<String, bool> _loadingThumbnails = {}; // 正在載入的縮圖
  Set<String> _failedThumbnails = {}; // 記錄載入失敗的縮圖，避免重複嘗試
  Set<String> _requestedThumbnails = {}; // 記錄已經請求加載的縮圖，避免重複註冊 callback
  int _maxConcurrentThumbnails = 3; // 最多同時載入的縮圖數量
  int _currentLoadingThumbnails = 0; // 當前正在載入的縮圖數量
  static const int _maxThumbnailCacheSize = 50; // 最多緩存的縮圖數量
  
  // 篩選和排序
  FileFilterType _filterType = FileFilterType.all;
  SortType _sortType = SortType.dateDesc;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  // 批量選擇
  bool _isSelectionMode = false;
  Set<String> _selectedFiles = {};
  
  // 磁盤空間信息
  String? _freeSpace;
  bool _isLoadingSpace = false;
  
  bool _isInitialized = false;
  bool _hasLoadedData = false;
  bool _isPageVisible = false;
  
  @override
  void initState() {
    developer.log('[FileManagement] initState() 開始', name: 'FileManagement');
    print('[FileManagement] initState() 開始');
    super.initState();
    
    // 熱重載時重置狀態，確保頁面可以重新初始化
    // 這可以防止熱重載時使用舊的狀態導致問題
    _isPageVisible = false;
    _hasLoadedData = false;
    _isInitialized = false;
    developer.log('[FileManagement] 已重置狀態標記（熱重載安全）', name: 'FileManagement');
    print('[FileManagement] 已重置狀態標記（熱重載安全）');
    
    _searchController.addListener(_onSearchChanged);
    // 不在 initState 中載入數據，等待頁面真正可見時再載入
    // 確保在 initState 中不執行任何網路操作
    // 所有數據載入都必須通過 onPageVisible() 方法，並且會檢查連線狀態
    // 重要：不要在 initState 中使用 addPostFrameCallback 或任何延遲操作
    // 這樣可以確保頁面在創建時不會立即執行任何操作
    developer.log('[FileManagement] initState() 完成，_isPageVisible=$_isPageVisible, _hasLoadedData=$_hasLoadedData', name: 'FileManagement');
    print('[FileManagement] initState() 完成，_isPageVisible=$_isPageVisible, _hasLoadedData=$_hasLoadedData');
  }
  
  /// 當頁面變為可見時調用此方法來載入數據
  /// 重要：這個方法只應該在用戶切換到檔案管理頁面時被 MainNavigationPage 調用
  void onPageVisible() {
    developer.log('[FileManagement] onPageVisible() 被調用', name: 'FileManagement');
    print('[FileManagement] onPageVisible() 被調用');
    
    if (_isPageVisible) {
      developer.log('[FileManagement] 已經處理過，跳過', name: 'FileManagement');
      print('[FileManagement] 已經處理過，跳過');
      return; // 已經處理過，避免重複調用
    }
    
    _isPageVisible = true;
    
    // 檢查連線狀態，只有在已連線時才載入數據
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      // 未連線，不執行讀取操作
      developer.log('[FileManagement] 未連線，跳過載入檔案操作', name: 'FileManagement');
      print('[FileManagement] 未連線，跳過載入檔案操作');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingSpace = false;
        });
      }
      return;
    }
    
    if (!_hasLoadedData && mounted) {
      developer.log('[FileManagement] 開始載入數據', name: 'FileManagement');
      print('[FileManagement] 開始載入數據');
      _hasLoadedData = true;
      // 確保設備 IP 已設置
      _initializeDevice();
      // 延遲一小段時間再載入，確保頁面完全可見
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          // 再次檢查連線狀態，確保在延遲期間連線狀態沒有改變
          final currentState = Provider.of<AppState>(context, listen: false);
          if (currentState.isConnected && currentState.deviceIp != null) {
            developer.log('[FileManagement] 執行載入檔案列表和磁盤空間', name: 'FileManagement');
            print('[FileManagement] 執行載入檔案列表和磁盤空間');
            _loadFileList();
            _loadDiskSpace();
          } else {
            developer.log('[FileManagement] 延遲後檢查發現未連線，跳過載入', name: 'FileManagement');
            print('[FileManagement] 延遲後檢查發現未連線，跳過載入');
          }
        }
      });
    } else {
      developer.log('[FileManagement] 數據已載入，跳過', name: 'FileManagement');
      print('[FileManagement] 數據已載入，跳過');
    }
  }
  
  /// 初始化設備連接
  void _initializeDevice() {
    try {
      final state = Provider.of<AppState>(context, listen: false);
      if (state.deviceIp != null) {
        _deviceService.setDeviceIp(state.deviceIp!);
      }
    } catch (e) {
      print('初始化設備 IP 錯誤：$e');
    }
  }
  
  @override
  void dispose() {
    developer.log('[FileManagement] dispose() 開始', name: 'FileManagement');
    print('[FileManagement] dispose() 開始');
    
    // 清理資源
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    
    // 清理縮圖緩存和失敗記錄
    _thumbnails.clear();
    _loadingThumbnails.clear();
    _failedThumbnails.clear();
    _requestedThumbnails.clear();
    _currentLoadingThumbnails = 0;
    
    // 重置狀態標記（熱重載安全）
    _isPageVisible = false;
    _hasLoadedData = false;
    _isInitialized = false;
    
    developer.log('[FileManagement] dispose() 完成', name: 'FileManagement');
    print('[FileManagement] dispose() 完成');
    super.dispose();
  }
  
  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _searchQuery = _searchController.text;
      _applyFilters();
    });
  }
  
  Future<void> _loadFileList() async {
    developer.log('[FileManagement] _loadFileList() 被調用', name: 'FileManagement');
    print('[FileManagement] _loadFileList() 被調用');
    
    if (!mounted) {
      developer.log('[FileManagement] _loadFileList()：頁面未掛載，跳過', name: 'FileManagement');
      print('[FileManagement] _loadFileList()：頁面未掛載，跳過');
      return;
    }
    
    // 檢查連線狀態，未連線時不執行讀取操作
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      developer.log('[FileManagement] 載入檔案列表：未連線，跳過操作', name: 'FileManagement');
      print('[FileManagement] 載入檔案列表：未連線，跳過操作');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    
    // 檢查頁面是否可見，只有在可見時才執行讀取操作
    if (!_isPageVisible) {
      developer.log('[FileManagement] 載入檔案列表：頁面不可見，跳過操作', name: 'FileManagement');
      print('[FileManagement] 載入檔案列表：頁面不可見，跳過操作');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    
    developer.log('[FileManagement] 載入檔案列表：開始執行', name: 'FileManagement');
    print('[FileManagement] 載入檔案列表：開始執行');
    setState(() => _isLoading = true);
    
    try {
      final result = await _deviceService.filelist();
      
      if (!mounted) return;
      
      if (result['status'] == 'success') {
        // 從解析結果中獲取文件列表
        final fileList = result['fileList'] as List<dynamic>?;
        final fileListLength = fileList?.length ?? 0;
        print('[FileManagement] 解析到的文件列表長度: $fileListLength');
        if (fileList != null && fileList.isNotEmpty) {
          print('[FileManagement] 文件列表內容:');
          for (int i = 0; i < fileList.length; i++) {
            final file = fileList[i];
            print('[FileManagement]   文件 $i: ${file['name'] ?? '無名稱'}, 路徑: ${file['path'] ?? file['fullPath'] ?? '無路徑'}');
          }
        }
        
        setState(() {
          _fileList = fileList?.cast<Map<String, dynamic>>() ?? [];
          // 清除舊的縮圖緩存和失敗記錄
          _thumbnails.clear();
          _loadingThumbnails.clear();
          _failedThumbnails.clear();
          _requestedThumbnails.clear(); // 清除請求記錄
          _currentLoadingThumbnails = 0; // 重置載入計數
          _selectedFiles.clear();
          _isSelectionMode = false;
        });
        
        print('[FileManagement] 設置 _fileList 長度: ${_fileList.length}');
        _applyFilters();
        print('[FileManagement] 過濾後 _filteredFileList 長度: ${_filteredFileList.length}');
        
        if (mounted) {
          if (_fileList.isEmpty) {
            // 空列表是正常情況，不需要顯示錯誤訊息
            // 只在使用者手動刷新時才顯示提示
            print('[FileManagement] 文件列表為空');
          } else {
            _showMessage('已載入 ${_fileList.length} 個文件');
          }
        }
      } else {
        if (mounted) {
          final errorMsg = result['message'] ?? '未知錯誤';
          print('載入文件列表失敗：$errorMsg');
          
          // 對於文件列表，任何解析錯誤都視為空列表，不顯示錯誤訊息
          // 因為空列表是正常情況（設備可能沒有文件）
          setState(() {
            _fileList = [];
            _thumbnails.clear();
            _loadingThumbnails.clear();
            _failedThumbnails.clear();
            _requestedThumbnails.clear();
            _currentLoadingThumbnails = 0; // 重置載入計數
            _selectedFiles.clear();
            _isSelectionMode = false;
          });
          _applyFilters();
          // 不顯示錯誤訊息，因為空列表是正常情況
          // 只有在真正的網路連接錯誤時才顯示錯誤（但這應該在 _sendCommand 中處理）
        }
      }
    } catch (e) {
      if (mounted) {
        print('載入文件列表異常：$e');
        _showMessage('載入文件列表錯誤：$e\n請檢查網絡連接');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadDiskSpace() async {
    if (!mounted) return;
    
    // 檢查連線狀態，未連線時不執行讀取操作
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      print('載入磁盤空間：未連線，跳過操作');
      if (mounted) {
        setState(() => _isLoadingSpace = false);
      }
      return;
    }
    
    setState(() => _isLoadingSpace = true);
    
    try {
      final result = await _deviceService.getdiskfreespace();
      
      if (!mounted) return;
      
      if (result['status'] == 'success') {
        final freeSpace = result['freeSpace'];
        if (freeSpace != null && mounted) {
          setState(() {
            _freeSpace = _formatBytes(int.tryParse(freeSpace.toString()) ?? 0);
          });
        }
      } else {
        print('載入磁盤空間失敗：${result['message']}');
      }
    } catch (e) {
      print('載入磁盤空間錯誤：$e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSpace = false);
      }
    }
  }
  
  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '$bytes B';
    }
  }
  
  void _applyFilters() {
    if (!mounted) return;
    
    List<Map<String, dynamic>> filtered = List.from(_fileList);
    
    // 應用類型篩選
    if (_filterType != FileFilterType.all) {
      filtered = filtered.where((file) {
        final fileName = file['name'] ?? '';
        final fileType = file['type'] ?? _getFileTypeFromName(fileName);
        
        if (_filterType == FileFilterType.photo) {
          return fileType == 'photo';
        } else if (_filterType == FileFilterType.video) {
          return fileType == 'video';
        }
        return true;
      }).toList();
    }
    
    // 應用搜索篩選
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((file) {
        final fileName = (file['name'] ?? '').toLowerCase();
        return fileName.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    
    // 應用排序
    if (filtered.isNotEmpty) {
      filtered.sort((a, b) {
        switch (_sortType) {
          case SortType.dateDesc:
          case SortType.dateAsc:
            final dateA = _parseDateTime(a['date'], a['time']);
            final dateB = _parseDateTime(b['date'], b['time']);
            final comparison = dateA.compareTo(dateB);
            return _sortType == SortType.dateDesc ? -comparison : comparison;
            
          case SortType.sizeDesc:
          case SortType.sizeAsc:
            final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
            final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;
            final comparison = sizeA.compareTo(sizeB);
            return _sortType == SortType.sizeDesc ? -comparison : comparison;
            
          case SortType.nameAsc:
          case SortType.nameDesc:
            final nameA = (a['name'] ?? '').toLowerCase();
            final nameB = (b['name'] ?? '').toLowerCase();
            final comparison = nameA.compareTo(nameB);
            return _sortType == SortType.nameDesc ? -comparison : comparison;
        }
      });
    }
    
    if (mounted) {
      setState(() {
        _filteredFileList = filtered;
      });
    }
  }
  
  DateTime _parseDateTime(String? date, String? time) {
    try {
      if (date != null && date.isNotEmpty) {
        // 嘗試解析日期格式，例如 "2014-05-06" 或 "2014_05_06"
        String dateStr = date.replaceAll('_', '-');
        String timeStr = time ?? '00:00:00';
        
        // 解析日期時間
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          
          final timeParts = timeStr.split(':');
          final hour = timeParts.length > 0 ? int.tryParse(timeParts[0]) ?? 0 : 0;
          final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
          final second = timeParts.length > 2 ? int.tryParse(timeParts[2]) ?? 0 : 0;
          
          return DateTime(year, month, day, hour, minute, second);
        }
      }
    } catch (e) {
      print('解析日期時間錯誤：$e');
    }
    return DateTime(1970); // 返回默認日期
  }
  
  Future<void> _deleteFile(String filePath) async {
    // 檢查連線狀態
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      _showMessage('未連線，無法刪除文件');
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('確認刪除'),
        content: Text('確定要刪除這個文件嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final result = await _deviceService.deleteonefile(filePath);
      
      if (result['status'] == 'success') {
        _showMessage('文件已刪除');
        _loadFileList();
        _loadDiskSpace();
      } else {
        _showMessage('刪除失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;
    
    // 檢查連線狀態
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      _showMessage('未連線，無法刪除文件');
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('確認刪除'),
        content: Text('確定要刪除選中的 ${_selectedFiles.length} 個文件嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    int successCount = 0;
    int failCount = 0;
    
    for (final filePath in _selectedFiles) {
      try {
        final result = await _deviceService.deleteonefile(filePath);
        if (result['status'] == 'success') {
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        failCount++;
      }
    }
    
    setState(() {
      _selectedFiles.clear();
      _isSelectionMode = false;
    });
    
    _loadFileList();
    _loadDiskSpace();
    
    if (failCount == 0) {
      _showMessage('成功刪除 $successCount 個文件');
    } else {
      _showMessage('成功刪除 $successCount 個文件，失敗 $failCount 個');
    }
  }
  
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedFiles.clear();
      }
    });
  }
  
  void _toggleFileSelection(String filePath) {
    setState(() {
      if (_selectedFiles.contains(filePath)) {
        _selectedFiles.remove(filePath);
      } else {
        _selectedFiles.add(filePath);
      }
    });
  }
  
  void _selectAllFiles() {
    setState(() {
      _selectedFiles = _filteredFileList
          .map((file) => (file['path'] ?? file['fullPath'] ?? '').toString())
          .where((path) => path.isNotEmpty)
          .toSet();
    });
  }
  
  void _deselectAllFiles() {
    setState(() {
      _selectedFiles.clear();
    });
  }
  
  Future<void> _deleteAllFiles() async {
    // 檢查連線狀態
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      _showMessage('未連線，無法刪除文件');
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('確認刪除所有文件'),
        content: Text('確定要刪除所有文件嗎？此操作無法復原！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('刪除全部', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final result = await _deviceService.deleteall();
      
      if (result['status'] == 'success') {
        _showMessage('所有文件已刪除');
        _loadFileList();
        _loadDiskSpace();
      } else {
        _showMessage('刪除失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  Future<void> _downloadFile(String filePath, String fileName) async {
    // 檢查連線狀態
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      _showMessage('未連線，無法下載文件');
      return;
    }
    
    // 如果是視頻文件，可以選擇播放或下載
    final isVideo = fileName.toLowerCase().endsWith('.mov') || 
                    fileName.toLowerCase().endsWith('.mp4') ||
                    fileName.toLowerCase().endsWith('.avi');
    
    if (isVideo) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('選擇操作'),
          content: Text('要播放還是下載這個文件？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'play'),
              child: Text('播放'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'download'),
              child: Text('下載'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
          ],
        ),
      );
      
      if (action == 'play') {
        // 導航到播放頁面
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaybackPage(fileName: fileName, filePath: filePath),
          ),
        );
        return;
      } else if (action == 'download') {
        await _performDownload(filePath, fileName);
        return;
      }
    } else {
      await _performDownload(filePath, fileName);
    }
  }
  
  Future<void> _performDownload(String filePath, String fileName) async {
    try {
      _showMessage('開始下載：$fileName');
      
      String? downloadUrl;
      
      // 首先嘗試使用 getdownloadurl API (cmd=3025) 獲取下載 URL
      try {
        print('嘗試使用 getdownloadurl API 獲取下載 URL...');
        final urlResult = await _deviceService.getdownloadurl(filePath);
        print('getdownloadurl 結果: $urlResult');
        
        if (urlResult['status'] == 'success' && urlResult['url'] != null) {
          downloadUrl = urlResult['url'] as String?;
          print('從 API 獲取下載 URL: $downloadUrl');
        }
      } catch (e) {
        print('使用 getdownloadurl API 失敗: $e，將使用直接構建的 URL');
      }
      
      // 如果 API 沒有返回 URL，使用直接構建的方式
      if (downloadUrl == null || downloadUrl.isEmpty) {
        downloadUrl = _deviceService.buildDownloadUrl(filePath);
        print('使用直接構建的下載 URL: $downloadUrl');
      }
      
      print('最終下載 URL: $downloadUrl');
      print('原始文件路徑: $filePath');
      
      // 下載文件 - 使用流式處理避免內存溢出
      final request = http.Request('GET', Uri.parse(downloadUrl!));
      final streamedResponse = await http.Client().send(request).timeout(
        Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('下載超時'),
      );
      
      print('下載響應狀態碼: ${streamedResponse.statusCode}');
      print('下載響應 Content-Type: ${streamedResponse.headers['content-type']}');
      print('下載響應 Content-Length: ${streamedResponse.headers['content-length']}');
      
      if (streamedResponse.statusCode == 200) {
        final contentLength = streamedResponse.headers['content-length'];
        if (contentLength != null) {
          final size = int.tryParse(contentLength);
          if (size != null && size < 100) {
            // 如果文件大小異常小，可能是錯誤響應
            final response = await http.Response.fromStream(streamedResponse);
            final responseText = response.body;
            print('錯誤：下載響應異常小，內容: $responseText');
            _showMessage('下載失敗：服務器返回錯誤響應（${size} 字節）\n內容: ${responseText.substring(0, responseText.length > 100 ? 100 : responseText.length)}');
            return;
          }
        }
        // 獲取下載目錄
        Directory downloadDir;
        String saveLocation;
        
        if (Platform.isAndroid) {
          // Android 上嘗試使用公共 Downloads 目錄
          // 對於 Android 10+，如果無法訪問公共目錄，則使用應用外部存儲目錄
          try {
            // 首先嘗試獲取外部存儲目錄，然後嘗試訪問公共 Downloads
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              // 嘗試訪問公共 Downloads 目錄
              // externalDir.path 通常是 /storage/emulated/0/Android/data/包名/files
              // 公共 Downloads 在 /storage/emulated/0/Download
              final publicDownloadsPath = '/storage/emulated/0/Download';
              final publicDownloadsDir = Directory(publicDownloadsPath);
              
              // 檢查是否可以訪問（雖然 Android 10+ 可能無法直接訪問，但我們嘗試一下）
              try {
                if (await publicDownloadsDir.exists() || 
                    await publicDownloadsDir.parent.exists()) {
                  // 嘗試創建目錄（可能會失敗，但不影響）
                  try {
                    await publicDownloadsDir.create(recursive: true);
                    downloadDir = publicDownloadsDir;
                    saveLocation = 'Download 資料夾（公共目錄）';
                    print('使用公共 Downloads 目錄: $publicDownloadsPath');
                  } catch (e) {
                    print('無法創建公共 Downloads 目錄: $e，使用應用目錄');
                    // 如果無法使用公共目錄，使用應用目錄
                    downloadDir = Directory('${externalDir.path}/Downloads');
                    saveLocation = 'Android/data/com.example.nt96650_app/files/Downloads';
                  }
                } else {
                  // 使用應用目錄
                  downloadDir = Directory('${externalDir.path}/Downloads');
                  saveLocation = 'Android/data/com.example.nt96650_app/files/Downloads';
                }
              } catch (e) {
                // 如果無法訪問公共目錄，使用應用目錄
                print('無法訪問公共 Downloads 目錄: $e，使用應用目錄');
                downloadDir = Directory('${externalDir.path}/Downloads');
                saveLocation = 'Android/data/com.example.nt96650_app/files/Downloads';
              }
            } else {
              // 如果無法獲取外部存儲，使用應用文檔目錄
              final appDocDir = await getApplicationDocumentsDirectory();
              downloadDir = Directory('${appDocDir.path}/Downloads');
              saveLocation = '應用文檔/Downloads';
            }
          } catch (e) {
            // 出錯時使用應用文檔目錄
            print('獲取存儲目錄失敗：$e');
            final appDocDir = await getApplicationDocumentsDirectory();
            downloadDir = Directory('${appDocDir.path}/Downloads');
            saveLocation = '應用文檔/Downloads';
          }
        } else if (Platform.isIOS) {
          downloadDir = await getApplicationDocumentsDirectory();
          saveLocation = '應用文檔';
        } else {
          downloadDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
          saveLocation = downloadDir.path;
        }
        
        // 確保目錄存在
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        
        // 保存文件 - 使用流式寫入避免內存溢出
        final file = File('${downloadDir.path}/$fileName');
        final sink = file.openWrite();
        
        try {
          int totalBytes = 0;
          await for (final chunk in streamedResponse.stream) {
            sink.add(chunk);
            totalBytes += chunk.length;
            // 可以在此處添加進度更新（如果需要）
          }
          await sink.close();
          print('文件下載完成，總大小: $totalBytes 字節');
        } catch (e) {
          await sink.close();
          // 如果下載失敗，刪除部分下載的文件
          if (await file.exists()) {
            await file.delete();
          }
          rethrow;
        }
        
        final fileSize = await file.length();
        String sizeText = '';
        if (fileSize > 1024 * 1024) {
          sizeText = '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
        } else if (fileSize > 1024) {
          sizeText = '${(fileSize / 1024).toStringAsFixed(2)} KB';
        } else {
          sizeText = '$fileSize B';
        }
        
        // 顯示下載完成對話框
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('下載完成'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('文件名：$fileName', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 12),
                    Text('文件大小：$sizeText'),
                    SizedBox(height: 12),
                    if (Platform.isAndroid) ...[
                      Text('保存位置：', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '完整路徑：',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            SelectableText(
                              file.path,
                              style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                            ),
                            SizedBox(height: 12),
                            Text(
                              '如何在文件管理器中找到：',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '1. 打開手機的「文件管理器」應用\n'
                              '2. 進入「Android」資料夾\n'
                              '3. 進入「data」資料夾\n'
                              '4. 找到並進入「com.example.nt96650_app」資料夾\n'
                              '5. 進入「files」資料夾\n'
                              '6. 進入「Downloads」資料夾\n'
                              '7. 即可看到下載的文件',
                              style: TextStyle(fontSize: 11),
                            ),
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '注意：某些文件管理器可能隱藏 Android/data 目錄，請使用系統文件管理器或允許顯示隱藏文件',
                                      style: TextStyle(fontSize: 10, color: Colors.orange.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text('保存位置：$saveLocation'),
                      SizedBox(height: 8),
                      SelectableText(
                        file.path,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('確定'),
                ),
              ],
            ),
          );
        }
      } else {
        _showMessage('下載失敗：HTTP ${streamedResponse.statusCode}');
      }
    } catch (e) {
      _showMessage('下載錯誤：$e');
    }
  }
  
  Future<void> _loadThumbnail(String filePath, String fileName, {bool forceRetry = false}) async {
    // 如果已經在載入，則跳過
    if (_loadingThumbnails[filePath] == true) {
      return;
    }
    
    // 如果已經有緩存，則跳過（除非強制重試）
    if (_thumbnails[filePath] != null && !forceRetry) {
      return;
    }
    
    // 如果已經載入失敗，且不是強制重試，則跳過
    // 強制重試時（例如用戶點擊"查看縮圖"），允許重新嘗試
    if (_failedThumbnails.contains(filePath) && !forceRetry) {
      return;
    }
    
    // 檢查同時載入的縮圖數量，避免內存溢出（強制重試時跳過此檢查，允許優先載入）
    if (_currentLoadingThumbnails >= _maxConcurrentThumbnails && !forceRetry) {
      print('載入縮圖：已達到最大並發數量（$_maxConcurrentThumbnails），跳過 $filePath');
      _requestedThumbnails.remove(filePath); // 移除請求標記，允許稍後重試
      return;
    }
    
    // 檢查連線狀態，未連線時不執行讀取操作
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      print('載入縮圖：未連線，跳過操作');
      _requestedThumbnails.remove(filePath); // 移除請求標記，允許稍後重試
      return;
    }
    
    // 檢查頁面是否可見，只有在可見時才載入縮圖（強制重試時跳過此檢查）
    if (!_isPageVisible && !forceRetry) {
      print('載入縮圖：頁面不可見，跳過操作');
      _requestedThumbnails.remove(filePath); // 移除請求標記，允許稍後重試
      return;
    }
    
    // 增加當前載入計數
    _currentLoadingThumbnails++;
    setState(() {
      _loadingThumbnails[filePath] = true;
    });
    
    try {
      // 根據檔案類型選擇不同的 API
      // 照片使用 getthumbnail (cmd=4001)
      // 影片使用 getscreennail (cmd=4002)
      final fileType = _getFileTypeFromName(fileName);
      print('載入縮圖：檔案類型=$fileType, 文件名=$fileName, 路徑=$filePath');
      final result = fileType == 'video' 
          ? await _deviceService.getscreennail(filePath)
          : await _deviceService.getthumbnail(filePath);
      print('載入縮圖結果：status=${result['status']}, 是否有圖片數據=${result['imageData'] != null}');
      
      if (!mounted) return;
      
      if (result['status'] == 'success' && result['imageData'] != null) {
        try {
          // 驗證圖片數據是否有效
          final imageData = result['imageData'] as Uint8List;
          if (imageData.isNotEmpty) {
            // 檢查緩存大小，如果超過限制則清理舊的縮圖
            if (_thumbnails.length >= _maxThumbnailCacheSize) {
              _cleanupThumbnailCache();
            }
            
            setState(() {
              _thumbnails[filePath] = imageData;
              _loadingThumbnails[filePath] = false;
            });
          } else {
            setState(() {
              _loadingThumbnails[filePath] = false;
            });
          }
        } catch (e) {
          print('處理縮圖數據錯誤：$e');
          setState(() {
            _loadingThumbnails[filePath] = false;
            // 只有在非強制重試時才標記為失敗，允許用戶手動重試
            if (!forceRetry) {
              _failedThumbnails.add(filePath);
            }
          });
        }
      } else {
        // 載入失敗，記錄錯誤信息
        final errorMessage = result['message'] ?? '未知錯誤';
        print('載入縮圖失敗：$errorMessage (filePath: $filePath)');
        setState(() {
          _loadingThumbnails[filePath] = false;
          // 只有在非強制重試時才標記為失敗，允許用戶手動重試
          if (!forceRetry) {
            _failedThumbnails.add(filePath);
          }
        });
      }
    } catch (e) {
      print('載入縮圖錯誤：$e (filePath: $filePath)');
      if (mounted) {
        setState(() {
          _loadingThumbnails[filePath] = false;
          // 只有在非強制重試時才標記為失敗，允許用戶手動重試
          if (!forceRetry) {
            _failedThumbnails.add(filePath);
          }
        });
      }
    } finally {
      // 減少當前載入計數
      _currentLoadingThumbnails = (_currentLoadingThumbnails - 1).clamp(0, _maxConcurrentThumbnails);
    }
  }
  
  /// 清理縮圖緩存，保留最新的縮圖
  void _cleanupThumbnailCache() {
    if (_thumbnails.length <= _maxThumbnailCacheSize) {
      return;
    }
    
    // 簡單策略：清理一半的緩存（保留最新的）
    final keysToRemove = _thumbnails.keys.take(_thumbnails.length - (_maxThumbnailCacheSize ~/ 2)).toList();
    for (final key in keysToRemove) {
      _thumbnails.remove(key);
    }
    print('清理縮圖緩存：移除了 ${keysToRemove.length} 個縮圖');
  }
  
  Future<void> _showThumbnailDialog(String filePath, String fileName) async {
    // 檢查連線狀態
    final state = Provider.of<AppState>(context, listen: false);
    if (!state.isConnected || state.deviceIp == null) {
      _showMessage('未連線，無法載入縮圖');
      return;
    }
    
    // 如果已經有緩存的縮圖，直接顯示
    if (_thumbnails[filePath] != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(fileName),
          content: Image.memory(_thumbnails[filePath]!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('關閉'),
            ),
          ],
        ),
      );
      return;
    }
    
    // 顯示對話框，使用 StatefulBuilder 來管理狀態
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return _ThumbnailDialogWidget(
          filePath: filePath,
          fileName: fileName,
          loadThumbnail: (filePath, fileName) => _loadThumbnail(filePath, fileName, forceRetry: true),
          getThumbnail: (filePath) => _thumbnails[filePath],
        );
      },
    );
  }
  
  Widget _buildThumbnail(String filePath, String fileName, {int? index}) {
    // 如果已經有緩存的縮圖，直接顯示
    if (_thumbnails[filePath] != null) {
      return Image.memory(
        _thumbnails[filePath]!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Icon(_getFileIcon(_getFileTypeFromName(fileName)));
        },
      );
    }
    
    // 如果正在載入，顯示載入指示器
    if (_loadingThumbnails[filePath] == true) {
      return SizedBox(
        width: 60,
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    
    // 只載入前 20 個可見項目的縮圖（第一頁）
    // 如果 index 為 null 或 index >= 20，不載入縮圖，直接顯示圖標
    if (index != null && index >= 20) {
      return Icon(_getFileIcon(_getFileTypeFromName(fileName)));
    }
    
    // 檢查是否已經載入失敗，如果是則不再嘗試
    if (_failedThumbnails.contains(filePath)) {
      return Icon(_getFileIcon(_getFileTypeFromName(fileName)));
    }
    
    // 如果已經請求過但還沒有開始載入，也直接顯示圖標（避免重複註冊 callback）
    if (_requestedThumbnails.contains(filePath)) {
      return Icon(_getFileIcon(_getFileTypeFromName(fileName)));
    }
    
    // 只有在頁面可見、已連線、且 index < 20 時才載入縮圖
    if (_isPageVisible && index != null && index < 20) {
      final state = Provider.of<AppState>(context, listen: false);
      if (state.isConnected && state.deviceIp != null) {
        // 確保還沒有開始載入、沒有緩存、也沒有失敗，且沒有已經請求過，避免重複請求
        // 重要：在註冊 callback 之前就標記為已請求，防止重複
        if (!_loadingThumbnails.containsKey(filePath) && 
            _loadingThumbnails[filePath] != true) {
          // 立即標記為已請求，避免重複註冊 callback（即使還沒開始載入）
          _requestedThumbnails.add(filePath);
          
          // 延遲載入，避免在同一 frame 中發起太多請求
          // 使用 addPostFrameCallback 確保只在 frame 後執行一次
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && 
                _thumbnails[filePath] == null &&
                !_failedThumbnails.contains(filePath)) {
              _loadThumbnail(filePath, fileName);
            } else {
              // 如果條件不滿足，移除請求標記
              _requestedThumbnails.remove(filePath);
            }
          });
        }
      }
    }
    
    return Icon(_getFileIcon(_getFileTypeFromName(fileName)));
  }
  
  String? _getFileTypeFromName(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.jpg') || 
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png')) {
      return 'photo';
    } else if (lowerName.endsWith('.mov') ||
               lowerName.endsWith('.mp4') ||
               lowerName.endsWith('.avi') ||
               lowerName.endsWith('.ts')) {  // 添加 .ts 支持
      return 'video';
    }
    return null;
  }
  
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    developer.log('[FileManagement] build() 被調用，_isPageVisible=$_isPageVisible, _hasLoadedData=$_hasLoadedData, _isLoading=$_isLoading', name: 'FileManagement');
    print('[FileManagement] build() 被調用，_isPageVisible=$_isPageVisible, _hasLoadedData=$_hasLoadedData, _isLoading=$_isLoading');
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('已選擇 ${_selectedFiles.length} 個文件')
            : Text('檔案管理'),
        actions: [
          // 連線狀態指示器
          Consumer<AppState>(
            builder: (context, state, _) {
              return Padding(
                padding: EdgeInsets.only(right: 8),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.isConnected ? Icons.wifi : Icons.wifi_off,
                        size: 20,
                        color: state.isConnected ? Colors.green : Colors.grey,
                      ),
                      SizedBox(width: 4),
                      Text(
                        state.isConnected ? '已連線' : '未連線',
                        style: TextStyle(
                          fontSize: 12,
                          color: state.isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_isSelectionMode) ...[
            IconButton(
              icon: Icon(_selectedFiles.length == _filteredFileList.length
                  ? Icons.deselect
                  : Icons.select_all),
              onPressed: _selectedFiles.length == _filteredFileList.length
                  ? _deselectAllFiles
                  : _selectAllFiles,
              tooltip: _selectedFiles.length == _filteredFileList.length
                  ? '取消全選'
                  : '全選',
            ),
            if (_selectedFiles.isNotEmpty)
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: _deleteSelectedFiles,
                tooltip: '刪除選中',
              ),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: _toggleSelectionMode,
              tooltip: '取消選擇模式',
            ),
          ] else ...[
            IconButton(
              icon: Icon(Icons.filter_list),
              onPressed: _showFilterDialog,
              tooltip: '篩選',
            ),
            IconButton(
              icon: Icon(Icons.sort),
              onPressed: _showSortDialog,
              tooltip: '排序',
            ),
            IconButton(
              icon: Icon(Icons.select_all),
              onPressed: _toggleSelectionMode,
              tooltip: '選擇模式',
            ),
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () {
                final state = Provider.of<AppState>(context, listen: false);
                if (state.isConnected && state.deviceIp != null) {
                  _loadFileList();
                  _loadDiskSpace();
                } else {
                  _showMessage('未連線，無法刷新檔案列表');
                }
              },
              tooltip: '刷新',
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: Text('刪除所有文件'),
                  onTap: () => Future.delayed(Duration.zero, _deleteAllFiles),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 搜索欄和磁盤空間信息
          Container(
            padding: EdgeInsets.all(8),
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                // 搜索欄
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索文件名...',
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                SizedBox(height: 8),
                // 磁盤空間信息
                if (_freeSpace != null || _isLoadingSpace)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storage, size: 16, color: Colors.grey),
                          SizedBox(width: 4),
                          Text(
                            '可用空間：${_freeSpace ?? "載入中..."}',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Text(
                        '共 ${_fileList.length} 個文件，顯示 ${_filteredFileList.length} 個',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // 檔案列表
          Expanded(
            child: Consumer<AppState>(
              builder: (context, state, _) {
                // 如果未連線，顯示連線提示
                if (!state.isConnected || state.deviceIp == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('未連接到設備', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 8),
                        Text('請先連接 Wi-Fi', style: TextStyle(color: Colors.grey)),
                        SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: Icon(Icons.wifi),
                          label: Text('前往 Wi-Fi 連接'),
                          onPressed: () {
                            // 導航到 Wi-Fi 連接頁面（索引 3）
                            // 注意：這裡需要通過父組件來切換頁面
                            // 由於我們在 MainNavigationPage 中，可以通過 Navigator 或回調來實現
                            // 暫時顯示提示
                            _showMessage('請使用底部導航切換到 Wi-Fi 連接頁面');
                          },
                        ),
                      ],
                    ),
                  );
                }
                
                // 已連線，顯示檔案列表
                return _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _filteredFileList.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async {
                          final state = Provider.of<AppState>(context, listen: false);
                          if (state.isConnected && state.deviceIp != null) {
                            await _loadFileList();
                            await _loadDiskSpace();
                          } else {
                            _showMessage('未連線，無法刷新');
                          }
                        },
                        child: SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: MediaQuery.of(context).size.height - 200,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_open, size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text(
                                    _fileList.isEmpty
                                        ? '沒有文件'
                                        : '沒有符合條件的文件',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () {
                                      final state = Provider.of<AppState>(context, listen: false);
                                      if (state.isConnected && state.deviceIp != null) {
                                        _loadFileList();
                                        _loadDiskSpace();
                                      } else {
                                        _showMessage('未連線，無法載入');
                                      }
                                    },
                                    child: Text('重新載入'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          final state = Provider.of<AppState>(context, listen: false);
                          if (state.isConnected && state.deviceIp != null) {
                            await _loadFileList();
                            await _loadDiskSpace();
                          } else {
                            _showMessage('未連線，無法刷新');
                          }
                        },
                        child: ListView.builder(
                          itemCount: _filteredFileList.length,
                          itemBuilder: (context, index) {
                            final file = _filteredFileList[index];
                            final fileName = file['name'] ?? '未知文件';
                            final filePath = file['path'] ?? file['fullPath'] ?? '';
                            final fileSize = file['size'];
                            final fileDate = file['date'];
                            final fileTime = file['time'];
                            final fileType = file['type'] ?? _getFileTypeFromName(fileName);
                            
                            // 格式化文件大小
                            String sizeText = '';
                            if (fileSize != null && fileSize.isNotEmpty) {
                              try {
                                final size = int.parse(fileSize);
                                if (size > 1024 * 1024) {
                                  sizeText = '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
                                } else if (size > 1024) {
                                  sizeText = '${(size / 1024).toStringAsFixed(2)} KB';
                                } else {
                                  sizeText = '$size B';
                                }
                              } catch (e) {
                                sizeText = fileSize;
                              }
                            }
                            
                            // 格式化日期時間
                            String dateTimeText = '';
                            if (fileDate != null && fileDate.isNotEmpty) {
                              dateTimeText = fileDate;
                              if (fileTime != null && fileTime.isNotEmpty) {
                                dateTimeText += ' $fileTime';
                              }
                            }
                            
                            final isSelected = _selectedFiles.contains(filePath);
                            
                            return Card(
                              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              color: isSelected
                                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                                  : null,
                              child: ListTile(
                                leading: _isSelectionMode
                                    ? Checkbox(
                                        value: isSelected,
                                        onChanged: (value) => _toggleFileSelection(filePath),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: _buildThumbnail(filePath, fileName, index: index),
                                      ),
                                title: Text(
                                  fileName,
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (sizeText.isNotEmpty) Text(sizeText),
                                    if (dateTimeText.isNotEmpty) Text(dateTimeText, style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                                trailing: _isSelectionMode
                                    ? null
                                    : PopupMenuButton(
                                        itemBuilder: (context) => [
                                          if (fileType == 'video')
                                            PopupMenuItem(
                                              child: Row(
                                                children: [
                                                  Icon(Icons.play_arrow, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('播放'),
                                                ],
                                              ),
                                              onTap: () => Future.delayed(
                                                Duration.zero,
                                                () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => PlaybackPage(fileName: fileName, filePath: filePath),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          PopupMenuItem(
                                            child: Row(
                                              children: [
                                                Icon(Icons.download, size: 20),
                                                SizedBox(width: 8),
                                                Text('下載'),
                                              ],
                                            ),
                                            onTap: () => Future.delayed(
                                              Duration.zero,
                                              () => _downloadFile(filePath, fileName),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            child: Row(
                                              children: [
                                                Icon(Icons.image, size: 20),
                                                SizedBox(width: 8),
                                                Text('查看縮圖'),
                                              ],
                                            ),
                                            onTap: () => Future.delayed(
                                              Duration.zero,
                                              () => _showThumbnailDialog(filePath, fileName),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete, size: 20, color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('刪除', style: TextStyle(color: Colors.red)),
                                              ],
                                            ),
                                            onTap: () => Future.delayed(
                                              Duration.zero,
                                              () => _deleteFile(filePath),
                                            ),
                                          ),
                                        ],
                                      ),
                                onTap: () {
                                  if (_isSelectionMode) {
                                    _toggleFileSelection(filePath);
                                  } else {
                                    if (fileType == 'video') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PlaybackPage(fileName: fileName, filePath: filePath),
                                        ),
                                      );
                                    } else {
                                      _downloadFile(filePath, fileName);
                                    }
                                  }
                                },
                                onLongPress: () {
                                  if (!_isSelectionMode) {
                                    _toggleSelectionMode();
                                    _toggleFileSelection(filePath);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('篩選文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<FileFilterType>(
              title: Text('全部'),
              value: FileFilterType.all,
              groupValue: _filterType,
              onChanged: (value) {
                setState(() {
                  _filterType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<FileFilterType>(
              title: Row(
                children: [
                  Icon(Icons.image, size: 20),
                  SizedBox(width: 8),
                  Text('照片'),
                ],
              ),
              value: FileFilterType.photo,
              groupValue: _filterType,
              onChanged: (value) {
                setState(() {
                  _filterType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<FileFilterType>(
              title: Row(
                children: [
                  Icon(Icons.video_library, size: 20),
                  SizedBox(width: 8),
                  Text('影片'),
                ],
              ),
              value: FileFilterType.video,
              groupValue: _filterType,
              onChanged: (value) {
                setState(() {
                  _filterType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('關閉'),
          ),
        ],
      ),
    );
  }
  
  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('排序方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<SortType>(
              title: Text('日期（最新在前）'),
              value: SortType.dateDesc,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() {
                  _sortType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortType>(
              title: Text('日期（最舊在前）'),
              value: SortType.dateAsc,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() {
                  _sortType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortType>(
              title: Text('大小（大在前）'),
              value: SortType.sizeDesc,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() {
                  _sortType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortType>(
              title: Text('大小（小在前）'),
              value: SortType.sizeAsc,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() {
                  _sortType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortType>(
              title: Text('名稱（A-Z）'),
              value: SortType.nameAsc,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() {
                  _sortType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortType>(
              title: Text('名稱（Z-A）'),
              value: SortType.nameDesc,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() {
                  _sortType = value!;
                });
                _applyFilters();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('關閉'),
          ),
        ],
      ),
    );
  }
  
  /// 縮圖對話框 Widget（用於管理載入狀態）
  static Widget _ThumbnailDialogWidget({
    required String filePath,
    required String fileName,
    required Future<void> Function(String, String) loadThumbnail,
    required Uint8List? Function(String) getThumbnail,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        final thumbnail = getThumbnail(filePath);
        
        // 如果已經有縮圖，直接顯示
        if (thumbnail != null) {
          return AlertDialog(
            title: Text(fileName),
            content: Image.memory(thumbnail),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('關閉'),
              ),
            ],
          );
        }
        
        // 如果沒有縮圖，開始載入
        bool isLoading = true;
        String? errorMessage;
        
        // 只在第一次構建時載入
        loadThumbnail(filePath, fileName).then((_) {
          if (context.mounted) {
            final newThumbnail = getThumbnail(filePath);
            if (newThumbnail != null) {
              setState(() {});
            } else {
              isLoading = false;
              errorMessage = '無法載入縮圖';
              setState(() {});
            }
          }
        }).catchError((error) {
          if (context.mounted) {
            isLoading = false;
            errorMessage = '載入錯誤：$error';
            setState(() {});
          }
        });
        
        // 如果正在載入，顯示載入指示器
        if (isLoading) {
          return AlertDialog(
            title: Text(fileName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在載入縮圖...', style: TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('關閉'),
              ),
            ],
          );
        }
        
        // 如果載入失敗，顯示錯誤和重試按鈕
        return AlertDialog(
          title: Text(fileName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red),
              SizedBox(height: 16),
              Text(errorMessage ?? '無法載入縮圖', style: TextStyle(color: Colors.red)),
              SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  isLoading = true;
                  errorMessage = null;
                  setState(() {});
                  loadThumbnail(filePath, fileName).then((_) {
                    if (context.mounted) {
                      final newThumbnail = getThumbnail(filePath);
                      if (newThumbnail != null) {
                        setState(() {});
                      } else {
                        isLoading = false;
                        errorMessage = '載入縮圖失敗';
                        setState(() {});
                      }
                    }
                  }).catchError((error) {
                    if (context.mounted) {
                      isLoading = false;
                      errorMessage = '載入錯誤：$error';
                      setState(() {});
                    }
                  });
                },
                child: Text('重試'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('關閉'),
            ),
          ],
        );
      },
    );
  }
  
  IconData _getFileIcon(String? type) {
    switch (type) {
      case 'photo':
        return Icons.image;
      case 'video':
        return Icons.video_library;
      default:
        return Icons.insert_drive_file;
    }
  }
}

