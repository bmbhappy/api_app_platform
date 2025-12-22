import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nt96650_app/services/device_service.dart';
import 'package:nt96650_app/services/socket_service.dart';
import 'package:nt96650_app/state/app_state.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

/// 4. 裝置 Wi-Fi 連結設定
class WifiConnectionPage extends StatefulWidget {
  @override
  _WifiConnectionPageState createState() => _WifiConnectionPageState();
}

class _WifiConnectionPageState extends State<WifiConnectionPage> {
  final DeviceService _deviceService = DeviceService();
  final SocketService _socketService = SocketService();
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.1.254',
  );
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isConnecting = false;
  bool _isScanning = false;
  List<WiFiAccessPoint> _availableNetworks = [];
  String? _selectedSsid;
  List<Map<String, String>> _savedWiFiList = []; // 保存的 Wi-Fi 列表
  
  @override
  void initState() {
    super.initState();
    final state = Provider.of<AppState>(context, listen: false);
    if (state.deviceIp != null) {
      _ipController.text = state.deviceIp!;
    }
    // 延遲初始化，避免在 IndexedStack 中立即執行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadConnectionStatus();
        _loadSavedWiFiCredentials();
        _loadSavedWiFiList();
      }
    });
  }
  
  @override
  void dispose() {
    _ipController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  void _loadConnectionStatus() {
    final state = Provider.of<AppState>(context, listen: false);
    if (state.isConnected) {
      _ipController.text = state.deviceIp ?? '192.168.1.254';
    }
  }
  
  /// 載入保存的 Wi-Fi 憑證（兼容舊版本，載入最後一個）
  Future<void> _loadSavedWiFiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSsid = prefs.getString('wifi_ssid');
      final savedPassword = prefs.getString('wifi_password');
      
      if (savedSsid != null) {
        _ssidController.text = savedSsid;
      }
      if (savedPassword != null && savedPassword.isNotEmpty) {
        _passwordController.text = savedPassword;
      }
    } catch (e) {
      print('載入保存的 Wi-Fi 憑證失敗：$e');
    }
  }
  
  /// 載入保存的 Wi-Fi 列表
  Future<void> _loadSavedWiFiList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wifiListJson = prefs.getString('wifi_list');
      
      if (wifiListJson != null && wifiListJson.isNotEmpty) {
        // 解析 JSON 字符串
        final List<dynamic> decoded = 
            wifiListJson.split('|||').map((item) {
          final parts = item.split(':::');
          if (parts.length >= 2) {
            return {'ssid': parts[0], 'password': parts[1]};
          }
          return null;
        }).where((item) => item != null).toList();
        
        setState(() {
          _savedWiFiList = decoded.cast<Map<String, String>>();
        });
      }
    } catch (e) {
      print('載入 Wi-Fi 列表失敗：$e');
    }
  }
  
  /// 保存 Wi-Fi 列表
  Future<void> _saveWiFiList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 使用簡單的格式：ssid:::password|||ssid2:::password2
      final wifiListJson = _savedWiFiList
          .map((wifi) => '${wifi['ssid']}:::${wifi['password'] ?? ''}')
          .join('|||');
      await prefs.setString('wifi_list', wifiListJson);
      print('Wi-Fi 列表已保存，共 ${_savedWiFiList.length} 個');
    } catch (e) {
      print('保存 Wi-Fi 列表失敗：$e');
    }
  }
  
  /// 載入特定 SSID 的密碼（從列表中查找）
  Future<void> _loadPasswordForSsid(String ssid) async {
    try {
      // 先從列表中查找
      final wifi = _savedWiFiList.firstWhere(
        (w) => w['ssid'] == ssid,
        orElse: () => {},
      );
      
      if (wifi.isNotEmpty && wifi['password'] != null && wifi['password']!.isNotEmpty) {
        setState(() {
          _passwordController.text = wifi['password']!;
        });
        return;
      }
      
      // 如果列表中沒有，嘗試從舊的保存方式載入（兼容舊版本）
      final prefs = await SharedPreferences.getInstance();
      final savedSsid = prefs.getString('wifi_ssid');
      final savedPassword = prefs.getString('wifi_password');
      
      // 如果選擇的 SSID 與保存的 SSID 匹配，載入密碼
      if (savedSsid == ssid && savedPassword != null && savedPassword.isNotEmpty) {
        setState(() {
          _passwordController.text = savedPassword;
        });
      }
    } catch (e) {
      print('載入 SSID 密碼失敗：$e');
    }
  }
  
  /// 保存 Wi-Fi 憑證（兼容舊版本）
  Future<void> _saveWiFiCredentials(String ssid, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wifi_ssid', ssid);
      await prefs.setString('wifi_password', password);
      print('Wi-Fi 憑證已保存');
    } catch (e) {
      print('保存 Wi-Fi 憑證失敗：$e');
    }
  }
  
  /// 添加 Wi-Fi 到列表（如果不存在則添加，存在則更新）
  Future<void> _addWiFiToList(String ssid, String password) async {
    // 檢查是否已存在
    final existingIndex = _savedWiFiList.indexWhere((wifi) => wifi['ssid'] == ssid);
    
    if (existingIndex >= 0) {
      // 更新現有項目
      _savedWiFiList[existingIndex] = {'ssid': ssid, 'password': password};
    } else {
      // 添加新項目
      _savedWiFiList.add({'ssid': ssid, 'password': password});
    }
    
    await _saveWiFiList();
    setState(() {});
  }
  
  /// 從列表中刪除 Wi-Fi
  Future<void> _deleteWiFiFromList(String ssid) async {
    _savedWiFiList.removeWhere((wifi) => wifi['ssid'] == ssid);
    await _saveWiFiList();
    setState(() {});
  }
  
  /// 從列表中選擇 Wi-Fi
  void _selectWiFiFromList(String ssid, String password) {
    setState(() {
      _ssidController.text = ssid;
      _passwordController.text = password;
      _selectedSsid = ssid;
    });
    _showMessage('已選擇 Wi-Fi: $ssid');
  }
  
  /// 確認刪除 Wi-Fi
  void _confirmDeleteWiFi(String ssid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('確認刪除'),
        content: Text('確定要刪除 Wi-Fi "$ssid" 嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _deleteWiFiFromList(ssid);
              Navigator.pop(context);
              _showMessage('已刪除 Wi-Fi: $ssid');
            },
            child: Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  /// 顯示 Wi-Fi 列表對話框
  void _showWiFiListDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('已保存的 Wi-Fi 列表'),
        content: Container(
          width: double.maxFinite,
          child: _savedWiFiList.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('暫無保存的 Wi-Fi'),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _savedWiFiList.length,
                  itemBuilder: (context, index) {
                    final wifi = _savedWiFiList[index];
                    return ListTile(
                      leading: Icon(Icons.wifi, color: Colors.blue),
                      title: Text(wifi['ssid'] ?? ''),
                      subtitle: Text(
                        wifi['password']?.isNotEmpty == true 
                            ? '已保存密碼' 
                            : '無密碼',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, size: 20),
                            onPressed: () {
                              Navigator.pop(context);
                              _selectWiFiFromList(
                                wifi['ssid'] ?? '',
                                wifi['password'] ?? '',
                              );
                            },
                            tooltip: '使用此 Wi-Fi',
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, size: 20, color: Colors.red),
                            onPressed: () {
                              Navigator.pop(context);
                              _confirmDeleteWiFi(wifi['ssid'] ?? '');
                            },
                            tooltip: '刪除',
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _selectWiFiFromList(
                          wifi['ssid'] ?? '',
                          wifi['password'] ?? '',
                        );
                      },
                    );
                  },
                ),
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
  
  /// 掃描 Wi-Fi 網絡
  Future<void> _scanWiFiNetworks() async {
    // 檢查平台（僅 Android 支持）
    if (!Platform.isAndroid) {
      _showMessage('Wi-Fi 掃描僅支持 Android 平台');
      return;
    }
    
    setState(() => _isScanning = true);
    
    try {
      // 檢查並請求位置權限（Android 掃描 Wi-Fi 需要位置權限）
      PermissionStatus locationStatus = await Permission.location.status;
      
      if (!locationStatus.isGranted) {
        // 如果權限被永久拒絕，引導用戶到設置
        if (locationStatus.isPermanentlyDenied) {
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('需要位置權限'),
              content: Text(
                '掃描 Wi-Fi 網絡需要位置權限。\n\n'
                '這是 Android 系統的要求，因為 Wi-Fi 掃描可以推斷設備位置。\n\n'
                '請在設置中授予位置權限。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('打開設置'),
                ),
              ],
            ),
          );
          
          if (shouldOpen == true) {
            await openAppSettings();
          }
          setState(() => _isScanning = false);
          return;
        }
        
        // 請求權限
        locationStatus = await Permission.location.request();
        
        if (!locationStatus.isGranted) {
          _showMessage('需要位置權限才能掃描 Wi-Fi 網絡');
          setState(() => _isScanning = false);
          return;
        }
      }
      
      // 檢查精確位置權限（Android 10+ 需要）
      if (await Permission.locationWhenInUse.isDenied) {
        final preciseLocationStatus = await Permission.locationWhenInUse.request();
        if (preciseLocationStatus.isDenied) {
          _showMessage('建議授予精確位置權限以獲得更好的掃描結果');
        }
      }
      
      // 檢查 Wi-Fi 掃描是否可用
      final canGetScannedResults = await WiFiScan.instance.canGetScannedResults();
      
      if (canGetScannedResults == CanGetScannedResults.yes) {
        // 獲取已掃描的結果
        final accessPoints = await WiFiScan.instance.getScannedResults();
        
        setState(() {
          _availableNetworks = accessPoints;
          _isScanning = false;
        });
        
        if (_availableNetworks.isEmpty) {
          _showMessage('未找到 Wi-Fi 網絡，請嘗試手動掃描');
        } else {
          _showMessage('找到 ${_availableNetworks.length} 個 Wi-Fi 網絡');
          _showNetworkSelectionDialog();
        }
      } else {
        // 需要手動觸發掃描
        final result = await WiFiScan.instance.startScan();
        
        if (result) {
          // 等待掃描完成
          await Future.delayed(Duration(seconds: 2));
          
          // 獲取掃描結果
          final accessPoints = await WiFiScan.instance.getScannedResults();
          
          setState(() {
            _availableNetworks = accessPoints;
            _isScanning = false;
          });
          
          if (_availableNetworks.isEmpty) {
            _showMessage('未找到 Wi-Fi 網絡');
          } else {
            _showMessage('找到 ${_availableNetworks.length} 個 Wi-Fi 網絡');
            _showNetworkSelectionDialog();
          }
        } else {
          setState(() => _isScanning = false);
          _showMessage('掃描失敗，請檢查權限設置');
        }
      }
    } catch (e) {
      setState(() => _isScanning = false);
      _showMessage('掃描錯誤：$e');
    }
  }
  
  /// 顯示網絡選擇對話框
  void _showNetworkSelectionDialog() {
    if (_availableNetworks.isEmpty) {
      _showMessage('沒有可用的 Wi-Fi 網絡');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('選擇 Wi-Fi 網絡'),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _availableNetworks.length,
            itemBuilder: (context, index) {
              final network = _availableNetworks[index];
              final isSelected = _selectedSsid == network.ssid;
              
              return ListTile(
                leading: Icon(
                  network.capabilities.contains('WPA') || network.capabilities.contains('WPA2')
                      ? Icons.lock
                      : Icons.lock_open,
                  color: isSelected ? Colors.blue : Colors.grey,
                ),
                title: Text(network.ssid.isEmpty ? '(隱藏網絡)' : network.ssid),
                subtitle: Text(
                  '信號強度: ${network.level} dBm\n'
                  '頻段: ${network.frequency} MHz\n'
                  '加密: ${network.capabilities}',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: isSelected ? Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  setState(() {
                    _selectedSsid = network.ssid;
                    _ssidController.text = network.ssid;
                  });
                  Navigator.pop(context);
                  _showMessage('已選擇：${network.ssid}');
                  // 如果之前保存過這個 SSID 的密碼，自動載入
                  _loadPasswordForSsid(network.ssid);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
        ],
      ),
    );
  }
  
  /// 連接到設備（步驟 1-3：Wi-Fi 連接流程）
  Future<void> _connectToDevice() async {
    final state = Provider.of<AppState>(context, listen: false);
    final ip = _ipController.text.trim();
    
    if (ip.isEmpty) {
      _showMessage('請輸入設備 IP 地址');
      return;
    }
    
    setState(() => _isConnecting = true);
    
    try {
      // 步驟 1: 設置設備 IP
      _deviceService.setDeviceIp(ip);
      
      // 步驟 2: 測試連接（發送心跳命令）
      final heartbeatResult = await _deviceService.heartbeat();
      
      if (heartbeatResult['status'] == 'success') {
        // 步驟 3: 連接成功，更新狀態
        state.setConnected(true, ip: ip);
        
        // 步驟 4: 啟動 Socket 通知連接
        await _startSocketConnection(ip);
        
        _showMessage('連接成功！');
      } else {
        state.setConnected(false);
        _showMessage('連接失敗：設備無回應');
      }
    } catch (e) {
      state.setConnected(false);
      _showMessage('連接錯誤：$e');
    } finally {
      setState(() => _isConnecting = false);
    }
  }
  
  /// 啟動 Socket 通知連接（Port 3333）
  Future<void> _startSocketConnection(String ip) async {
    final state = Provider.of<AppState>(context, listen: false);
    
    try {
      await _socketService.connect(ip, 3333);
      state.setSocketConnected(true);
      
      // 監聽通知
      _socketService.onNotification = (notification) {
        state.addNotification(notification);
        _showMessage('設備通知：$notification');
      };
      
      _showMessage('Socket 通知已連接');
    } catch (e) {
      state.setSocketConnected(false);
      _showMessage('Socket 連接失敗：$e');
    }
  }
  
  /// 斷開連接
  Future<void> _disconnect() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    await _socketService.disconnect();
    state.setSocketConnected(false);
    state.setConnected(false);
    
    _showMessage('已斷開連接');
  }
  
  /// 重新連接 Wi-Fi
  Future<void> _reconnectWiFi() async {
    try {
      final result = await _deviceService.reconnectWiFi();
      if (result['status'] == 'success') {
        _showMessage('Wi-Fi 重新連接中...');
      } else {
        _showMessage('重新連接失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  /// 設定 Wi-Fi SSID 和密碼
  Future<void> _setWiFiCredentials() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();
    
    if (ssid.isEmpty) {
      _showMessage('請輸入 SSID');
      return;
    }
    
    try {
      // 設定 SSID
      final ssidResult = await _deviceService.setssid(ssid);
      
      if (ssidResult['status'] == 'success') {
        // 設定密碼
        if (password.isNotEmpty) {
          final passResult = await _deviceService.setpassphrase(password);
          if (passResult['status'] == 'success') {
            // 保存 Wi-Fi 憑證到本地（兼容舊版本）
            await _saveWiFiCredentials(ssid, password);
            // 添加到列表
            await _addWiFiToList(ssid, password);
            _showMessage('Wi-Fi 設定成功，憑證已保存');
          } else {
            _showMessage('設定密碼失敗：${passResult['message']}');
          }
        } else {
          // 即使沒有密碼也保存 SSID
          await _saveWiFiCredentials(ssid, '');
          await _addWiFiToList(ssid, '');
          _showMessage('SSID 設定成功，已保存');
        }
      } else {
        _showMessage('設定 SSID 失敗：${ssidResult['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  /// 查詢設備狀態
  Future<void> _queryDeviceStatus() async {
    try {
      final result = await _deviceService.querycurrentstatus();
      if (result['status'] == 'success') {
        _showStatusDialog(result);
      } else {
        _showMessage('查詢失敗：${result['message']}');
      }
    } catch (e) {
      _showMessage('錯誤：$e');
    }
  }
  
  void _showStatusDialog(Map<String, dynamic> status) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('設備狀態'),
        content: SingleChildScrollView(
          child: Text(status.toString()),
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
  
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wi-Fi 連接設定'),
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          return ListView(
            padding: EdgeInsets.all(16),
            children: [
              // 連接狀態卡片
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            state.isConnected ? Icons.wifi : Icons.wifi_off,
                            color: state.isConnected ? Colors.green : Colors.grey,
                          ),
                          SizedBox(width: 8),
                          Text(
                            state.isConnected ? '已連接' : '未連接',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (state.isConnected) ...[
                        SizedBox(height: 8),
                        Text('設備 IP: ${state.deviceIp}'),
                        if (state.socketConnected)
                          Text('Socket: 已連接', style: TextStyle(color: Colors.green)),
                      ],
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              
              // IP 地址輸入
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: '設備 IP 地址',
                  hintText: '192.168.1.254',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
                keyboardType: TextInputType.number,
                enabled: !state.isConnected,
              ),
              
              SizedBox(height: 16),
              
              // 連接/斷開按鈕
              if (!state.isConnected)
                ElevatedButton.icon(
                  onPressed: _isConnecting ? null : _connectToDevice,
                  icon: _isConnecting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.link),
                  label: Text(_isConnecting ? '連接中...' : '連接到設備'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: Icon(Icons.link_off),
                  label: Text('斷開連接'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              
              SizedBox(height: 24),
              
              // Wi-Fi 設定區域
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wi-Fi 設定',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 16),
                      
                      TextField(
                        controller: _ssidController,
                        decoration: InputDecoration(
                          labelText: 'SSID',
                          hintText: '輸入或選擇 Wi-Fi 名稱',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.wifi),
                          helperText: '點擊下方按鈕掃描附近的 Wi-Fi 網絡',
                        ),
                        readOnly: false,
                      ),
                      
                      SizedBox(height: 12),
                      
                      // 掃描 Wi-Fi 按鈕（確保可見）
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isScanning ? null : _scanWiFiNetworks,
                          icon: _isScanning
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Icon(Icons.search),
                          label: Text(_isScanning ? '掃描中...' : '掃描 Wi-Fi 網絡'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '密碼',
                  hintText: '輸入 Wi-Fi 密碼',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              
              SizedBox(height: 16),
              
              ElevatedButton.icon(
                onPressed: _setWiFiCredentials,
                icon: Icon(Icons.settings),
                label: Text('設定 Wi-Fi'),
              ),
              
              SizedBox(height: 24),
              
              // 已保存的 Wi-Fi 列表
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '已保存的 Wi-Fi 列表',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          if (_savedWiFiList.isNotEmpty)
                            TextButton.icon(
                              onPressed: _showWiFiListDialog,
                              icon: Icon(Icons.list, size: 18),
                              label: Text('管理'),
                            ),
                        ],
                      ),
                      SizedBox(height: 12),
                      if (_savedWiFiList.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              '暫無保存的 Wi-Fi',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ...(_savedWiFiList.take(3).map((wifi) {
                          return ListTile(
                            leading: Icon(Icons.wifi, color: Colors.blue),
                            title: Text(wifi['ssid'] ?? ''),
                            subtitle: Text(
                              wifi['password']?.isNotEmpty == true 
                                  ? '已保存密碼' 
                                  : '無密碼',
                              style: TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, size: 20),
                                  onPressed: () => _selectWiFiFromList(
                                    wifi['ssid'] ?? '',
                                    wifi['password'] ?? '',
                                  ),
                                  tooltip: '使用此 Wi-Fi',
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, size: 20, color: Colors.red),
                                  onPressed: () => _confirmDeleteWiFi(wifi['ssid'] ?? ''),
                                  tooltip: '刪除',
                                ),
                              ],
                            ),
                            onTap: () => _selectWiFiFromList(
                              wifi['ssid'] ?? '',
                              wifi['password'] ?? '',
                            ),
                          );
                        }).toList()),
                      if (_savedWiFiList.length > 3)
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Center(
                            child: TextButton(
                              onPressed: _showWiFiListDialog,
                              child: Text('查看全部 (${_savedWiFiList.length} 個)'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              
              // 其他操作
              Divider(),
              SizedBox(height: 8),
              
              ListTile(
                leading: Icon(Icons.refresh),
                title: Text('重新連接 Wi-Fi'),
                trailing: Icon(Icons.chevron_right),
                onTap: _reconnectWiFi,
              ),
              
              ListTile(
                leading: Icon(Icons.info),
                title: Text('查詢設備狀態'),
                trailing: Icon(Icons.chevron_right),
                onTap: _queryDeviceStatus,
              ),
              
              // Socket 通知顯示
              if (state.lastNotification != null) ...[
                SizedBox(height: 16),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '最新通知',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(state.lastNotification!),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

