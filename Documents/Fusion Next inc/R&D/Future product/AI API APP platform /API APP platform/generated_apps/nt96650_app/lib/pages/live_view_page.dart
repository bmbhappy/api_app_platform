import 'dart:async';
import 'dart:ui' as ui;
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nt96650_app/services/device_service.dart';
import 'package:nt96650_app/state/app_state.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:nt96650_app/widgets/stream_viewer.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'dart:math' as math;

/// 日誌輸出輔助函數（確保在 Android logcat 中可見）
void _log(String tag, String message) {
  // 使用 developer.log 確保在 logcat 中可見
  developer.log(message, name: tag);
  // 同時使用 print 確保在控制台可見
  print('[$tag] $message');
}

/// 鏡頭模式枚舉
enum CameraMode {
  front,      // 前鏡頭
  rear,       // 後鏡頭
  both,       // 前後鏡頭同時
}

/// 1. 實時影像瀏覽及錄影照相控制
class LiveViewPage extends StatefulWidget {
  @override
  _LiveViewPageState createState() => _LiveViewPageState();
}

class _LiveViewPageState extends State<LiveViewPage> {
  final DeviceService _deviceService = DeviceService();
  VideoPlayerController? _videoController;
  Player? _mediaKitPlayer; // media_kit Player
  VideoController? _videoControllerKit; // media_kit VideoController
  bool _isInitializing = false;
  bool _useFallbackViewer = false; // 是否使用備用查看器
  bool _mediaKitInitialized = false; // media_kit 播放器是否已初始化
  Timer? _keepAliveTimer; // Keep-alive 定時器，防止30秒後停止
  
  // 追蹤相關狀態
  bool _isTrackingMode = false; // 是否啟用追蹤模式
  Timer? _trackingTimer; // 追蹤更新定時器
  List<TrackingBox> _trackingBoxes = []; // 追蹤框列表
  Offset? _selectedPoint; // 用戶點擊的位置
  TrackingBox? _activeTrackingBox; // 當前正在追蹤的物體
  double _trackingSensitivity = 0.3; // 追蹤敏感度
  Offset? _targetPosition; // 目標位置（用戶點擊的位置）
  Offset _trackingVelocity = Offset.zero; // 追蹤速度向量
  
  // 鏡頭模式
  CameraMode _cameraMode = CameraMode.front; // 當前鏡頭模式
  bool _isFullScreen = false; // 是否全螢幕模式
  
  @override
  void initState() {
    super.initState();
    // 延遲初始化，避免在 IndexedStack 中立即執行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeDevice();
      }
    });
  }
  
  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _videoController?.dispose();
    _mediaKitPlayer?.dispose();
    // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
    _videoControllerKit = null;
    // 恢復系統 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
  
  Future<void> _initializeDevice() async {
    if (!mounted) return;
    final state = Provider.of<AppState>(context, listen: false);
    if (state.deviceIp != null) {
      _deviceService.setDeviceIp(state.deviceIp!);
    }
  }
  
  /// 開始即時預覽（根據操作流程：Idle -> Live View）
  Future<void> _startLiveView() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (!state.canStartLiveView) {
      _showMessage('無法開始即時預覽：當前狀態不允許');
      return;
    }
    
    setState(() => _isInitializing = true);
    
    try {
      // 1. 確保在 Movie 模式（默認就是 Movie 模式，但確認一下）
      if (state.deviceMode != DeviceMode.movie) {
        await _deviceService.modechange(1);
        state.setDeviceMode(DeviceMode.movie);
      }
      
      // 2. 啟動即時預覽（命令 2015，par=1）
      // 發送命令：http://192.168.1.254/?custom=1&cmd=2015&par=1
      print('準備發送命令 2015 (par=1) 啟動即時預覽');
      final result = await _deviceService.movieliveviewstart(1);
      print('命令 2015 回應：$result');
      
      if (result['status'] == 'success') {
        state.setMovieModeState(MovieModeState.liveView);
        
        // 3. 等待設備進入 Live view state 並準備好 RTSP 服務
        // 根據文檔：從 Idle state 到 Live view state 需要時間
        // 且只有在 Live view state 才有 RTSP 數據流
        await Future.delayed(Duration(milliseconds: 3000));
        
        // 4. 確認設備在 Live view state（查詢狀態）
        final statusResult = await _deviceService.querycurrentstatus();
        if (statusResult['status'] == 'success') {
          print('設備狀態查詢成功，確認在 Live view state');
        }
        
        // 5. 啟動 RTSP 串流
        // 根據文檔："While stop movie live view, RTSP client should also stop and 
        // start RTSP client until movie live view start OK."
        // 只有在 movie live view start OK 後，才啟動 RTSP 客戶端
        // RTSP URL 格式：rtsp://192.168.1.254/xxxx.mov（已確認 VLC 可播放）
        await _startStream();
        
        // 6. 刷新頁面以顯示即時畫面
        if (mounted) {
          setState(() {});
        }
        
        // 7. 啟動 keep-alive 機制，防止30秒後停止
        _startKeepAlive();
        
        _showMessage('即時預覽已啟動，正在連接 RTSP 串流...');
      } else {
        _showMessage('啟動即時預覽失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    } finally {
      setState(() => _isInitializing = false);
    }
  }
  
  /// 開始即時預覽（Movie 模式 RTSP - 備用方法，已停用）
  @Deprecated('Use _startLiveView instead')
  Future<void> _startLiveViewRTSP() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (!state.canStartLiveView) {
      _showMessage('無法開始即時預覽：當前狀態不允許');
      return;
    }
    
    setState(() => _isInitializing = true);
    
    try {
      // 1. 確保在 Movie 模式（默認就是 Movie 模式，但確認一下）
      if (state.deviceMode != DeviceMode.movie) {
        await _deviceService.modechange(1);
        state.setDeviceMode(DeviceMode.movie);
      }
      
      // 2. 啟動即時預覽（命令 2015，par=1）
      // 發送命令：http://192.168.1.254/?custom=1&cmd=2015&par=1
      print('準備發送命令 2015 (par=1) 啟動即時預覽');
      final result = await _deviceService.movieliveviewstart(1);
      print('命令 2015 回應：$result');
      
      if (result['status'] == 'success') {
        state.setMovieModeState(MovieModeState.liveView);
        
        // 3. 等待設備進入 Live view state 並準備好 RTSP 服務
        // 根據文檔：從 Idle state 到 Live view state 需要時間
        // 且只有在 Live view state 才有 RTSP 數據流
        await Future.delayed(Duration(milliseconds: 3000));
        
        // 4. 確認設備在 Live view state（查詢狀態）
        final statusResult = await _deviceService.querycurrentstatus();
        if (statusResult['status'] == 'success') {
          print('設備狀態查詢成功，確認在 Live view state');
        }
        
        // 5. 啟動 RTSP 串流
        // 根據文檔："While stop movie live view, RTSP client should also stop and 
        // start RTSP client until movie live view start OK."
        // 只有在 movie live view start OK 後，才啟動 RTSP 客戶端
        // RTSP URL 格式：rtsp://192.168.1.254/xxxx.mov（已確認 VLC 可播放）
        await _startStream();
        
        _showMessage('即時預覽已啟動，正在連接 RTSP 串流...');
      } else {
        _showMessage('啟動即時預覽失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    } finally {
      setState(() => _isInitializing = false);
    }
  }
  
  /// 停止即時預覽（Live View -> Idle）
  Future<void> _stopLiveView() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (!state.canStopLiveView) {
      _showMessage('無法停止即時預覽：當前狀態不允許');
      return;
    }
    
    try {
      // 1. 停止即時預覽
      // 根據文檔："While stop movie live view, RTSP client should also stop"
      // 先停止 RTSP 客戶端，然後停止 live view
      await _stopStream();
      
      // 2. 停止即時預覽（命令 2015，par=0）
      final result = await _deviceService.movieliveviewstart(0);
      
      if (result['status'] == 'success') {
        state.setMovieModeState(MovieModeState.idle);
        // 根據文檔：在 Idle state 沒有 RTSP 數據流，RTSP 客戶端已停止
        _showMessage('即時預覽已停止（已回到 Idle state，RTSP 客戶端已停止）');
      } else {
        _showMessage('停止即時預覽失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  /// 開始錄影（Live View -> Idle -> Record）
  Future<void> _startRecord() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (!state.canStartRecord) {
      _showMessage('無法開始錄影：請先啟動即時預覽');
      return;
    }
    
    try {
      // 根據操作流程：會經過 Idle 狀態
      // 1. 先停止串流（因為會經過 Idle）
      await _stopStream();
      
      // 2. 開始錄影（命令 2001，par=1）
      // 根據文檔：從 Live view state 可以開始錄影，進入 Record state
      // 重要：錄影開始時會有短時間沒有 RTSP 數據流
      final result = await _deviceService.movierecord(1);
      
      if (result['status'] == 'success') {
        state.setMovieModeState(MovieModeState.record);
        
        // 根據文檔：錄影開始時會有短時間沒有 RTSP 數據流
        // 等待一小段時間讓設備穩定
        await Future.delayed(Duration(milliseconds: 500));
        
        _showMessage('錄影已開始（Record state）');
      } else {
        _showMessage('開始錄影失敗：${result['message']}');
        // 恢復即時預覽
        await _startLiveView();
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  /// 停止錄影（Record -> Idle -> Live View）
  Future<void> _stopRecord() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (!state.canStopRecord) {
      _showMessage('無法停止錄影：當前未在錄影');
      return;
    }
    
    try {
      // 1. 停止錄影（命令 2001，par=0）
      // 根據文檔：從 Record state 停止錄影會回到 Live view state
      // 重要：錄影停止時會有短時間沒有 RTSP 數據流
      final result = await _deviceService.movierecord(0);
      
      if (result['status'] == 'success') {
        // 根據狀態圖：停止錄影會回到 Live view state（不是 Idle）
        state.setMovieModeState(MovieModeState.liveView);
        
        // 根據文檔：錄影停止時會有短時間沒有 RTSP 數據流
        // 等待一小段時間讓設備穩定，然後重新連接 RTSP
        await Future.delayed(Duration(milliseconds: 1000));
        
        // 確保 RTSP 串流仍在運行（Live view state 應該有 RTSP 數據流）
        if (!state.isStreaming) {
          await _startStream();
        }
        
        // 2. 恢復即時預覽
        await _startLiveView();
        
        _showMessage('錄影已停止（已回到 Live view state）');
      } else {
        _showMessage('停止錄影失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  /// 拍照
  Future<void> _capturePhoto() async {
    try {
      // 切換到 Photo 模式
      final state = Provider.of<AppState>(context, listen: false);
      if (state.deviceMode != DeviceMode.photo) {
        await _deviceService.modechange(0);
        state.setDeviceMode(DeviceMode.photo);
      }
      
      final result = await _deviceService.capture();
      
      if (result['status'] == 'success') {
        final fileName = result['file']?['name'] ?? '未知';
        _showMessage('拍照成功：$fileName');
      } else {
        _showMessage('拍照失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  /// 切換到 Photo 模式並使用 HTTP MJPEG 串流（已移除）
  @Deprecated('HTTP MJPEG streaming has been removed')
  Future<void> _switchToPhotoModeAndUseMJPEG() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    try {
      // 1. 如果當前在 Movie 模式，先停止 Movie live view
      if (state.deviceMode == DeviceMode.movie) {
        print('當前在 Movie 模式，停止 Movie live view');
        try {
          await _deviceService.movieliveviewstart(0);
          state.setMovieModeState(MovieModeState.idle);
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          print('停止 Movie live view 失敗（可忽略）：$e');
        }
      }
      
      // 2. 切換到 Photo 模式（如果還不在 Photo 模式）
      if (state.deviceMode != DeviceMode.photo) {
        print('切換到 Photo 模式');
        await _deviceService.modechange(0);
        state.setDeviceMode(DeviceMode.photo);
        // 等待模式切換完成（增加等待時間）
        await Future.delayed(Duration(milliseconds: 2000));
      } else {
        print('已在 Photo 模式，等待服務啟動');
        await Future.delayed(Duration(milliseconds: 2000));
      }
      
      // 3. 嘗試多個可能的 MJPEG URL（按優先級）
      final ip = state.deviceIp ?? '192.168.1.254';
      final possibleUrls = [
        'http://$ip:8192',                    // 官方文檔指定的端口（優先）
        'http://$ip:8080/?action=stream',     // 常見的 MJPEG 端口和路徑
        'http://$ip:8080/stream',            // 備用路徑
        'http://$ip:8080',                   // 直接端口
        'http://$ip/live',                   // 其他可能的路徑
        'http://$ip:80/live',                // 標準 HTTP 端口
      ];
      
      // 4. 嘗試每個 URL（帶重試）
      for (final mjpegUrl in possibleUrls) {
        print('嘗試使用 HTTP MJPEG 串流：$mjpegUrl');
        
        // 重試 3 次，每次間隔 1 秒
        for (int retry = 0; retry < 3; retry++) {
          try {
            final testResponse = await http.get(
              Uri.parse(mjpegUrl),
            ).timeout(Duration(seconds: 5));
            
            if (testResponse.statusCode == 200) {
              // 檢查響應內容類型是否為 MJPEG
              final contentType = testResponse.headers['content-type'] ?? '';
              print('HTTP 響應成功，Content-Type: $contentType');
              
              // 使用 SimpleMjpegViewer 顯示 MJPEG 串流
              setState(() {
                _useFallbackViewer = true;
              });
              state.setStreaming(true, url: mjpegUrl);
              _showMessage('已切換到 Photo 模式，使用 HTTP MJPEG 串流\nURL: $mjpegUrl');
              return;
            }
          } catch (e) {
            print('HTTP MJPEG 串流測試失敗（重試 ${retry + 1}/3）：$e');
            if (retry < 2) {
              await Future.delayed(Duration(seconds: 1));
            }
          }
        }
      }
      
      // 所有 URL 都失敗
      _showMessage('無法連接到 HTTP MJPEG 串流\n\n已嘗試的 URL：\n${possibleUrls.map((url) => '• $url').join('\n')}\n\n提示：\n1. 確認設備在 Photo 模式\n2. 確認設備已啟動 MJPEG 服務\n3. 檢查網絡連接');
    } catch (e) {
      print('切換到 Photo 模式失敗：$e');
      _showMessage('切換到 Photo 模式失敗：$e');
    }
  }
  
  /// 啟動串流（支持 RTSP H.264 和 HTTP MJPEG）
  Future<void> _startStream() async {
    final state = Provider.of<AppState>(context, listen: false);
    final ip = state.deviceIp ?? '192.168.1.254';
    final timestamp = DateTime.now().toIso8601String();
    
     _log('啟動串流', '========== 開始 ========== [$timestamp]');
     _log('啟動串流', '當前狀態:');
    _log('啟動串流', '  - deviceMode: ${state.deviceMode}');
    _log('啟動串流', '  - movieModeState: ${state.movieModeState}');
    _log('啟動串流', '  - deviceIp: $ip');
    _log('啟動串流', '  - isStreaming: ${state.isStreaming}');
    _log('啟動串流', '  - streamUrl: ${state.streamUrl}');
    _log('啟動串流', '  - mounted: $mounted');
    
    // 只支持 Movie 模式的 RTSP H.264 串流
    if (state.deviceMode != DeviceMode.movie) {
       _log('啟動串流', ' ❌ 錯誤：設備不在 Movie 模式');
      _showMessage('即時預覽需要在 Movie 模式下使用');
      return;
    }
    
    // 設置初始化狀態，顯示轉圈圖案
     _log('啟動串流', ' 設置初始化狀態...');
    if (mounted) {
      setState(() {
        _isInitializing = true;
      });
       _log('啟動串流', ' 初始化狀態已設置 ✓');
    } else {
       _log('啟動串流', ' ⚠️ 警告：Widget 未掛載，無法設置初始化狀態');
    }
    
    // Movie 模式：RTSP H.264（即時預覽）
    // RTSP URL 格式：rtsp://192.168.1.254/xxxx.mov（已確認 VLC 可播放）
    // 注意：鏡頭切換通過 Movie Live View Size (cmd=2010) 命令實現
    // RTSP URL 本身不變，設備會根據設置的鏡頭模式返回對應的畫面
    // 因此所有模式都使用相同的 RTSP URL
    final possibleUrls = [
      'rtsp://$ip/xxxx.mov',            // 標準 RTSP URL（設備會根據當前設置返回對應畫面）
      'rtsp://$ip/xxxx.mp4',            // 備用格式
    ];
    
    bool success = false;
    
    for (int i = 0; i < possibleUrls.length; i++) {
      final streamUrl = possibleUrls[i];
       _log('啟動串流', ' 嘗試 URL ${i + 1}/${possibleUrls.length}: $streamUrl');
      
      try {
        // 對於 RTSP URL，使用 media_kit
        if (streamUrl.startsWith('rtsp://')) {
           _log('啟動串流', ' RTSP URL 檢測到，使用 media_kit 播放器');
          
          try {
            // 確保 media_kit 已初始化（延遲初始化）
             _log('啟動串流', ' 初始化 media_kit...');
            MediaKit.ensureInitialized();
             _log('啟動串流', ' media_kit 初始化完成 ✓');
            
            // 釋放之前的播放器
             _log('啟動串流', ' 清理舊播放器...');
            if (_mediaKitPlayer != null) {
              try {
                await _mediaKitPlayer!.dispose();
                 _log('啟動串流', ' 舊播放器已釋放 ✓');
              } catch (e) {
                 _log('啟動串流', ' 釋放舊播放器時出錯: $e');
              }
            }
            _mediaKitPlayer = null;
            // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
            _videoControllerKit = null;
             _log('啟動串流', ' 播放器變量已清空 ✓');
            
            // 創建新的 media_kit Player
             _log('啟動串流', ' 創建新的 media_kit Player...');
            _mediaKitPlayer = Player(
              configuration: const PlayerConfiguration(
                // RTSP 相關配置
                vo: 'gpu', // 使用 GPU 加速
              ),
            );
             _log('啟動串流', ' Player 創建成功 ✓');
            
            // 創建 VideoController
             _log('啟動串流', ' 創建 VideoController...');
            _videoControllerKit = VideoController(_mediaKitPlayer!);
             _log('啟動串流', ' VideoController 創建成功 ✓');
            
            // 監聽播放器狀態
             _log('啟動串流', ' 設置播放器狀態監聽器...');
            _mediaKitPlayer!.stream.playing.listen((playing) {
               _log('啟動串流', ' 播放狀態變化: playing=$playing');
              if (mounted) {
                setState(() {
                  _mediaKitInitialized = playing;
                });
              }
            });
            
            _mediaKitPlayer!.stream.error.listen((error) {
               _log('啟動串流', ' ❌ media_kit 播放錯誤：$error');
              if (mounted) {
                setState(() {
                  _useFallbackViewer = true;
                });
              }
            });
            
            // 監聽播放器完成事件（用於檢測連接中斷）
            // 注意：對於RTSP實時串流，completed事件可能表示連接中斷
            _mediaKitPlayer!.stream.completed.listen((completed) {
              if (completed) {
                 _log('啟動串流', ' ⚠️ media_kit 播放完成，可能連接中斷');
                // 如果是在即時預覽狀態，立即嘗試重新連接
                final state = Provider.of<AppState>(context, listen: false);
                if (state.movieModeState == MovieModeState.liveView && 
                    mounted && 
                    state.streamUrl != null &&
                    state.streamUrl!.startsWith('rtsp://')) {
                  // 延遲一小段時間後重新連接，避免立即重連導致問題
                  Future.delayed(Duration(milliseconds: 500), () {
                    if (mounted) {
                      _reconnectStream();
                    }
                  });
                }
              }
            });
            
            // 打開媒體並開始播放
             _log('啟動串流', ' 打開媒體: $streamUrl');
            await _mediaKitPlayer!.open(Media(streamUrl));
             _log('啟動串流', ' 媒體已打開 ✓');
            
             _log('啟動串流', ' 開始播放...');
            await _mediaKitPlayer!.play();
             _log('啟動串流', ' 播放命令已發送 ✓');
            
            if (mounted) {
              setState(() {
                _useFallbackViewer = false;
                _mediaKitInitialized = true;
              });
            }
            
            state.setStreaming(true, url: streamUrl);
            success = true;
            
            // 清除初始化狀態
            if (mounted) {
              setState(() {
                _isInitializing = false;
              });
            }
            
             _log('啟動串流', ' ✅ 串流啟動成功！');
             _log('啟動串流', ' 最終狀態:');
            print('  - streamUrl: $streamUrl');
            print('  - isStreaming: ${state.isStreaming}');
            print('  - _mediaKitInitialized: $_mediaKitInitialized');
            break;
          } catch (e, stackTrace) {
             _log('啟動串流', ' ❌ media_kit 播放器創建失敗');
             _log('啟動串流', ' 錯誤類型: ${e.runtimeType}');
             _log('啟動串流', ' 錯誤訊息: $e');
             _log('啟動串流', ' 錯誤堆棧:');
            print(stackTrace);
            
            try {
              await _mediaKitPlayer?.dispose();
            } catch (e2) {
               _log('啟動串流', ' 清理播放器時出錯: $e2');
            }
            _mediaKitPlayer = null;
            // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
            _videoControllerKit = null;
            
            _showMessage('播放器初始化失敗：$e\n\n'
                'RTSP URL：$streamUrl');
            
            // 播放器失敗，嘗試備用方案
            if (mounted) {
              setState(() {
                _useFallbackViewer = true;
                _isInitializing = false;
              });
            }
            state.setStreaming(true, url: streamUrl);
            success = true;
             _log('啟動串流', ' 已切換到備用查看器');
            break;
          }
        }
        
        // 對於 HTTP URL，先測試是否可訪問
        final testResponse = await http.get(
          Uri.parse(streamUrl),
        ).timeout(Duration(seconds: 3));
        
        if (testResponse.statusCode == 200) {
          // 嘗試使用 video_player
          try {
            _videoController?.dispose();
            _videoController = VideoPlayerController.networkUrl(
              Uri.parse(streamUrl),
            );
            
            await _videoController!.initialize().timeout(
              Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException('初始化超時');
              },
            );
            
            await _videoController!.play();
            await _videoController!.setLooping(true);
            
            state.setStreaming(true, url: streamUrl);
            success = true;
            if (mounted) {
              setState(() {
                _useFallbackViewer = false;
                _isInitializing = false;
              });
            }
            break;
          } catch (e) {
            print('video_player 播放失敗：$e');
            _videoController?.dispose();
            _videoController = null;
            
            // 如果是 RTSP URL，video_player 不支持，應該已經用 VLC 處理了
            // 這裡不應該執行到
            // 對於 HTTP URL，繼續嘗試下一個
            continue;
          }
        }
      } catch (e, stackTrace) {
         _log('啟動串流', ' URL 測試失敗: $streamUrl');
         _log('啟動串流', ' 錯誤: $e');
         _log('啟動串流', ' 堆棧: $stackTrace');
        continue;
      }
    }
    
    if (!success) {
       _log('啟動串流', ' ❌ 所有 URL 都失敗，無法啟動串流');
      state.setStreaming(false);
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
      _showMessage('無法啟動 RTSP 串流\n\n提示：\n1. 確認設備已啟動即時預覽（命令 2015）\n2. 確認設備在 Live view state\n3. 檢查網絡連接\n4. 確認 RTSP URL 正確：rtsp://192.168.1.254/xxxx.mov');
    } else {
      // 成功啟動，確保清除初始化狀態
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
       _log('啟動串流', ' ✅ 串流啟動流程完成');
    }
    
    final endTimestamp = DateTime.now().toIso8601String();
     _log('啟動串流', ' ========== 結束 ========== [$endTimestamp]');
  }
  
  /// 停止串流
  Future<void> _stopStream() async {
    // 停止 keep-alive 定時器
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    
    if (_videoController != null) {
      await _videoController!.pause();
      await _videoController!.dispose();
      _videoController = null;
    }
    
    // 停止 media_kit 播放器
    if (_mediaKitPlayer != null) {
      try {
        await _mediaKitPlayer!.stop();
        await _mediaKitPlayer!.dispose();
      } catch (e) {
        print('停止 media_kit 播放器時出錯：$e');
      }
      _mediaKitPlayer = null;
    }
    
    // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
    _videoControllerKit = null;
    
    setState(() {
      _useFallbackViewer = false;
    });
    
    final state = Provider.of<AppState>(context, listen: false);
    state.setStreaming(false);
    
    setState(() {});
  }
  
  /// 啟動 keep-alive 機制，防止30秒後停止
  /// 每20秒主動重新打開RTSP連接，在30秒超時前刷新連接
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    
    _keepAliveTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      final state = Provider.of<AppState>(context, listen: false);
      
      // 只有在即時預覽狀態時才執行 keep-alive
      if (state.movieModeState == MovieModeState.liveView && 
          state.isStreaming && 
          _mediaKitPlayer != null &&
          state.streamUrl != null &&
          state.streamUrl!.startsWith('rtsp://')) {
        try {
          // 方法1: 發送設備心跳命令
          await _deviceService.heartbeat();
          print('Keep-alive: 發送心跳成功');
          
          // 方法2: 在30秒超時前（20秒時）主動重新打開RTSP連接
          // 這是最關鍵的：必須真正重新建立RTSP連接，而不是只發送play命令
          print('Keep-alive: 在30秒超時前主動重新打開RTSP連接（20秒間隔）');
          
          // 不停止播放器，直接重新打開連接，減少黑屏時間
          try {
            // 先暫停（非常短暫，用戶不會察覺）
            await _mediaKitPlayer!.pause();
            await Future.delayed(Duration(milliseconds: 50));
            
            // 重新打開RTSP連接（這會重新建立整個RTSP會話）
            await _mediaKitPlayer!.open(Media(state.streamUrl!));
            await _mediaKitPlayer!.play();
            
            print('Keep-alive: RTSP連接已刷新，避免30秒超時');
          } catch (e) {
            print('Keep-alive: 重新打開連接失敗：$e，嘗試完全重新連接');
            // 如果重新打開失敗，嘗試完全重新連接
            await _reconnectStream();
          }
        } catch (e) {
          print('Keep-alive: 發送心跳失敗：$e');
          // 如果心跳失敗，嘗試重新連接串流
          await _reconnectStream();
        }
      } else {
        // 如果不在即時預覽狀態，停止 keep-alive
        timer.cancel();
        _keepAliveTimer = null;
      }
    });
  }
  
  /// 重新連接串流
  /// 完全遵循初始啟動流程（_startLiveView），但加上設置 PIP 樣式的步驟
  Future<void> _reconnectStream() async {
    final state = Provider.of<AppState>(context, listen: false);
    final timestamp = DateTime.now().toIso8601String();
    
    _log('重啟串流', '========== 開始 ========== [$timestamp]');
    _log('重啟串流', '當前狀態檢查:');
    _log('重啟串流', '- movieModeState: ${state.movieModeState}');
    _log('重啟串流', '- deviceMode: ${state.deviceMode}');
    _log('重啟串流', '- isStreaming: ${state.isStreaming}');
    _log('重啟串流', '- streamUrl: ${state.streamUrl}');
    _log('重啟串流', '- deviceIp: ${state.deviceIp}');
    _log('重啟串流', '- isConnected: ${state.isConnected}');
    _log('重啟串流', '- _cameraMode: $_cameraMode');
    _log('重啟串流', '- _mediaKitPlayer: ${_mediaKitPlayer != null ? "存在" : "null"}');
    _log('重啟串流', '- _videoControllerKit: ${_videoControllerKit != null ? "存在" : "null"}');
    _log('重啟串流', '- _mediaKitInitialized: $_mediaKitInitialized');
    _log('重啟串流', '- _useFallbackViewer: $_useFallbackViewer');
    _log('重啟串流', '- _isInitializing: $_isInitializing');
    _log('重啟串流', '- _keepAliveTimer: ${_keepAliveTimer != null ? "運行中" : "null"}');
    _log('重啟串流', '- mounted: $mounted');
    
    if (state.movieModeState != MovieModeState.liveView) {
      _log('重啟串流', '❌ 錯誤：movieModeState 不是 liveView，無法重啟');
      _showMessage('請先啟動即時預覽');
      return;
    }
    
    try {
      // 步驟 0: 停止 keep-alive 定時器（首先停止，避免干擾）
      _log('重啟串流', '步驟 0: 停止 keep-alive 定時器...');
      if (_keepAliveTimer != null) {
        _keepAliveTimer!.cancel();
        _keepAliveTimer = null;
         _log('重啟串流', ' 步驟 0: Keep-alive 定時器已停止 ✓');
      } else {
         _log('重啟串流', ' 步驟 0: Keep-alive 定時器為 null（無需停止）');
      }
      
      // 步驟 1: 徹底清理播放器（完全釋放）
       _log('重啟串流', ' 步驟 1: 清理播放器...');
      if (_mediaKitPlayer != null) {
        try {
           _log('重啟串流', ' 步驟 1.1: 停止播放器...');
          await _mediaKitPlayer!.stop();
           _log('重啟串流', ' 步驟 1.1: 播放器已停止 ✓');
          await Future.delayed(Duration(milliseconds: 200));
          
           _log('重啟串流', ' 步驟 1.2: 釋放播放器資源...');
          await _mediaKitPlayer!.dispose();
           _log('重啟串流', ' 步驟 1.2: 播放器資源已釋放 ✓');
        } catch (e, stackTrace) {
           _log('重啟串流', ' 步驟 1: 停止播放器時出錯（繼續執行）');
           _log('重啟串流', ' 錯誤: $e');
           _log('重啟串流', ' 堆棧: $stackTrace');
        }
        _mediaKitPlayer = null;
        _videoControllerKit = null;
        _mediaKitInitialized = false;
         _log('重啟串流', ' 步驟 1: 播放器變量已清空 ✓');
      } else {
         _log('重啟串流', ' 步驟 1: 播放器為 null（無需清理）');
      }
      
      // 步驟 2: 重置狀態
       _log('重啟串流', ' 步驟 2: 重置 UI 狀態...');
      if (mounted) {
        setState(() {
          _useFallbackViewer = false;
        });
         _log('重啟串流', ' 步驟 2: UI 狀態已重置 ✓');
      } else {
         _log('重啟串流', ' 步驟 2: Widget 未掛載，跳過 UI 狀態重置');
      }
      
      // 步驟 3: 確保在 Movie 模式（與初始啟動流程一致）
       _log('重啟串流', ' 步驟 3: 檢查設備模式...');
       _log('重啟串流', ' 步驟 3: 當前 deviceMode = ${state.deviceMode}');
      if (state.deviceMode != DeviceMode.movie) {
         _log('重啟串流', ' 步驟 3: 切換到 Movie 模式...');
        try {
          final modeResult = await _deviceService.modechange(1);
           _log('重啟串流', ' 步驟 3: 模式切換結果: $modeResult');
          state.setDeviceMode(DeviceMode.movie);
          await Future.delayed(Duration(milliseconds: 500));
           _log('重啟串流', ' 步驟 3: 已切換到 Movie 模式 ✓');
        } catch (e) {
           _log('重啟串流', ' 步驟 3: 模式切換失敗: $e');
        }
      } else {
         _log('重啟串流', ' 步驟 3: 已在 Movie 模式，無需切換 ✓');
      }
      
      // 步驟 4: 停止即時預覽（與切換鏡頭流程一致）
       _log('重啟串流', ' 步驟 4: 停止即時預覽...');
      try {
        final stopResult = await _deviceService.movieliveviewstart(0);
         _log('重啟串流', ' 步驟 4: 停止即時預覽命令結果: $stopResult');
        await Future.delayed(Duration(milliseconds: 800)); // 與切換鏡頭流程一致
         _log('重啟串流', ' 步驟 4: 即時預覽已停止 ✓');
      } catch (e, stackTrace) {
         _log('重啟串流', ' 步驟 4: 停止即時預覽時出錯（繼續執行）');
         _log('重啟串流', ' 錯誤: $e');
         _log('重啟串流', ' 堆棧: $stackTrace');
      }
      
      // 步驟 5: 重新設置 PIP 樣式（重要：確保使用當前的鏡頭模式）
      // 這是額外的步驟，因為切換鏡頭後需要重新設置
       _log('重啟串流', ' 步驟 5: 重新設置 PIP 樣式...');
      int pipStyle;
      switch (_cameraMode) {
        case CameraMode.front:
          pipStyle = 0; // PIP_STYLE_1T1F
          break;
        case CameraMode.rear:
          pipStyle = 1; // PIP_STYLE_1T1B2S
          break;
        case CameraMode.both:
          pipStyle = 3; // PIP_STYLE_2T2F
          break;
      }
      
       _log('重啟串流', ' 步驟 5: 當前鏡頭模式 = $_cameraMode, PIP 樣式參數 = $pipStyle');
      try {
        final pipResult = await _deviceService.setPipStyle(pipStyle);
         _log('重啟串流', ' 步驟 5: PIP 樣式設置結果: $pipResult');
        
        if (pipResult['status'] != 'success') {
           _log('重啟串流', ' 步驟 5: ⚠️ 警告：PIP 樣式設置失敗，但繼續執行');
           _log('重啟串流', ' 步驟 5: 失敗原因: ${pipResult['message']}');
        } else {
           _log('重啟串流', ' 步驟 5: PIP 樣式設置成功 ✓');
        }
      } catch (e, stackTrace) {
         _log('重啟串流', ' 步驟 5: PIP 樣式設置異常');
         _log('重啟串流', ' 錯誤: $e');
         _log('重啟串流', ' 堆棧: $stackTrace');
      }
      
      // 等待設置生效（與切換鏡頭流程一致）
       _log('重啟串流', ' 步驟 5: 等待 PIP 樣式設置生效（1秒）...');
      await Future.delayed(Duration(milliseconds: 1000));
       _log('重啟串流', ' 步驟 5: 等待完成 ✓');
      
      // 步驟 6: 重新啟動即時預覽（與初始啟動流程一致）
      // 發送命令：http://192.168.1.254/?custom=1&cmd=2015&par=1
       _log('重啟串流', ' 步驟 6: 準備發送命令 2015 (par=1) 啟動即時預覽...');
      try {
        final startResult = await _deviceService.movieliveviewstart(1);
         _log('重啟串流', ' 步驟 6: 命令 2015 回應：$startResult');
        
        if (startResult['status'] != 'success') {
           _log('重啟串流', ' 步驟 6: ❌ 錯誤：無法啟動即時預覽');
           _log('重啟串流', ' 步驟 6: 失敗原因: ${startResult['message']}');
          _showMessage('重啟串流失敗：無法啟動即時預覽 - ${startResult['message']}');
          _log('重啟串流', '========== 失敗：無法啟動即時預覽 ==========');
          return;
        } else {
           _log('重啟串流', ' 步驟 6: 即時預覽啟動成功 ✓');
        }
      } catch (e, stackTrace) {
         _log('重啟串流', ' 步驟 6: ❌ 異常：啟動即時預覽時出錯');
         _log('重啟串流', ' 錯誤: $e');
         _log('重啟串流', ' 堆棧: $stackTrace');
        _showMessage('重啟串流出錯：啟動即時預覽失敗 - $e');
        return;
      }
      
      // 步驟 7: 設置狀態（與初始啟動流程一致）
       _log('重啟串流', ' 步驟 7: 設置應用狀態為 liveView...');
      state.setMovieModeState(MovieModeState.liveView);
       _log('重啟串流', ' 步驟 7: 狀態已設置 ✓');
      
      // 步驟 8: 等待設備進入 Live view state 並準備好 RTSP 服務（與初始啟動流程一致）
      // 根據文檔：從 Idle state 到 Live view state 需要時間
      // 且只有在 Live view state 才有 RTSP 數據流
       _log('重啟串流', ' 步驟 8: 等待設備進入 Live view state 並準備好 RTSP 服務（3秒）...');
      await Future.delayed(Duration(milliseconds: 3000)); // 與初始啟動流程一致
       _log('重啟串流', ' 步驟 8: 等待完成 ✓');
      
      // 步驟 9: 確認設備在 Live view state（查詢狀態，與初始啟動流程一致）
       _log('重啟串流', ' 步驟 9: 查詢設備狀態...');
      try {
        final statusResult = await _deviceService.querycurrentstatus();
         _log('重啟串流', ' 步驟 9: 設備狀態查詢結果: $statusResult');
        if (statusResult['status'] == 'success') {
           _log('重啟串流', ' 步驟 9: 設備狀態查詢成功，確認在 Live view state ✓');
        } else {
           _log('重啟串流', ' 步驟 9: ⚠️ 警告：設備狀態查詢失敗，但繼續執行');
        }
      } catch (e) {
         _log('重啟串流', ' 步驟 9: ⚠️ 警告：查詢設備狀態時出錯: $e');
      }
      
      // 步驟 10: 啟動 RTSP 串流（與初始啟動流程一致）
      // 根據文檔："While stop movie live view, RTSP client should also stop and 
      // start RTSP client until movie live view start OK."
      // 只有在 movie live view start OK 後，才啟動 RTSP 客戶端
       _log('重啟串流', ' 步驟 10: 啟動 RTSP 串流...');
       _log('重啟串流', ' 步驟 10: 當前狀態檢查:');
       _log('重啟串流', ' 步驟 10:   - deviceIp: ${state.deviceIp}');
       _log('重啟串流', ' 步驟 10:   - deviceMode: ${state.deviceMode}');
       _log('重啟串流', ' 步驟 10:   - movieModeState: ${state.movieModeState}');
       _log('重啟串流', ' 步驟 10:   - mounted: $mounted');
      
      try {
        // _startStream() 內部會設置 _isInitializing，顯示轉圈圖案
        await _startStream();
         _log('重啟串流', ' 步驟 10: _startStream() 執行完成');
        
        // 檢查串流狀態
        await Future.delayed(Duration(milliseconds: 500));
         _log('重啟串流', ' 步驟 10: 串流狀態檢查:');
         _log('重啟串流', ' 步驟 10:   - isStreaming: ${state.isStreaming}');
         _log('重啟串流', ' 步驟 10:   - streamUrl: ${state.streamUrl}');
         _log('重啟串流', ' 步驟 10:   - _mediaKitPlayer: ${_mediaKitPlayer != null ? "存在" : "null"}');
         _log('重啟串流', ' 步驟 10:   - _videoControllerKit: ${_videoControllerKit != null ? "存在" : "null"}');
         _log('重啟串流', ' 步驟 10:   - _mediaKitInitialized: $_mediaKitInitialized');
         _log('重啟串流', ' 步驟 10:   - _isInitializing: $_isInitializing');
        
        if (!state.isStreaming || state.streamUrl == null) {
           _log('重啟串流', ' 步驟 10: ❌ 錯誤：串流未成功啟動');
          throw Exception('串流未成功啟動：isStreaming=${state.isStreaming}, streamUrl=${state.streamUrl}');
        }
         _log('重啟串流', ' 步驟 10: RTSP 串流啟動成功 ✓');
      } catch (e, stackTrace) {
         _log('重啟串流', ' 步驟 10: ❌ 錯誤：啟動 RTSP 串流失敗');
         _log('重啟串流', ' 錯誤: $e');
         _log('重啟串流', ' 堆棧: $stackTrace');
        rethrow; // 重新拋出異常，讓外層 catch 處理
      }
      
      // 步驟 11: 刷新頁面以顯示即時畫面（與初始啟動流程一致）
       _log('重啟串流', ' 步驟 11: 刷新 UI...');
      if (mounted) {
        setState(() {});
         _log('重啟串流', ' 步驟 11: UI 已刷新 ✓');
      } else {
         _log('重啟串流', ' 步驟 11: Widget 未掛載，跳過 UI 刷新');
      }
      
      // 步驟 12: 啟動 keep-alive 機制，防止30秒後停止（與初始啟動流程一致）
       _log('重啟串流', ' 步驟 12: 啟動 keep-alive 機制...');
      _startKeepAlive();
       _log('重啟串流', ' 步驟 12: Keep-alive 機制已啟動 ✓');
      
      final endTimestamp = DateTime.now().toIso8601String();
      _log('重啟串流', '========== 成功完成 ========== [$endTimestamp]');
       _log('重啟串流', ' 最終狀態:');
      print('  - isStreaming: ${state.isStreaming}');
      print('  - streamUrl: ${state.streamUrl}');
      print('  - _mediaKitPlayer: ${_mediaKitPlayer != null ? "存在" : "null"}');
      print('  - _videoControllerKit: ${_videoControllerKit != null ? "存在" : "null"}');
      print('  - _mediaKitInitialized: $_mediaKitInitialized');
      print('  - _isInitializing: $_isInitializing');
      _showMessage('串流已重啟');
    } catch (e, stackTrace) {
      final errorTimestamp = DateTime.now().toIso8601String();
      _log('重啟串流', '========== 失敗 ========== [$errorTimestamp]');
       _log('重啟串流', ' 錯誤類型: ${e.runtimeType}');
       _log('重啟串流', ' 錯誤訊息: $e');
       _log('重啟串流', ' 錯誤堆棧:');
      print(stackTrace);
       _log('重啟串流', ' 失敗時狀態:');
      print('  - movieModeState: ${state.movieModeState}');
      print('  - deviceMode: ${state.deviceMode}');
      print('  - isStreaming: ${state.isStreaming}');
      print('  - streamUrl: ${state.streamUrl}');
      print('  - _mediaKitPlayer: ${_mediaKitPlayer != null ? "存在" : "null"}');
      print('  - _videoControllerKit: ${_videoControllerKit != null ? "存在" : "null"}');
      print('  - _mediaKitInitialized: $_mediaKitInitialized');
      print('  - _isInitializing: $_isInitializing');
      print('  - mounted: $mounted');
      _showMessage('重啟串流出錯：$e');
      
      // 嘗試最後一次恢復串流
      try {
         _log('重啟串流', ' 嘗試最後一次恢復串流...');
        await Future.delayed(Duration(milliseconds: 1000));
        await _startStream();
         _log('重啟串流', ' 最後一次恢復串流完成');
      } catch (e2, stackTrace2) {
         _log('重啟串流', ' 最後一次恢復串流也失敗');
         _log('重啟串流', ' 錯誤: $e2');
         _log('重啟串流', ' 堆棧: $stackTrace2');
      }
    }
  }
  
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullScreen ? null : AppBar(
        title: Text('實時影像瀏覽'),
        actions: [
          // 追蹤模式切換按鈕（確保可見且突出）
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isTrackingMode = !_isTrackingMode;
                  if (_isTrackingMode) {
                    _startTrackingLoop();
                  } else {
                    _stopTrackingLoop();
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isTrackingMode 
                      ? Colors.orange.withOpacity(0.8) 
                      : Colors.black.withOpacity(0.6), // 增強背景不透明度
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isTrackingMode ? Colors.orange : Colors.white70, // 添加邊框提高可見性
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  _isTrackingMode ? Icons.track_changes : Icons.track_changes_outlined,
                  color: _isTrackingMode ? Colors.white : Colors.white, // 確保圖標始終為白色
                  size: 28,
                ),
              ),
            ),
          ),
          SizedBox(width: 4),
          Consumer<AppState>(
            builder: (context, state, _) {
              return IconButton(
                icon: Icon(
                  state.isConnected ? Icons.wifi : Icons.wifi_off,
                  size: 28,
                ),
                onPressed: () {
                  // 導航到 Wi-Fi 連接頁面
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          // 確保按鈕始終顯示（除非全螢幕）
          // 使用明確的條件判斷，確保按鈕一定會渲染
          final showControls = !_isFullScreen;
          
          return Column(
            children: [
              // 前後鏡頭切換按鈕區域（在頁面上方）- 強制顯示，確保始終可見
              if (showControls)
                _buildCameraSwitchBar(),
              // 串流顯示區域
              Expanded(
                child: _buildStreamView(state),
              ),
              // 控制按鈕區域
              if (showControls)
                _buildControlPanel(state),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildStreamView(AppState state) {
    if (!state.isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('未連接到設備', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('請先連接 Wi-Fi', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    // 如果正在初始化，顯示轉圈圖案
    if (_isInitializing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在連接串流...'),
          ],
        ),
      );
    }
    
    // 如果使用 media_kit 播放器（RTSP）
    if (!_useFallbackViewer && state.streamUrl != null && state.streamUrl!.startsWith('rtsp://')) {
      if (_mediaKitPlayer != null && _videoControllerKit != null) {
        print('構建 media_kit Video widget，播放器狀態：_mediaKitInitialized=$_mediaKitInitialized');
        
        // 使用 media_kit 的 Video widget，帶追蹤覆蓋層和全螢幕支持
        return GestureDetector(
          onTapDown: _isTrackingMode ? (details) => _handleTapDown(details) : null,
          onDoubleTap: () {
            setState(() {
              _isFullScreen = !_isFullScreen;
              if (_isFullScreen) {
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
              } else {
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              }
            });
          },
          child: Stack(
            children: [
              Video(
                controller: _videoControllerKit!,
                // 在全螢幕模式下使用自定義控制，非全螢幕使用默認控制
                controls: AdaptiveVideoControls,
                fill: Colors.black,
              ),
              // 追蹤覆蓋層（在全螢幕模式下也能使用）
              if (_isTrackingMode)
                CustomPaint(
                  painter: TrackingPainter(
                    trackingBoxes: _trackingBoxes,
                    showInfo: true,
                  ),
                  size: Size.infinite,
                ),
              // 全螢幕模式下的控制按鈕（確保在最上層，始終顯示）
              if (_isFullScreen)
                _buildFullScreenControls(state),
            ],
          ),
        );
      } else {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在創建播放器...'),
            ],
          ),
        );
      }
    }
    
    // 如果使用備用查看器（HTTP MJPEG 或 RTSP 失敗時）
    if (_useFallbackViewer && state.isStreaming && state.streamUrl != null) {
      // 如果是 RTSP URL，顯示 RTSP URL 和使用說明
      if (state.streamUrl!.startsWith('rtsp://')) {
        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_library, size: 64, color: Colors.blue),
                SizedBox(height: 16),
                Text(
                  'RTSP 串流已準備',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RTSP URL:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 8),
                        SelectableText(
                          state.streamUrl!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  '使用外部播放器播放',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '方法 1: 使用 VLC 播放器',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1. 在手機上安裝 VLC for Android\n'
                          '2. 打開 VLC > 網絡串流\n'
                          '3. 輸入上述 RTSP URL\n'
                          '4. 點擊播放',
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '方法 2: 複製 URL',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '點擊下方按鈕複製 RTSP URL，然後在其他播放器中使用',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: Icon(Icons.content_copy),
                  label: Text('複製 RTSP URL'),
                  onPressed: () async {
                    if (state.streamUrl != null) {
                      await Clipboard.setData(ClipboardData(text: state.streamUrl!));
                      _showMessage('RTSP URL 已複製到剪貼板\n\n可以在 VLC 播放器中粘貼使用');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: Icon(Icons.refresh),
                  label: Text('重新嘗試內嵌播放'),
                  onPressed: () {
                    setState(() {
                      _useFallbackViewer = false;
                    });
                    _startStream();
                  },
                ),
              ],
            ),
          ),
        );
      }
      // 對於 HTTP URL，使用備用查看器
      return SimpleMjpegViewer(streamUrl: state.streamUrl!);
    }
    
    // 如果使用 video_player（HTTP 視頻）
    if (_videoController != null && _videoController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      );
    }
    
    // 如果 video_player 初始化失敗，顯示錯誤信息
    if (state.isStreaming && _videoController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text('串流連接失敗', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text(
              '可能原因：\n1. 設備未啟動即時預覽\n2. 串流 URL 不正確\n3. 網絡連接問題',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (state.movieModeState == MovieModeState.liveView) {
                  _startStream();
                }
              },
              child: Text('重試'),
            ),
          ],
        ),
      );
    }
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('未啟動即時預覽', style: TextStyle(fontSize: 18)),
          SizedBox(height: 8),
          Text(
            '點擊「開始預覽」按鈕啟動',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
  
  Widget _buildControlPanel(AppState state) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 狀態顯示
          _buildStateIndicator(state),
          SizedBox(height: 16),
          // 控制按鈕
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              // 即時預覽控制
              if (state.movieModeState == MovieModeState.idle)
                ElevatedButton.icon(
                  onPressed: _isInitializing ? null : _startLiveView,
                  icon: Icon(Icons.play_arrow),
                  label: Text('開始預覽'),
                )
              else if (state.movieModeState == MovieModeState.liveView)
                ElevatedButton.icon(
                  onPressed: _stopLiveView,
                  icon: Icon(Icons.stop),
                  label: Text('停止預覽'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
              
              // 重啟串流按鈕（在即時預覽狀態下顯示）
              if (state.movieModeState == MovieModeState.liveView && state.isStreaming)
                ElevatedButton.icon(
                  onPressed: () async {
                    print('手動重啟串流');
                    await _reconnectStream();
                    _showMessage('正在重啟串流...');
                  },
                  icon: Icon(Icons.refresh),
                  label: Text('重啟串流'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                ),
              
              // 錄影控制
              if (state.movieModeState == MovieModeState.liveView)
                ElevatedButton.icon(
                  onPressed: _startRecord,
                  icon: Icon(Icons.fiber_manual_record),
                  label: Text('開始錄影'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                )
              else if (state.movieModeState == MovieModeState.record)
                ElevatedButton.icon(
                  onPressed: _stopRecord,
                  icon: Icon(Icons.stop),
                  label: Text('停止錄影'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              
              // 拍照
              ElevatedButton.icon(
                onPressed: _capturePhoto,
                icon: Icon(Icons.camera_alt),
                label: Text('拍照'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  /// 啟動追蹤循環
  void _startTrackingLoop() {
    _trackingTimer?.cancel();
    
    _trackingTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isTrackingMode) {
        timer.cancel();
        return;
      }
      
      if (_selectedPoint != null) {
        if (_activeTrackingBox == null) {
          _activeTrackingBox = TrackingBox(
            id: DateTime.now().millisecondsSinceEpoch,
            center: _selectedPoint!,
            width: 100,
            height: 100,
            color: Colors.red,
            label: '追蹤目標',
          );
          _trackingBoxes.add(_activeTrackingBox!);
          // 確保目標位置已設置
          if (_targetPosition == null) {
            _targetPosition = _selectedPoint;
          }
        } else {
          _updateTrackingBox(_activeTrackingBox!);
        }
      }
      
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  /// 停止追蹤循環
  void _stopTrackingLoop() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    setState(() {
      _trackingBoxes.clear();
      _activeTrackingBox = null;
      _selectedPoint = null;
      _targetPosition = null;
      _trackingVelocity = Offset.zero;
    });
  }
  
  /// 更新追蹤框位置（改進：使用速度向量和目標跟隨邏輯）
  void _updateTrackingBox(TrackingBox box) {
    if (_targetPosition == null) {
      // 如果沒有目標位置，保持當前位置
      box.updateTime = DateTime.now();
      box.frameCount++;
      return;
    }
    
    // 獲取實際屏幕大小
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    
    // 計算到目標位置的方向和距離
    final direction = _targetPosition! - box.center;
    final distance = direction.distance;
    
    // 如果距離很小，保持當前位置
    if (distance < 5) {
      box.updateTime = DateTime.now();
      box.frameCount++;
      return;
    }
    
    // 計算速度：距離越遠，速度越快（但有上限）
    final maxSpeed = 8.0 * _trackingSensitivity;
    final speed = math.min(distance * 0.1, maxSpeed);
    
    // 計算速度向量（朝向目標）
    final normalizedDirection = direction / distance;
    _trackingVelocity = normalizedDirection * speed;
    
    // 應用速度向量，並添加少量隨機性模擬真實追蹤
    final random = math.Random();
    final noiseX = (random.nextDouble() - 0.5) * 2 * _trackingSensitivity;
    final noiseY = (random.nextDouble() - 0.5) * 2 * _trackingSensitivity;
    
    final newCenter = box.center + _trackingVelocity + Offset(noiseX, noiseY);
    
    // 確保追蹤框不會超出屏幕邊界
    box.center = Offset(
      newCenter.dx.clamp(box.width / 2, screenWidth - box.width / 2),
      newCenter.dy.clamp(box.height / 2, screenHeight - box.height / 2),
    );
    
    box.updateTime = DateTime.now();
    box.frameCount++;
  }
  
  /// 處理點擊事件
  void _handleTapDown(TapDownDetails details) {
    if (!_isTrackingMode) return;
    
    setState(() {
      _selectedPoint = details.localPosition;
      _targetPosition = details.localPosition; // 設置目標位置
      _trackingVelocity = Offset.zero; // 重置速度向量
      
      if (_activeTrackingBox != null) {
        _trackingBoxes.remove(_activeTrackingBox);
      }
      _activeTrackingBox = null;
    });
  }
  
  /// 構建前後鏡頭切換欄（單一按鈕循環切換）
  Widget _buildCameraSwitchBar() {
    String modeText;
    IconData modeIcon;
    Color buttonColor;
    
    switch (_cameraMode) {
      case CameraMode.front:
        modeText = '前鏡頭';
        modeIcon = Icons.camera_front;
        buttonColor = Colors.blue;
        break;
      case CameraMode.rear:
        modeText = '後鏡頭';
        modeIcon = Icons.camera_rear;
        buttonColor = Colors.green;
        break;
      case CameraMode.both:
        modeText = '前後同時';
        modeIcon = Icons.cameraswitch;
        buttonColor = Colors.orange;
        break;
    }
    
    print('渲染鏡頭切換按鈕: $modeText, 顏色: $buttonColor');
    
    // 調整按鈕大小，使其更緊湊
    return Container(
      width: double.infinity,
      height: 56, // 減小高度，使其更緊湊
      color: Colors.white,
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black12,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Center(
            child: Material(
              color: buttonColor,
              borderRadius: BorderRadius.circular(8),
              elevation: 3,
              child: InkWell(
                onTap: () {
                  print('鏡頭切換按鈕被點擊');
                  _cycleCameraMode();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10), // 減小padding
                  decoration: BoxDecoration(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        modeIcon,
                        color: Colors.white,
                        size: 20, // 減小圖標大小
                      ),
                      SizedBox(width: 8), // 減小間距
                      Text(
                        modeText,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600, // 減小字體粗細
                          fontSize: 14, // 減小字體大小
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.swap_horiz,
                        color: Colors.white,
                        size: 18, // 減小圖標大小
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// 循環切換鏡頭模式
  void _cycleCameraMode() {
    setState(() {
      switch (_cameraMode) {
        case CameraMode.front:
          _cameraMode = CameraMode.rear;
          break;
        case CameraMode.rear:
          _cameraMode = CameraMode.both;
          break;
        case CameraMode.both:
          _cameraMode = CameraMode.front;
          break;
      }
    });
    
    // 切換鏡頭時重新連接串流
    _switchCamera();
  }
  
  /// 切換鏡頭（根據當前模式）
  /// 使用命令 3028 (setPipStyle) 設置 PIP 樣式
  /// PIP_STYLE 枚舉值：
  /// 0: PIP_STYLE_1T1F - 只有 Path 1 全屏在頂部（前鏡頭）
  /// 1: PIP_STYLE_1T1B2S - Path 1 在頂部，Path 1 大屏，Path 2 小屏（前後同時，前大後小）
  /// 2: PIP_STYLE_1T1S2B - Path 1 在頂部，Path 1 小屏，Path 2 大屏（前後同時，前小後大）
  /// 3: PIP_STYLE_2T2F - 只有 Path 2 全屏在頂部（後鏡頭）
  /// 4: PIP_STYLE_2T1B2S - Path 2 在頂部，Path 1 大屏，Path 2 小屏（前後同時，前大後小）
  /// 5: PIP_STYLE_2T1S2B - Path 2 在頂部，Path 1 小屏，Path 2 大屏（前後同時，前小後大）
  Future<void> _switchCamera() async {
    String modeText;
    
    switch (_cameraMode) {
      case CameraMode.front:
        modeText = '前鏡頭';
        break;
      case CameraMode.rear:
        modeText = '後鏡頭';
        break;
      case CameraMode.both:
        modeText = '前後鏡頭同時';
        break;
    }
    
    final state = Provider.of<AppState>(context, listen: false);
    
    // 如果正在串流，需要先停止，設置鏡頭模式，然後重新啟動
    if (state.isStreaming && state.movieModeState == MovieModeState.liveView) {
      try {
        // 1. 停止當前串流
        await _stopStream();
        
        // 2. 停止即時預覽
        await _deviceService.movieliveviewstart(0);
        await Future.delayed(Duration(milliseconds: 800));
        
        // 3. 使用命令 3028 設置 PIP 樣式
        // 修正：後鏡頭和前後同時的參數交換
        int pipStyle;
        switch (_cameraMode) {
          case CameraMode.front:
            pipStyle = 0; // PIP_STYLE_1T1F - Path 1 全屏（前鏡頭）
            break;
          case CameraMode.rear:
            pipStyle = 1; // PIP_STYLE_1T1B2S - Path 1 大屏，Path 2 小屏（修正：後鏡頭）
            break;
          case CameraMode.both:
            pipStyle = 3; // PIP_STYLE_2T2F - Path 2 全屏（修正：前後同時）
            break;
        }
        
        print('設置鏡頭模式: $modeText (使用 setPipStyle par=$pipStyle)');
        final setResult = await _deviceService.setPipStyle(pipStyle);
        print('PIP 樣式設置結果: $setResult');
        
        if (setResult['status'] != 'success') {
          print('設置 PIP 樣式失敗，嘗試其他參數...');
          // 如果失敗，可以嘗試其他參數組合
        }
        
        // 4. 等待設置生效
        await Future.delayed(Duration(milliseconds: 1000));
        
        // 5. 重新啟動即時預覽
        final startResult = await _deviceService.movieliveviewstart(1);
        print('重新啟動即時預覽結果: $startResult');
        
        if (startResult['status'] == 'success') {
          state.setMovieModeState(MovieModeState.liveView);
          // 等待設備準備好 RTSP 服務
          await Future.delayed(Duration(milliseconds: 2500));
          
          // 6. 重新啟動串流
          await _startStream();
          
          _showMessage('已切換到$modeText');
        } else {
          _showMessage('切換鏡頭失敗：${startResult['message']}');
          // 嘗試恢復串流
          await _startStream();
        }
      } catch (e) {
        print('切換鏡頭時出錯: $e');
        _showMessage('切換鏡頭時出錯：$e');
        // 嘗試恢復串流
        try {
          await _startStream();
        } catch (e2) {
          print('恢復串流失敗: $e2');
        }
      }
    } else {
      // 如果沒有串流，只設置鏡頭模式
      try {
        int pipStyle;
        switch (_cameraMode) {
          case CameraMode.front:
            pipStyle = 0; // PIP_STYLE_1T1F
            break;
          case CameraMode.rear:
            pipStyle = 1; // PIP_STYLE_1T1B2S（修正：後鏡頭）
            break;
          case CameraMode.both:
            pipStyle = 3; // PIP_STYLE_2T2F（修正：前後同時）
            break;
        }
        
        final setResult = await _deviceService.setPipStyle(pipStyle);
        if (setResult['status'] == 'success') {
          _showMessage('已設置為$modeText（下次啟動即時預覽時生效）');
        } else {
          _showMessage('設置鏡頭模式失敗：${setResult['message']}');
        }
      } catch (e) {
        _showMessage('設置鏡頭模式時出錯：$e');
      }
    }
  }
  
  /// 構建全螢幕模式下的鏡頭切換按鈕
  Widget _buildFullScreenCameraButton() {
    String modeText;
    IconData modeIcon;
    
    switch (_cameraMode) {
      case CameraMode.front:
        modeText = '前';
        modeIcon = Icons.camera_front;
        break;
      case CameraMode.rear:
        modeText = '後';
        modeIcon = Icons.camera_rear;
        break;
      case CameraMode.both:
        modeText = '雙';
        modeIcon = Icons.cameraswitch;
        break;
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              modeIcon,
              color: Colors.white,
              size: 24,
            ),
            SizedBox(height: 2),
            Text(
              modeText,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        onPressed: _cycleCameraMode,
        tooltip: '切換鏡頭模式（點擊循環切換）',
      ),
    );
  }
  
  /// 構建全螢幕模式下的控制按鈕
  Widget _buildFullScreenControls(AppState state) {
    String modeText;
    IconData modeIcon;
    Color buttonColor;
    
    switch (_cameraMode) {
      case CameraMode.front:
        modeText = '前';
        modeIcon = Icons.camera_front;
        buttonColor = Colors.blue;
        break;
      case CameraMode.rear:
        modeText = '後';
        modeIcon = Icons.camera_rear;
        buttonColor = Colors.green;
        break;
      case CameraMode.both:
        modeText = '雙';
        modeIcon = Icons.cameraswitch;
        buttonColor = Colors.orange;
        break;
    }
    
    // 確保按鈕始終在最上層，使用 Material 和明確的 z-index
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.5, 1.0],
                colors: [
                  Colors.black.withOpacity(0.9),
                  Colors.black.withOpacity(0.7),
                  Colors.black.withOpacity(0.4),
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 左側：鏡頭切換按鈕
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _cycleCameraMode,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: buttonColor.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            modeIcon,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(width: 6),
                          Text(
                            modeText,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 右側：追蹤和退出全螢幕按鈕
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 追蹤模式切換
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isTrackingMode = !_isTrackingMode;
                            if (_isTrackingMode) {
                              _startTrackingLoop();
                            } else {
                              _stopTrackingLoop();
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _isTrackingMode 
                                ? Colors.orange.withOpacity(0.8) 
                                : Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isTrackingMode ? Colors.orange : Colors.white24,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _isTrackingMode ? Icons.track_changes : Icons.track_changes_outlined,
                            color: _isTrackingMode ? Colors.orange : Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    // 退出全螢幕
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isFullScreen = false;
                            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: Icon(
                            Icons.fullscreen_exit,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStateIndicator(AppState state) {
    String stateText;
    Color stateColor;
    
    switch (state.movieModeState) {
      case MovieModeState.idle:
        stateText = '閒置狀態';
        stateColor = Colors.grey;
        break;
      case MovieModeState.liveView:
        stateText = '即時預覽中';
        stateColor = Colors.blue;
        break;
      case MovieModeState.record:
        stateText = '錄影中';
        stateColor = Colors.red;
        break;
    }
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 8),
            Text(
              stateText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: stateColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 追蹤框數據類
class TrackingBox {
  final int id;
  Offset center;
  final double width;
  final double height;
  final Color color;
  final String label;
  DateTime updateTime;
  int frameCount;
  
  TrackingBox({
    required this.id,
    required this.center,
    required this.width,
    required this.height,
    required this.color,
    required this.label,
    DateTime? updateTime,
    this.frameCount = 0,
  }) : updateTime = updateTime ?? DateTime.now();
  
  Rect get rect => Rect.fromCenter(
    center: center,
    width: width,
    height: height,
  );
}

/// 追蹤覆蓋層繪製器
class TrackingPainter extends CustomPainter {
  final List<TrackingBox> trackingBoxes;
  final bool showInfo;
  
  TrackingPainter({
    required this.trackingBoxes,
    this.showInfo = true,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final box in trackingBoxes) {
      // 繪製追蹤框
      final paint = Paint()
        ..color = box.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      
      final rect = box.rect;
      canvas.drawRect(rect, paint);
      
      // 繪製四個角的標記
      final cornerSize = 20.0;
      _drawCorner(canvas, rect.topLeft, cornerSize, box.color);
      _drawCorner(canvas, rect.topRight, cornerSize, box.color);
      _drawCorner(canvas, rect.bottomLeft, cornerSize, box.color);
      _drawCorner(canvas, rect.bottomRight, cornerSize, box.color);
      
      // 繪製標籤
      if (showInfo && box.label.isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: box.label,
            style: TextStyle(
              color: box.color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.black54,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(rect.left, rect.top - textPainter.height - 4),
        );
      }
      
      // 繪製中心點
      final centerPaint = Paint()
        ..color = box.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(box.center, 4, centerPaint);
    }
  }
  
  void _drawCorner(Canvas canvas, Offset position, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    // 繪製 L 形角標記
    canvas.drawLine(
      position,
      Offset(position.dx + size, position.dy),
      paint,
    );
    canvas.drawLine(
      position,
      Offset(position.dx, position.dy + size),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(TrackingPainter oldDelegate) {
    return trackingBoxes.length != oldDelegate.trackingBoxes.length ||
           showInfo != oldDelegate.showInfo;
  }
}

