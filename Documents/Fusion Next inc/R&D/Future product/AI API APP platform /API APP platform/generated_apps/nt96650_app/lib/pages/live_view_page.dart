import 'dart:async';
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
  bool _isReconnecting = false; // 是否正在重新連接，防止重複重連
  bool _isRefreshing = false; // 是否正在刷新連接，防止重複刷新
  DateTime? _lastRefreshTime; // 上次刷新時間，用於防抖
  Player? _backupPlayer; // 備用播放器，用於無縫切換
  VideoController? _backupVideoController; // 備用視頻控制器
  
  @override
  void initState() {
    super.initState();
    _initializeDevice();
  }
  
  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _videoController?.dispose();
    _mediaKitPlayer?.dispose();
    _backupPlayer?.dispose(); // 釋放備用播放器
    // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
    _videoControllerKit = null;
    _backupVideoController = null;
    super.dispose();
  }
  
  Future<void> _initializeDevice() async {
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
    
    // 只支持 Movie 模式的 RTSP H.264 串流
    if (state.deviceMode != DeviceMode.movie) {
      _showMessage('即時預覽需要在 Movie 模式下使用');
      return;
    }
    
    // Movie 模式：RTSP H.264（即時預覽）
    // RTSP URL 格式：rtsp://192.168.1.254/xxxx.mov（已確認 VLC 可播放）
    final possibleUrls = [
      'rtsp://$ip/xxxx.mov',            // 確認可用的 RTSP URL（優先）
      'rtsp://$ip/xxxx.mp4',            // 備用格式
    ];
    
    bool success = false;
    
    for (final streamUrl in possibleUrls) {
      try {
        // 對於 RTSP URL，使用 media_kit
        if (streamUrl.startsWith('rtsp://')) {
          print('RTSP URL 檢測到：$streamUrl，使用 media_kit 播放器');
          
          try {
            // 確保 media_kit 已初始化（延遲初始化）
            MediaKit.ensureInitialized();
            
            // 釋放之前的播放器
            await _mediaKitPlayer?.dispose();
            _mediaKitPlayer = null;
            // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
            _videoControllerKit = null;
            
            // 創建新的 media_kit Player
            _mediaKitPlayer = Player(
              configuration: const PlayerConfiguration(
                // RTSP 相關配置
                vo: 'gpu', // 使用 GPU 加速
              ),
            );
            
            // 創建 VideoController
            _videoControllerKit = VideoController(_mediaKitPlayer!);
            
            // 監聽播放器狀態
            _mediaKitPlayer!.stream.playing.listen((playing) {
              if (mounted) {
                setState(() {
                  _mediaKitInitialized = playing;
                });
                
                // 如果播放器停止且是在即時預覽狀態，立即嘗試恢復
                // 使用無黑屏方式，避免完全重新連接
                if (!playing) {
                  final state = Provider.of<AppState>(context, listen: false);
                  if (state.movieModeState == MovieModeState.liveView && 
                      state.isStreaming &&
                      !_isReconnecting &&
                      !_isRefreshing) {
                    // 防抖：如果距離上次刷新不到2秒，則跳過
                    final now = DateTime.now();
                    if (_lastRefreshTime == null || 
                        now.difference(_lastRefreshTime!).inSeconds >= 2) {
                      print('播放器狀態變為停止，立即嘗試無黑屏恢復');
                      // 立即嘗試無黑屏刷新，不延遲
                      _refreshRTSPStreamWithoutBlackScreen().catchError((e) {
                        print('無黑屏刷新失敗：$e，嘗試完全重新連接');
                        // 只有在無黑屏刷新失敗時才完全重新連接
                        _reconnectStream();
                      });
                    } else {
                      print('播放器停止，但距離上次刷新太近，跳過（防抖）');
                    }
                  }
                }
              }
            });
            
            _mediaKitPlayer!.stream.error.listen((error) {
              print('media_kit 播放錯誤：$error');
              if (mounted) {
                setState(() {
                  _useFallbackViewer = true;
                });
                // 對於 RTSP 實時串流，錯誤可能是暫時的
                // 嘗試使用無黑屏方式刷新連接，而不是完全重新連接
                final state = Provider.of<AppState>(context, listen: false);
                if (state.movieModeState == MovieModeState.liveView && !_isRefreshing) {
                  // 延遲後嘗試無黑屏刷新
                  Future.delayed(Duration(seconds: 1), () {
                    if (mounted && 
                        state.movieModeState == MovieModeState.liveView &&
                        !_isRefreshing) {
                      _refreshRTSPStreamWithoutBlackScreen().catchError((e) {
                        print('無黑屏刷新失敗：$e，嘗試完全重新連接');
                        _reconnectStream();
                      });
                    }
                  });
                }
              }
            });
            
            // 注意：對於 RTSP 實時串流，不應該監聽 completed 事件
            // 因為實時串流理論上永遠不會"完成"，completed 事件可能是誤觸發
            // 改為通過 playing 狀態和錯誤事件來檢測連接問題
            
            // 打開媒體並開始播放
            await _mediaKitPlayer!.open(Media(streamUrl));
            await _mediaKitPlayer!.play();
            
            print('media_kit 播放器創建成功，開始播放');
            
            setState(() {
              _useFallbackViewer = false;
              _mediaKitInitialized = true;
            });
            
            state.setStreaming(true, url: streamUrl);
            success = true;
            break;
          } catch (e) {
            print('media_kit 播放器創建失敗：$e');
            await _mediaKitPlayer?.dispose();
            _mediaKitPlayer = null;
            // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
            _videoControllerKit = null;
            
            _showMessage('播放器初始化失敗：$e\n\n'
                'RTSP URL：$streamUrl');
            
            // 播放器失敗，嘗試備用方案
            setState(() {
              _useFallbackViewer = true;
            });
            state.setStreaming(true, url: streamUrl);
            success = true;
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
            setState(() {
              _useFallbackViewer = false;
            });
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
      } catch (e) {
        print('URL 測試失敗：$streamUrl - $e');
        continue;
      }
    }
    
    if (!success) {
      state.setStreaming(false);
      _showMessage('無法啟動 RTSP 串流\n\n提示：\n1. 確認設備已啟動即時預覽（命令 2015）\n2. 確認設備在 Live view state\n3. 檢查網絡連接\n4. 確認 RTSP URL 正確：rtsp://192.168.1.254/xxxx.mov');
    }
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
  /// 每15秒發送一次心跳並重新打開連接，在30秒超時前刷新（更激進的策略）
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    
    _keepAliveTimer = Timer.periodic(Duration(seconds: 15), (timer) async {
      final state = Provider.of<AppState>(context, listen: false);
      
      // 只有在即時預覽狀態時才發送 keep-alive
      if (state.movieModeState == MovieModeState.liveView && 
          state.isStreaming && 
          _mediaKitPlayer != null) {
        try {
          // 方法1: 發送設備心跳命令，保持連接活躍
          await _deviceService.heartbeat();
          print('Keep-alive: 發送心跳成功');
          
          // 方法2: 在30秒超時前主動重新打開連接（每20秒執行一次）
          // 這樣可以在服務器超時前刷新連接，避免播放器停止
          try {
            if (!_mediaKitInitialized || _isRefreshing) {
              print('Keep-alive: 播放器未初始化或正在刷新，跳過');
              return;
            }
            
            // 檢查距離上次刷新的時間（縮短防抖時間，更頻繁刷新）
            final now = DateTime.now();
            if (_lastRefreshTime != null && 
                now.difference(_lastRefreshTime!).inSeconds < 10) {
              print('Keep-alive: 距離上次刷新太近，跳過（10秒防抖）');
              return;
            }
            
            // 在30秒超時前（15秒時）主動刷新連接
            // 使用無黑屏的刷新方式
            print('Keep-alive: 在30秒超時前主動刷新連接（15秒間隔，10秒防抖）');
            await _refreshRTSPStreamWithoutBlackScreen();
          } catch (e) {
            print('Keep-alive: 刷新連接時發生錯誤：$e');
          }
        } catch (e) {
          print('Keep-alive: 發送心跳失敗：$e');
          // 如果心跳失敗，嘗試重新連接串流
          if (state.streamUrl != null && state.streamUrl!.startsWith('rtsp://')) {
            await _reconnectStream();
          }
        }
      } else {
        // 如果不在即時預覽狀態，停止 keep-alive
        timer.cancel();
        _keepAliveTimer = null;
      }
    });
  }
  
  /// 刷新 RTSP 串流（無黑屏方式：通過 seek 到當前位置來刷新連接）
  /// 這會在30秒超時前刷新連接，避免播放器停止
  /// 使用 seek 而不是重新打開連接，可以避免黑屏
  Future<void> _refreshRTSPStreamWithoutBlackScreen() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (state.movieModeState != MovieModeState.liveView || 
        state.streamUrl == null || 
        !state.streamUrl!.startsWith('rtsp://') ||
        _mediaKitPlayer == null) {
      return;
    }
    
    // 防止重複刷新
    if (_isRefreshing) {
      print('正在刷新中，跳過重複請求');
      return;
    }
    
    _isRefreshing = true;
    _lastRefreshTime = DateTime.now();
    
    try {
      print('刷新 RTSP 串流（無黑屏模式）：通過 seek 刷新連接');
      
      // 方法1: 嘗試使用 seek 來刷新連接（對於實時串流可能無效，但可以嘗試）
      try {
        // 獲取當前播放位置
        final position = _mediaKitPlayer!.position;
        if (position != null) {
          // seek 到當前位置，這會觸發 RTSP 重新協商
          await _mediaKitPlayer!.seek(position);
          print('刷新 RTSP 串流成功（通過 seek，無黑屏）');
        } else {
          throw Exception('無法獲取播放位置');
        }
      } catch (e) {
        print('Seek 刷新失敗：$e，嘗試重新打開連接');
        
        // 方法2: 如果 seek 失敗，嘗試重新打開連接（不停止播放器）
        try {
          // 直接打開新連接，不調用 stop()
          // 這會建立新的 RTSP 會話，但保持播放器運行
          await _mediaKitPlayer!.open(Media(state.streamUrl!));
          
          // 等待連接建立（較短時間）
          await Future.delayed(Duration(milliseconds: 150));
          
          // 確保播放器正在播放
          try {
            await _mediaKitPlayer!.play();
          } catch (e2) {
            // 如果已經在播放，可能會拋出錯誤，這是正常的
            print('播放器可能已經在播放（可忽略）：$e2');
          }
          
          // 等待播放器真正開始播放
          await Future.delayed(Duration(milliseconds: 200));
          
          print('刷新 RTSP 串流成功（重新打開連接，無黑屏）');
        } catch (e2) {
          print('重新打開連接失敗：$e2');
          throw e2;
        }
      }
      
      // 更新狀態
      if (mounted) {
        setState(() {
          _mediaKitInitialized = true;
        });
      }
    } catch (e) {
      print('刷新 RTSP 串流失敗：$e');
      // 如果刷新失敗，不立即重新連接，等待下次 keep-alive
      // 或者讓播放器狀態監聽器處理
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// 刷新 RTSP 串流（使用備用播放器實現無縫切換，避免黑屏）
  /// 在後台準備新連接，然後快速切換，確保畫面不中斷
  Future<void> _refreshRTSPStream() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (state.movieModeState != MovieModeState.liveView || 
        state.streamUrl == null || 
        !state.streamUrl!.startsWith('rtsp://') ||
        _mediaKitPlayer == null) {
      return;
    }
    
    // 防止重複刷新
    if (_isRefreshing) {
      print('正在刷新中，跳過重複請求');
      return;
    }
    
    _isRefreshing = true;
    _lastRefreshTime = DateTime.now();
    
    try {
      print('刷新 RTSP 串流：使用備用播放器實現無縫切換');
      
      // 方法：不刷新當前播放器，而是通過發送 RTSP OPTIONS 請求來保持連接活躍
      // 或者簡單地調用 play() 來發送 RTSP PLAY 請求，這不會中斷當前播放
      // 這比重新打開連接更安全，不會導致黑屏
      
      // 嘗試通過發送播放命令來刷新連接（這會發送 RTSP PLAY 請求）
      // 如果連接已經斷開，這會觸發重新連接，但不會導致黑屏
      try {
        // 先暫停一小段時間（非常短，用戶不會察覺）
        // 然後立即恢復播放，這會觸發 RTSP 重新協商
        await _mediaKitPlayer!.pause();
        await Future.delayed(Duration(milliseconds: 50)); // 非常短的暫停
        await _mediaKitPlayer!.play();
        
        print('刷新 RTSP 串流成功：通過暫停/播放刷新連接（無黑屏）');
      } catch (e) {
        print('暫停/播放刷新失敗：$e，嘗試重新打開連接');
        
        // 如果暫停/播放失敗，則需要重新打開連接
        // 但這次我們不停止播放器，直接打開新連接
        try {
          // 直接打開新連接，不停止當前播放
          // media_kit 應該能夠處理這種情況
          await _mediaKitPlayer!.open(Media(state.streamUrl!));
          await Future.delayed(Duration(milliseconds: 200));
          await _mediaKitPlayer!.play();
          
          print('刷新 RTSP 串流成功：重新打開連接');
        } catch (e2) {
          print('重新打開連接失敗：$e2');
          throw e2;
        }
      }
      
      // 更新狀態
      if (mounted) {
        setState(() {
          _mediaKitInitialized = true;
        });
      }
      
    } catch (e) {
      print('刷新 RTSP 串流失敗：$e');
      // 如果刷新失敗，嘗試完全重新連接
      if (mounted && state.movieModeState == MovieModeState.liveView) {
        await _reconnectStream();
      }
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// 重新連接串流（使用無黑屏方式，不重新創建播放器）
  /// 改進：不停止播放器，直接重新打開連接，避免黑屏
  Future<void> _reconnectStream() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    if (state.movieModeState != MovieModeState.liveView) {
      return;
    }
    
    // 防止重複重連
    if (_isReconnecting) {
      print('正在重新連接中，跳過重複請求');
      return;
    }
    
    _isReconnecting = true;
    print('重新連接 RTSP 串流（無黑屏模式）...');
    
    try {
      // 不停止播放器，直接使用無黑屏刷新方式
      if (_mediaKitPlayer != null && state.streamUrl != null) {
        try {
          // 使用無黑屏刷新方式，不重新創建播放器
          await _refreshRTSPStreamWithoutBlackScreen();
          print('重新連接 RTSP 串流成功（使用無黑屏方式）');
        } catch (e) {
          print('無黑屏刷新失敗：$e，嘗試完全重新連接');
          // 只有在無黑屏刷新失敗時才完全重新連接
          // 先停止當前播放器
          try {
            await _mediaKitPlayer!.stop();
          } catch (e2) {
            print('停止播放器時出錯（可忽略）：$e2');
          }
          
          // 等待一小段時間
          await Future.delayed(Duration(milliseconds: 300));
          
          // 重新啟動串流
          await _startStream();
          
          // 等待播放器初始化
          await Future.delayed(Duration(milliseconds: 500));
          
          // 刷新 UI
          if (mounted) {
            setState(() {
              _mediaKitInitialized = true;
            });
          }
          
          print('重新連接 RTSP 串流成功（完全重新連接）');
        }
      } else {
        // 如果播放器不存在，重新啟動串流
        await _startStream();
      }
    } catch (e) {
      print('重新連接 RTSP 串流失敗：$e');
      if (mounted) {
        setState(() {
          _useFallbackViewer = true;
        });
      }
    } finally {
      _isReconnecting = false;
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
      appBar: AppBar(
        title: Text('實時影像瀏覽'),
        actions: [
          Consumer<AppState>(
            builder: (context, state, _) {
              return IconButton(
                icon: Icon(state.isConnected ? Icons.wifi : Icons.wifi_off),
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
          return Column(
            children: [
              // 串流顯示區域
              Expanded(
                child: _buildStreamView(state),
              ),
              // 控制按鈕區域
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
    
    // 如果使用 media_kit 播放器（RTSP）
    if (!_useFallbackViewer && state.streamUrl != null && state.streamUrl!.startsWith('rtsp://')) {
      if (_mediaKitPlayer != null && _videoControllerKit != null) {
        print('構建 media_kit Video widget，播放器狀態：_mediaKitInitialized=$_mediaKitInitialized');
        
        // 使用 media_kit 的 Video widget
        return Video(
          controller: _videoControllerKit!,
          controls: AdaptiveVideoControls,
          fill: Colors.black,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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

