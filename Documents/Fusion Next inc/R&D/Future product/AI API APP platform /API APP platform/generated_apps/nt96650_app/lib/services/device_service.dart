import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

class DeviceService {
  static const String defaultIp = '192.168.1.254';
  static const int defaultPort = 80;
  String _deviceIp = defaultIp;
  
  void setDeviceIp(String ip) {
    _deviceIp = ip;
  }
  
  String get baseUrl => 'http://$_deviceIp';
  
  Future<Map<String, dynamic>> _sendCommand(
    int cmd, {
    int? par,
    String? str,
  }) async {
    try {
      // 構建 URL：http://192.168.1.254/?custom=1&cmd=XXXX&par=Y 或 &str=Z
      // 確保 baseUrl 以 / 結尾，這樣 queryParameters 會正確添加
      String url = baseUrl;
      if (!url.endsWith('/')) {
        url = '$url/';
      }
      
      final queryParams = <String, String>{
          'custom': '1',
          'cmd': cmd.toString(),
      };
      if (par != null) {
        queryParams['par'] = par.toString();
      }
      if (str != null) {
        queryParams['str'] = str;
      }
      
      final uri = Uri.parse(url).replace(queryParameters: queryParams);
      
      // 記錄發送的 URL（用於調試）
      print('發送命令: $uri');
      
      final response = await http.get(uri).timeout(
        Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('請求超時'),
      );
      
      if (response.statusCode == 200) {
        // 對於文件列表命令（3015），記錄原始 XML 響應（截取前 2000 字符）
        if (cmd == 3015) {
          final xmlPreview = response.body.length > 2000 
              ? '${response.body.substring(0, 2000)}...' 
              : response.body;
          print('文件列表 XML 響應（前 ${xmlPreview.length} 字符）: $xmlPreview');
          print('文件列表 XML 響應總長度: ${response.body.length} 字符');
        }
        
        // 對於文件列表命令（3015），如果解析失敗，視為空列表
        final result = _parseXmlResponse(response.body, cmd: cmd);
        
        // 如果是文件列表命令且解析失敗，視為空列表而不是錯誤
        if (cmd == 3015 && result['status'] == 'error') {
          final errorMsg = result['message'] ?? '';
          if (errorMsg.contains('XML 解析失敗') || 
              errorMsg.contains('No element') ||
              errorMsg.contains('Bad state')) {
            print('文件列表解析失敗，視為空列表: $errorMsg');
            return {
              'status': 'success',
              'fileList': <Map<String, dynamic>>[],
            };
          }
        }
        
        return result;
      } else {
        return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      // 對於文件列表命令，網路錯誤也視為空列表（可能是設備未連接）
      if (cmd == 3015) {
        print('文件列表請求失敗，視為空列表: $e');
        return {
          'status': 'success',
          'fileList': <Map<String, dynamic>>[],
        };
      }
      return {'status': 'error', 'message': e.toString()};
    }
  }
  
  Map<String, dynamic> _parseXmlResponse(String xmlString, {int? cmd}) {
    try {
      // 檢查 XML 是否為空或無效
      if (xmlString.trim().isEmpty) {
        return {'status': 'error', 'message': 'XML 響應為空'};
      }
      
      final document = xml.XmlDocument.parse(xmlString);
      
      // 對於 filelist 命令（cmd=3015），檢查是否有 LIST 元素（另一種 XML 格式）
      if (cmd == 3015) {
        print('開始解析文件列表 XML，cmd=3015');
        
        // 嘗試多種可能的 XML 結構
        // 1. <LIST><ALLFile><File> 結構
        final listElements = document.findElements('LIST');
        print('找到 ${listElements.length} 個 LIST 元素');
        
        if (listElements.isNotEmpty) {
          print('找到 ${listElements.length} 個 LIST 元素，將遍歷所有 LIST 元素');
          
          // 處理 <LIST><ALLFile><File> 結構
          // 重要：需要遍歷所有 LIST 元素，因為文件可能分布在多個 LIST 中
          final files = <Map<String, dynamic>>[];
          int processedCount = 0;
          
          try {
            // 遍歷所有 LIST 元素
            for (final listElement in listElements) {
              final allFileElements = listElement.findElements('ALLFile');
              print('在當前 LIST 元素中找到 ${allFileElements.length} 個 ALLFile 元素');
              
              // 遍歷當前 LIST 中的所有 ALLFile 元素
              for (final allFile in allFileElements) {
                try {
                  // 每個 ALLFile 中應該有一個 File 元素
                  final fileElements = allFile.findElements('File');
                  print('在當前 ALLFile 中找到 ${fileElements.length} 個 File 元素');
                  
                  for (final fileElement in fileElements) {
                    try {
                      final fileName = fileElement.findElements('NAME').firstOrNull?.innerText ?? '';
                      final filePath = fileElement.findElements('FPATH').firstOrNull?.innerText ?? '';
                      final fileSize = fileElement.findElements('SIZE').firstOrNull?.innerText;
                      final timeCode = fileElement.findElements('TIMECODE').firstOrNull?.innerText;
                      final time = fileElement.findElements('TIME').firstOrNull?.innerText;
                      
                      print('解析文件: name=$fileName, path=$filePath, size=$fileSize, time=$time');
                      
                      // 只有當文件名不為空時才添加
                      if (fileName.isNotEmpty) {
                        // 判斷文件類型
                        String? fileType;
                        if (fileName.toLowerCase().endsWith('.jpg') || 
                            fileName.toLowerCase().endsWith('.jpeg') ||
                            fileName.toLowerCase().endsWith('.png')) {
                          fileType = 'photo';
                        } else if (fileName.toLowerCase().endsWith('.mov') ||
                                   fileName.toLowerCase().endsWith('.mp4') ||
                                   fileName.toLowerCase().endsWith('.avi') ||
                                   fileName.toLowerCase().endsWith('.ts')) {
                          fileType = 'video';
                        }
                        
                        // 解析 TIME 字段（格式：2025/10/03 17:28:58）
                        String? fileDate;
                        String? fileTime;
                        if (time != null && time.isNotEmpty) {
                          final parts = time.split(' ');
                          if (parts.length >= 2) {
                            fileDate = parts[0].replaceAll('/', '-'); // 轉換為 2025-10-03
                            fileTime = parts[1]; // 17:28:58
                          }
                        }
                        
                        files.add({
                          'name': fileName,
                          'path': filePath,
                          'size': fileSize,
                          'timeCode': timeCode,
                          'time': time, // 原始時間字符串（格式：2025/10/03 17:28:58）
                          'date': fileDate, // 解析後的日期（格式：2025-10-03）
                          'timeOnly': fileTime, // 解析後的時間（格式：17:28:58）
                          'type': fileType,
                          'fullPath': filePath.isNotEmpty ? filePath : fileName,
                        });
                        processedCount++;
                      } else {
                        print('跳過空文件名的文件元素');
                      }
                    } catch (e) {
                      // 跳過無法解析的文件元素，繼續處理下一個
                      print('解析文件元素時出錯：$e');
                      continue;
                    }
                  }
                } catch (e) {
                  print('處理 ALLFile 元素時出錯：$e');
                  continue;
                }
              }
            }
            
            print('成功解析 $processedCount 個文件，總文件列表長度: ${files.length}');
            
            return {
              'status': 'success',
              'fileList': files,
              'message': files.isEmpty ? '沒有文件' : '已載入 ${files.length} 個文件',
            };
          } catch (e) {
            print('解析文件列表時出錯：$e');
            // 即使出錯也返回已解析的文件列表（可能部分成功）
            return {
              'status': 'success',
              'fileList': files,
              'message': '部分文件解析失敗，已載入 ${files.length} 個文件',
            };
          }
        } else {
          // 沒有 LIST 元素，嘗試其他 XML 結構
          print('沒有找到 LIST 元素，嘗試其他 XML 結構');
        }
      }
      
      final function = document.findElements('Function').firstOrNull;
      
      if (function == null) {
        // 如果沒有 Function 元素，但這是文件列表查詢，可能表示沒有文件
        // 檢查是否是文件列表命令（cmd=3015）
        if (cmd == 3015 || xmlString.contains('3015') || xmlString.contains('filelist')) {
          return {
            'status': 'success',
            'fileList': <Map<String, dynamic>>[],
            'message': '沒有文件',
          };
        }
        return {'status': 'error', 'message': 'XML 中找不到 Function 元素。響應內容: ${xmlString.substring(0, xmlString.length > 200 ? 200 : xmlString.length)}'};
      }
      
      final cmdStr = function.findElements('Cmd').firstOrNull?.innerText ?? '';
      final status = function.findElements('Status').firstOrNull?.innerText ?? '';
      
      final result = <String, dynamic>{
        'cmd': cmdStr,
        'status': status == '0' ? 'success' : 'error',
      };
      
      // 如果狀態不是成功，嘗試獲取錯誤信息
      if (status != '0' && status.isNotEmpty) {
        result['message'] = '設備返回錯誤狀態: $status';
      }
      
      // 解析其他可能的字段
      final file = function.findElements('File').firstOrNull;
      if (file != null) {
        result['file'] = <String, dynamic>{
          'name': file.findElements('NAME').firstOrNull?.innerText,
          'path': file.findElements('FPATH').firstOrNull?.innerText,
        };
      }
      
      final freePicNum = function.findElements('FREEPICNUM').firstOrNull;
      if (freePicNum != null) {
        result['freePicNum'] = freePicNum.innerText;
      }
      
      // 解析文件列表（FileList）
      // 如果沒有 FileList 元素，視為空列表（成功，但沒有文件）
      final fileList = function.findElements('FileList').firstOrNull;
      if (fileList != null) {
        final files = <Map<String, dynamic>>[];
        try {
          for (final fileElement in fileList.findElements('File')) {
            try {
              final fileName = fileElement.findElements('NAME').firstOrNull?.innerText ?? '';
              final filePath = fileElement.findElements('FPATH').firstOrNull?.innerText ?? '';
              final fileSize = fileElement.findElements('SIZE').firstOrNull?.innerText;
              final fileDate = fileElement.findElements('DATE').firstOrNull?.innerText;
              final fileTime = fileElement.findElements('TIME').firstOrNull?.innerText;
              
              // 只有當文件名不為空時才添加
              if (fileName.isNotEmpty) {
                // 判斷文件類型
                String? fileType;
                if (fileName.toLowerCase().endsWith('.jpg') || 
                    fileName.toLowerCase().endsWith('.jpeg') ||
                    fileName.toLowerCase().endsWith('.png')) {
                  fileType = 'photo';
                } else if (fileName.toLowerCase().endsWith('.mov') ||
                           fileName.toLowerCase().endsWith('.mp4') ||
                           fileName.toLowerCase().endsWith('.avi')) {
                  fileType = 'video';
                }
                
                files.add({
                  'name': fileName,
                  'path': filePath,
                  'size': fileSize,
                  'date': fileDate,
                  'time': fileTime,
                  'type': fileType,
                  'fullPath': filePath.isNotEmpty ? filePath : fileName,
                });
              }
            } catch (e) {
              // 跳過無法解析的文件元素，繼續處理下一個
              print('解析文件元素時出錯：$e');
              continue;
            }
          }
        } catch (e) {
          // 如果解析文件列表時出錯，返回空列表而不是錯誤
          print('解析文件列表時出錯：$e');
        }
        result['fileList'] = files;
      } else {
        // 沒有 FileList 元素，視為空列表（成功，但沒有文件）
        result['fileList'] = <Map<String, dynamic>>[];
      }
      
      // 解析磁盤空間信息
      final diskFreeSpace = function.findElements('FREESPACE').firstOrNull;
      if (diskFreeSpace != null) {
        result['freeSpace'] = diskFreeSpace.innerText;
      }
      
      // 解析下載 URL（cmd=3025）
      if (cmd == 3025) {
        final urlElement = function.findElements('URL').firstOrNull;
        if (urlElement != null) {
          result['url'] = urlElement.innerText;
        }
        // 也可能在根元素中
        final rootUrl = document.findElements('URL').firstOrNull;
        if (rootUrl != null) {
          result['url'] = rootUrl.innerText;
        }
      }
      
      return result;
    } catch (e) {
      return {'status': 'error', 'message': 'XML 解析失敗: $e'};
    }
  }

  Future<Map<String, dynamic>> capture() async {
    return await _sendCommand(1001);
  }

  Future<Map<String, dynamic>> capturesize(int par) async {
    return await _sendCommand(1002, par: par);
  }

  Future<Map<String, dynamic>> freecapturenumber() async {
    return await _sendCommand(1003);
  }

  Future<Map<String, dynamic>> movierecord(int par) async {
    return await _sendCommand(2001, par: par);
  }

  Future<Map<String, dynamic>> movierecordsize(int par) async {
    return await _sendCommand(2002, par: par);
  }

  Future<Map<String, dynamic>> cyclicrecord(int par) async {
    return await _sendCommand(2003, par: par);
  }

  Future<Map<String, dynamic>> moviehdr(int par) async {
    return await _sendCommand(2004, par: par);
  }

  Future<Map<String, dynamic>> movieev(int par) async {
    return await _sendCommand(2005, par: par);
  }

  Future<Map<String, dynamic>> motiondetection(int par) async {
    return await _sendCommand(2006, par: par);
  }

  Future<Map<String, dynamic>> movieaudio(int par) async {
    return await _sendCommand(2007, par: par);
  }

  Future<Map<String, dynamic>> moviedateinprint(int par) async {
    return await _sendCommand(2008, par: par);
  }

  Future<Map<String, dynamic>> moviemaxrecordtime() async {
    return await _sendCommand(2009);
  }

  Future<Map<String, dynamic>> movieliveviewsize(int par) async {
    return await _sendCommand(2010, par: par);
  }

  Future<Map<String, dynamic>> movieGSensorSensitivity(int par) async {
    return await _sendCommand(2011, par: par);
  }

  Future<Map<String, dynamic>> setAutoRecording(int par) async {
    return await _sendCommand(2012, par: par);
  }

  Future<Map<String, dynamic>> movierecordbitrate(String str) async {
    return await _sendCommand(2013, str: str);
  }

  Future<Map<String, dynamic>> movieliveviewbitrate(String str) async {
    return await _sendCommand(2014, str: str);
  }

  Future<Map<String, dynamic>> movieliveviewstart(int par) async {
    return await _sendCommand(2015, par: par);
  }

  Future<Map<String, dynamic>> movierecordingtime() async {
    return await _sendCommand(2016);
  }

  Future<Map<String, dynamic>> modechange(int par) async {
    return await _sendCommand(3001, par: par);
  }

  Future<Map<String, dynamic>> querystatus() async {
    return await _sendCommand(3002);
  }

  Future<Map<String, dynamic>> setssid(String str) async {
    return await _sendCommand(3003, str: str);
  }

  Future<Map<String, dynamic>> setpassphrase(String str) async {
    return await _sendCommand(3004, str: str);
  }

  Future<Map<String, dynamic>> setdate(String str) async {
    return await _sendCommand(3005, str: str);
  }

  Future<Map<String, dynamic>> settime(String str) async {
    return await _sendCommand(3006, str: str);
  }

  Future<Map<String, dynamic>> poweroff(int par) async {
    return await _sendCommand(3007, par: par);
  }

  Future<Map<String, dynamic>> language(int par) async {
    return await _sendCommand(3008, par: par);
  }

  Future<Map<String, dynamic>> tvformat(int par) async {
    return await _sendCommand(3009, par: par);
  }

  Future<Map<String, dynamic>> format(int par) async {
    return await _sendCommand(3010, par: par);
  }

  Future<Map<String, dynamic>> systemreset() async {
    return await _sendCommand(3011);
  }

  Future<Map<String, dynamic>> getversion() async {
    return await _sendCommand(3012);
  }

  Future<Map<String, dynamic>> firmwareupdate() async {
    return await _sendCommand(3013);
  }

  Future<Map<String, dynamic>> querycurrentstatus() async {
    return await _sendCommand(3014);
  }

  Future<Map<String, dynamic>> filelist() async {
    return await _sendCommand(3015);
  }

  Future<Map<String, dynamic>> heartbeat() async {
    return await _sendCommand(3016);
  }

  Future<Map<String, dynamic>> getdiskfreespace() async {
    return await _sendCommand(3017);
  }

  Future<Map<String, dynamic>> reconnectWiFi() async {
    return await _sendCommand(3018);
  }

  Future<Map<String, dynamic>> getbatterylevel() async {
    return await _sendCommand(3019);
  }

  Future<Map<String, dynamic>> savemenuinformation() async {
    return await _sendCommand(3021);
  }

  Future<Map<String, dynamic>> gethardwarecapacity() async {
    return await _sendCommand(3022);
  }

  Future<Map<String, dynamic>> removelastuser() async {
    return await _sendCommand(3023);
  }

  Future<Map<String, dynamic>> getcardstatus() async {
    return await _sendCommand(3024);
  }

  Future<Map<String, dynamic>> getupdatefwpath() async {
    return await _sendCommand(3026);
  }

  Future<Map<String, dynamic>> resultofhfsuploadfile() async {
    return await _sendCommand(3027);
  }

  /// 獲取縮圖
  /// filePath: 文件路徑，例如 "A:\\CARDV\\PHOTO\\2014_0506_000000.0001.JPG"
  /// 根據成功的 HTTP headers，縮圖 URL 格式為：http://192.168.1.254/CARDV/MOVIE/...?customer=1&cmd=4001
  Future<Map<String, dynamic>> getthumbnail(String filePath) async {
    try {
      // 需要將文件路徑轉換為 URL 格式
      String urlPath = filePath.replaceAll('\\', '/');
      
      // 處理 Windows 路徑格式（如 A:\CARDV\...）
      // 移除驅動器字母和冒號（如 A:）
      if (urlPath.contains(':')) {
        // 如果包含冒號，可能是 Windows 路徑格式
        // 例如 "A:/CARDV/MOVIE/..." 應該轉換為 "/CARDV/MOVIE/..."
        final parts = urlPath.split(':');
        if (parts.length > 1) {
          urlPath = parts[1]; // 取冒號後的部分
        }
      }
      
      // 確保路徑以 / 開頭
      if (!urlPath.startsWith('/')) {
        urlPath = '/$urlPath';
      }
      
      // 保持 CARDV 路徑（不轉換為 NOVATEK），根據成功的 HTTP headers 使用 CARDV
      
      String url = baseUrl;
      if (!url.endsWith('/')) {
        url = '$url/';
      }
      url = url.replaceAll(RegExp(r'/$'), '') + urlPath;
      
      final queryParams = <String, String>{
        'customer': '1',  // 注意：是 customer 不是 custom
        'cmd': '4001',
      };
      
      final uri = Uri.parse(url).replace(queryParameters: queryParams);
      print('獲取縮圖: $uri');
      
      final response = await http.get(uri).timeout(
        Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('請求超時'),
      );
      
      if (response.statusCode == 200) {
        // 驗證響應內容是否真的是圖片
        final contentType = response.headers['content-type'] ?? '';
        final bodyBytes = response.bodyBytes;
        
        // 檢查響應大小，如果太小可能不是有效的圖片
        if (bodyBytes.isEmpty) {
          return {'status': 'error', 'message': '響應為空'};
        }
        
        // 檢查是否是圖片格式（通過檢查文件頭）
        bool isImage = false;
        if (bodyBytes.length >= 2) {
          // JPEG: FF D8
          // PNG: 89 50
          // GIF: 47 49
          final header = bodyBytes.sublist(0, 2);
          if ((header[0] == 0xFF && header[1] == 0xD8) || // JPEG
              (header[0] == 0x89 && header[1] == 0x50) || // PNG
              (header[0] == 0x47 && header[1] == 0x49)) { // GIF
            isImage = true;
          }
        }
        
        if (!isImage && !contentType.contains('image')) {
          // 如果不是圖片格式，返回錯誤
          return {'status': 'error', 'message': '響應不是有效的圖片格式'};
        }
        
        // 返回圖片數據
        return {
          'status': 'success',
          'imageData': bodyBytes,
          'contentType': contentType.isNotEmpty ? contentType : 'image/jpeg',
        };
      } else {
        return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      print('獲取縮圖錯誤: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// 獲取屏幕縮圖
  /// filePath: 文件路徑，例如 "A:\\CARDV\\PHOTO\\2014_0506_000000.0001.JPG"
  /// 根據成功的 HTTP headers，屏幕縮圖 URL 格式應為：http://192.168.1.254/CARDV/MOVIE/...?customer=1&cmd=4002
  Future<Map<String, dynamic>> getscreennail(String filePath) async {
    try {
      String urlPath = filePath.replaceAll('\\', '/');
      
      // 處理 Windows 路徑格式（如 A:\CARDV\...）
      if (urlPath.contains(':')) {
        final parts = urlPath.split(':');
        if (parts.length > 1) {
          urlPath = parts[1]; // 取冒號後的部分
        }
      }
      
      if (!urlPath.startsWith('/')) {
        urlPath = '/$urlPath';
      }
      
      // 保持 CARDV 路徑（不轉換為 NOVATEK），根據成功的 HTTP headers 使用 CARDV
      
      String url = baseUrl;
      if (!url.endsWith('/')) {
        url = '$url/';
      }
      url = url.replaceAll(RegExp(r'/$'), '') + urlPath;
      
      final queryParams = <String, String>{
        'customer': '1',  // 注意：是 customer 不是 custom
        'cmd': '4002',
      };
      
      final uri = Uri.parse(url).replace(queryParameters: queryParams);
      print('獲取屏幕縮圖: $uri');
      
      final response = await http.get(uri).timeout(
        Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('請求超時'),
      );
      
      if (response.statusCode == 200) {
        // 返回圖片數據
        return {
          'status': 'success',
          'imageData': response.bodyBytes,
          'contentType': response.headers['content-type'] ?? 'image/jpeg',
        };
      } else {
        return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
  
  /// 獲取下載 URL
  /// filePath: 文件路徑
  Future<Map<String, dynamic>> getdownloadurl(String filePath) async {
    return await _sendCommand(3025, str: filePath);
  }
  
  /// 構建文件下載 URL
  /// 設備使用 HFS (HTTP File Server)，可以直接通過 HTTP GET 訪問文件路徑
  /// 成功的 URL 格式：http://192.168.1.254/CARDV/MOVIE/文件名（不使用查詢參數）
  /// filePath: 文件路徑，例如 "A:\CARDV\MOVIE\20251003172400_000001A.TS"
  /// 注意：下載使用 CARDV 路徑，不需要轉換為 NOVATEK（縮圖 API 使用 NOVATEK，但下載使用 CARDV）
  String buildDownloadUrl(String filePath) {
    String urlPath = filePath.replaceAll('\\', '/');
    
    // 移除驅動器字母和冒號（例如 "A:/CARDV/..." -> "/CARDV/..."）
    if (urlPath.length > 2 && urlPath[1] == ':') {
      urlPath = urlPath.substring(2);
    }
    
    // 確保路徑以 / 開頭
    if (!urlPath.startsWith('/')) {
      urlPath = '/$urlPath';
    }
    
    // 保持 CARDV 路徑（不轉換為 NOVATEK），因為 HFS 直接訪問使用 CARDV 路徑
    // 根據成功的 HTTP headers，直接訪問 http://192.168.1.254/CARDV/MOVIE 可以正常工作
    
    String url = baseUrl;
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    url = url.replaceAll(RegExp(r'/$'), '') + urlPath;
    
    // 不使用查詢參數（根據成功的 HTTP headers，HFS 直接訪問不需要查詢參數）
    print('構建下載 URL（HFS 直接訪問）: $url (原始路徑: $filePath, 轉換後路徑: $urlPath)');
    return url;
  }

  Future<Map<String, dynamic>> deleteonefile(String str) async {
    return await _sendCommand(4003, str: str);
  }

  Future<Map<String, dynamic>> deleteall() async {
    return await _sendCommand(4004);
  }
}
