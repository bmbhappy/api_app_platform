import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nt96650_app/services/device_service.dart';
import 'package:nt96650_app/state/app_state.dart';
import 'package:video_player/video_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 播放已錄製的文件（使用 RTSP）
class PlaybackPage extends StatefulWidget {
  final String fileName; // 例如：xxxx.mov 或 xxxx.mp4
  
  const PlaybackPage({Key? key, required this.fileName}) : super(key: key);
  
  @override
  _PlaybackPageState createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage> {
  final DeviceService _deviceService = DeviceService();
  VideoPlayerController? _videoController;
  Player? _mediaKitPlayer; // media_kit Player
  VideoController? _videoControllerKit; // media_kit VideoController
  bool _isLoading = false;
  String? _error;
  bool _useMediaKit = false;
  
  @override
  void initState() {
    super.initState();
    _loadVideo();
  }
  
  @override
  void dispose() {
    _videoController?.dispose();
    _mediaKitPlayer?.dispose();
    // VideoController 不需要手動 dispose，它會隨 Player 一起釋放
    _videoControllerKit = null;
    super.dispose();
  }
  
  Future<void> _loadVideo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    final state = Provider.of<AppState>(context, listen: false);
    final ip = state.deviceIp ?? '192.168.1.254';
    
    // RTSP URL 格式：rtsp://192.168.1.254/xxxx.mov 或 rtsp://192.168.1.254/xxxx.mp4
    final rtspUrl = 'rtsp://$ip/${widget.fileName}';
    
    try {
      // 確保設備在 Movie 模式（默認就是 Movie 模式）
      if (state.deviceMode != DeviceMode.movie) {
        await _deviceService.modechange(1);
        state.setDeviceMode(DeviceMode.movie);
      }
      
      // RTSP 使用 media_kit 播放器
      try {
        // 確保 media_kit 已初始化
        MediaKit.ensureInitialized();
        
        // 創建新的 media_kit Player
        _mediaKitPlayer = Player(
          configuration: const PlayerConfiguration(
            vo: 'gpu', // 使用 GPU 加速
          ),
        );
        
        // 創建 VideoController
        _videoControllerKit = VideoController(_mediaKitPlayer!);
        
        // 監聽播放器狀態
        _mediaKitPlayer!.stream.playing.listen((playing) {
          if (mounted) {
            setState(() {});
          }
        });
        
        _mediaKitPlayer!.stream.error.listen((error) {
          print('media_kit 播放錯誤：$error');
          if (mounted) {
            setState(() {
              _error = '播放錯誤：$error';
              _isLoading = false;
            });
          }
        });
        
        // 打開媒體並開始播放
        await _mediaKitPlayer!.open(Media(rtspUrl));
        await _mediaKitPlayer!.play();
        
        setState(() {
          _isLoading = false;
          _useMediaKit = true;
        });
      } catch (e) {
        // 如果 media_kit 失敗，嘗試 video_player（可能不支持）
        print('media_kit 播放失敗，嘗試 video_player：$e');
        await _mediaKitPlayer?.dispose();
        _mediaKitPlayer = null;
        _videoControllerKit = null;
        
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(rtspUrl),
        );
        
        await _videoController!.initialize();
        await _videoController!.play();
        
        setState(() {
          _isLoading = false;
          _useMediaKit = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '播放失敗：$e\n\n提示：\n1. 確認文件名正確\n2. 檢查網絡連接\n3. 確認設備在 Movie 模式';
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('播放：${widget.fileName}'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadVideo,
          ),
        ],
      ),
      body: _buildContent(),
    );
  }
  
  Widget _buildContent() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                '播放失敗',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadVideo,
                child: Text('重試'),
              ),
              SizedBox(height: 16),
              Text(
                '提示：如果 video_player 不支持 RTSP，\n可以使用 VLC 播放器打開：\nrtsp://192.168.1.254/${widget.fileName}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_useMediaKit && _mediaKitPlayer != null && _videoControllerKit != null) {
      return Column(
        children: [
          Expanded(
            child: Video(
              controller: _videoControllerKit!,
              controls: AdaptiveVideoControls,
              fill: Colors.black,
            ),
          ),
          _buildMediaKitControls(),
        ],
      );
    }
    
    if (!_useMediaKit && _videoController != null && _videoController!.value.isInitialized) {
      return Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
          VideoProgressIndicator(_videoController!, allowScrubbing: true),
          _buildControls(),
        ],
      );
    }
    
    return Center(child: Text('準備播放...'));
  }
  
  Widget _buildControls() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(_videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
              setState(() {});
            },
          ),
          IconButton(
            icon: Icon(Icons.stop),
            onPressed: () {
              _videoController!.pause();
              _videoController!.seekTo(Duration.zero);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildMediaKitControls() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.pause),
            onPressed: () {
              _mediaKitPlayer?.pause();
              setState(() {});
            },
          ),
          IconButton(
            icon: Icon(Icons.play_arrow),
            onPressed: () {
              _mediaKitPlayer?.play();
              setState(() {});
            },
          ),
          IconButton(
            icon: Icon(Icons.stop),
            onPressed: () {
              _mediaKitPlayer?.stop();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

