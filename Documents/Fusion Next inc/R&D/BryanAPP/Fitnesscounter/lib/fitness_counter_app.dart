import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'build_info.dart';
import 'record_model.dart';
import 'record_database.dart';
import 'record_calendar_view.dart';

class FitnessCounterApp extends StatefulWidget {
  const FitnessCounterApp({super.key});

  @override
  State<FitnessCounterApp> createState() => _FitnessCounterAppState();
}

class _FitnessCounterAppState extends State<FitnessCounterApp> with WidgetsBindingObserver {
  final stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts? _tts; // 改为可选类型，延迟初始化
  
  bool _isListening = false;
  bool _isCountingDown = false;
  bool _isCounting = false;
  bool _speechInitialized = false; // 语音识别是否已初始化
  bool _isRestartingListening = false; // 是否正在重新启动监听（防止并发）
  int _countdownSeconds = 0;
  int _currentSecond = 0;
  int _totalSeconds = 0;
  int _announceInterval = 1; // 播报间隔（秒），默认每1秒
  int _nextAnnounceSecond = 0; // 下次播报的秒数
  int _startListeningFromMinute = 0; // 从第几分钟开始监听（0表示立即开始）
  bool _isTtsSpeaking = false; // TTS是否正在播报
  String? _pendingAnnouncement; // 待播报的内容
  Timer? _ttsTimeoutTimer; // TTS超时定时器
  
  Timer? _countdownTimer;
  Timer? _countTimer;
  Timer? _listeningTimer;
  String _statusText = '请说"倒數10秒"开始';
  String _commandText = '';
  bool _hasUnsavedRecord = false; // 是否有未保存的记录
  int _unsavedTotalSeconds = 0; // 未保存的总秒数

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 延迟初始化，确保应用完全启动和权限请求完成
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _initializeSpeech().catchError((error) {
          // 初始化失败，不抛出异常
          if (mounted) {
            try {
              setState(() {
                _statusText = '语音识别初始化失败，请检查权限设置';
              });
            } catch (e) {
              // 忽略setState错误
            }
          }
        });
      }
    });
    
    // 延迟初始化TTS，确保插件完全注册后再初始化
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _initializeTts().catchError((error) {
          // TTS初始化失败，不抛出异常
          if (mounted) {
            try {
              setState(() {
                _statusText = '语音播报初始化失败';
              });
            } catch (e) {
              // 忽略setState错误
            }
          }
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused) {
      // 应用进入后台，暂停所有活动
      _pauseAllActivities();
    } else if (state == AppLifecycleState.resumed) {
      // 应用恢复前台，重新初始化
      if (mounted) {
        _resumeActivities();
      }
    } else if (state == AppLifecycleState.detached) {
      // 应用被终止，清理资源
      _cleanup();
    }
  }

  void _pauseAllActivities() {
    // 停止所有定时器
    _countdownTimer?.cancel();
    _countTimer?.cancel();
    _listeningTimer?.cancel();
    _ttsTimeoutTimer?.cancel();
    
    // 停止语音识别
    try {
      _speech.stop();
    } catch (e) {
      // 忽略错误
    }
    
    // 停止TTS
    try {
      _tts?.stop();
    } catch (e) {
      // 忽略错误
    }
    
    // 重置状态
    if (mounted) {
      setState(() {
        _isListening = false;
        _isTtsSpeaking = false;
        _pendingAnnouncement = null;
      });
    }
  }

  Future<void> _resumeActivities() async {
    // 等待一下确保应用完全恢复
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    // 重新初始化服务
    try {
      await _initializeSpeech();
    } catch (e) {
      // 忽略初始化错误，稍后重试
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _initializeSpeech();
        }
      });
    }
    
    try {
      await _initializeTts();
    } catch (e) {
      // 忽略初始化错误，稍后重试
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _initializeTts();
        }
      });
    }
    
    // 如果之前在计数，重置状态
    if (mounted) {
      setState(() {
        _isCountingDown = false;
        _isCounting = false;
        _currentSecond = 0;
        _statusText = '请说"倒數10秒"开始';
      });
    }
  }

  void _cleanup() {
    // 完全清理所有资源
    _pauseAllActivities();
  }

  Future<void> _initializeSpeech() async {
    if (!mounted) return;
    
    try {
      // 先停止之前的监听
      try {
        await _speech.stop();
      } catch (e) {
        // 忽略停止错误
      }
      
      // 等待一下确保完全停止
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          
          try {
            setState(() {
              _isListening = status == 'listening';
            });
            
            // 在计数模式下，如果监听结束（done），安排重新启动
            if ((status == 'done' || status == 'notListening') && _isCounting && !_isRestartingListening) {
              _scheduleRestartListening();
            }
          } catch (e) {
            // 忽略setState错误
          }
        },
        onError: (error) {
          if (!mounted) return;
          
          try {
            // 过滤可忽略的错误
            String errorMsg = error.errorMsg.toLowerCase();
            bool isIgnorableError = 
                errorMsg.contains('no speech detected') ||
                errorMsg.contains('1101') ||
                errorMsg.contains('1110') ||
                errorMsg.contains('session deactivation') ||
                errorMsg.contains('not authorized') ||
                errorMsg.contains('restricted') ||
                (errorMsg.contains('speech recognition') && errorMsg.contains('not available')) ||
                errorMsg.contains('authorization denied') ||
                errorMsg.contains('service unavailable') ||
                errorMsg.contains('error 1101') ||
                errorMsg.contains('error 1110') ||
                errorMsg.contains('error_no_match') ||
                errorMsg.contains('no match');
            
            // 如果是可忽略的错误，在非计数模式下也静默处理（不显示错误）
            // 只在持续监听模式下遇到可忽略错误时，重新开始监听
            if (_isCounting && isIgnorableError) {
              // 使用辅助方法，避免并发问题
              _scheduleRestartListening();
              return; // 不显示错误信息
            }
            
            // 只在重要错误或初始化失败时才显示错误
            if (!isIgnorableError) {
              if (mounted) {
                try {
                  setState(() {
                    _statusText = '语音识别错误: ${error.errorMsg}';
                  });
                } catch (e) {
                  // 忽略setState错误
                }
              }
            }
          } catch (e) {
            // 忽略错误处理中的错误
          }
        },
      );

      if (!available && mounted) {
        try {
          setState(() {
            _statusText = '语音识别不可用，请检查权限设置';
            _speechInitialized = false;
          });
        } catch (e) {
          // 忽略setState错误
        }
      } else if (available && mounted) {
        setState(() {
          _speechInitialized = true;
        });
      }
    } catch (e) {
      // 初始化失败，不抛出异常
      if (mounted) {
        try {
          setState(() {
            _statusText = '语音识别初始化失败';
          });
        } catch (_) {
          // 忽略setState错误
        }
      }
    }
  }

  Future<void> _initializeTts() async {
    if (!mounted) return;
    
    // 延迟创建TTS实例，避免在插件未完全注册时初始化
    if (_tts == null) {
      try {
        _tts = FlutterTts();
        // 等待一下确保插件完全加载
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // 如果创建失败，稍后重试
        if (mounted) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _initializeTts();
            }
          });
        }
        return;
      }
    }
    
    if (_tts == null || !mounted) return;
    
    try {
      // 先停止之前的播报
      await _tts!.stop();
    } catch (e) {
      // 忽略停止错误
    }
    
    // 等待一下确保完全停止
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted || _tts == null) return;
    
    try {
      await _tts!.setLanguage('zh-TW');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
      
      // 设置完成回调
      _tts!.setCompletionHandler(() {
        _ttsTimeoutTimer?.cancel();
        if (mounted) {
          setState(() {
            _isTtsSpeaking = false;
          });
          
          // 如果有待播报的内容，继续播报
          if (_pendingAnnouncement != null) {
            String? text = _pendingAnnouncement;
            _pendingAnnouncement = null;
            // 延迟一点再播报，确保状态正确
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                _safeSpeak(text!);
              }
            });
          }
        }
      });
      
      // 设置错误回调
      _tts!.setErrorHandler((msg) {
        _ttsTimeoutTimer?.cancel();
        if (mounted) {
          setState(() {
            _isTtsSpeaking = false;
            _pendingAnnouncement = null;
          });
          // 等待后重新初始化TTS
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _tts?.stop().then((_) {
                _initializeTts();
              }).catchError((_) {
                // 忽略错误
              });
            }
          });
        }
      });
    } catch (e) {
      // 初始化失败，稍后重试
      if (mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _initializeTts();
          }
        });
      }
    }
  }
  
  Future<void> _safeSpeak(String text) async {
    if (!mounted || text.isEmpty) return;
    
    // 如果正在播报，将内容加入队列
    if (_isTtsSpeaking) {
      _pendingAnnouncement = text;
      return;
    }
    
    try {
      // 取消之前的超时定时器
      _ttsTimeoutTimer?.cancel();
      
      setState(() {
        _isTtsSpeaking = true;
        _pendingAnnouncement = null;
      });
      
      // 确保TTS已初始化
      if (_tts == null) {
        await _initializeTts();
        if (_tts == null) return;
      }
      
      // 停止之前的播报（如果有）
      await _tts!.stop();
      await Future.delayed(const Duration(milliseconds: 50));
      
      // 开始播报（不等待完成）
      final result = await _tts!.speak(text);
      
      if (result == 1) {
        // 播报成功，设置超时保护（3秒后自动重置，防止完成回调没有触发）
        _ttsTimeoutTimer = Timer(const Duration(seconds: 3), () {
          if (_isTtsSpeaking && mounted) {
            setState(() {
              _isTtsSpeaking = false;
            });
            // 如果有待播报的内容，继续播报
            if (_pendingAnnouncement != null) {
              String? nextText = _pendingAnnouncement;
              _pendingAnnouncement = null;
              _safeSpeak(nextText!);
            }
          }
        });
      } else {
        // 播报失败，立即重置状态
        _ttsTimeoutTimer?.cancel();
        setState(() {
          _isTtsSpeaking = false;
        });
        // 如果有待播报的内容，继续播报
        if (_pendingAnnouncement != null) {
          String? nextText = _pendingAnnouncement;
          _pendingAnnouncement = null;
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              _safeSpeak(nextText!);
            }
          });
        }
      }
    } catch (e) {
      // 捕获异常，重置状态
      _ttsTimeoutTimer?.cancel();
      setState(() {
        _isTtsSpeaking = false;
      });
      
      // 尝试恢复
      try {
        await _tts?.stop();
      } catch (_) {}
      
      // 如果有待播报的内容，等待后继续播报
      if (_pendingAnnouncement != null) {
        String? nextText = _pendingAnnouncement;
        _pendingAnnouncement = null;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _safeSpeak(nextText!);
          }
        });
      } else {
        // 没有待播报内容，尝试重新初始化
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _initializeTts();
          }
        });
      }
    }
  }

  Future<void> _startListening({bool continuous = false}) async {
    if (_isListening && !continuous) return;

    // 检查语音识别是否已初始化
    if (!_speechInitialized) {
      // 尝试重新初始化
      await _initializeSpeech();
      
      // 如果还是没初始化成功，等待一下再试
      if (!_speechInitialized) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _initializeSpeech();
      }
      
      // 如果仍然失败，显示提示
      if (!_speechInitialized && mounted) {
        setState(() {
          _statusText = '语音识别未就绪，请稍后再试';
        });
        return;
      }
    }

    // 停止之前的监听
    if (_isListening) {
      try {
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        // 忽略停止错误
      }
    }

    // 持续监听模式（用于计数过程中）
    if (continuous) {
      _keepListening();
    } else {
      // 普通监听模式
      try {
        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _commandText = result.recognizedWords;
            });
            
            if (result.finalResult) {
              _processCommand(result.recognizedWords);
            }
          },
          listenFor: const Duration(seconds: 5),
          pauseFor: const Duration(seconds: 3),
          localeId: 'zh_TW',
          listenOptions: stt.SpeechListenOptions(
            cancelOnError: false, // 改为false，避免自动取消
            partialResults: true,
            listenMode: stt.ListenMode.confirmation,
          ),
        );
        
        // 监听成功开始
        if (mounted) {
          setState(() {
            _isListening = true;
            _statusText = '正在监听，请说"倒數X秒"';
          });
        }
      } catch (e) {
        // 监听启动失败
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusText = '监听启动失败，请重试';
          });
          
          // 尝试重新初始化
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _initializeSpeech();
            }
          });
        }
      }
    }
  }

  void _keepListening() async {
    // 防止并发调用
    if (!_isCounting || !mounted || _isRestartingListening || _isListening) return;
    
    // 设置标志，防止并发
    _isRestartingListening = true;

    try {
      // 确保之前的监听已完全停止
      try {
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 300)); // 等待完全停止
      } catch (e) {
        // 忽略停止错误
      }

      if (!_isCounting || !mounted) {
        _isRestartingListening = false;
        return;
      }

      // 重置监听状态
      setState(() {
        _isListening = false;
      });

      // 再等待一下，确保系统完全清理
      await Future.delayed(const Duration(milliseconds: 200));

      if (!_isCounting || !mounted) {
        _isRestartingListening = false;
        return;
      }

      // 开始新的监听
      await _speech.listen(
        onResult: (result) {
          if (!mounted || !_isCounting) return;
          
          // 在计数过程中，只显示"停/停止"命令，其他命令静默处理
          if (_isCounting || _isCountingDown) {
            String lowerWords = result.recognizedWords.toLowerCase().trim();
            if (lowerWords.contains('停') || lowerWords.contains('停止') || 
                lowerWords == 'stop' || lowerWords.contains('结束')) {
              setState(() {
                _commandText = result.recognizedWords;
              });
            } else {
              // 非停止命令，不更新 _commandText，避免显示错误信息
              setState(() {
                _commandText = ''; // 清空显示
              });
            }
          } else {
            // 非计数模式，正常显示识别结果
            setState(() {
              _commandText = result.recognizedWords;
            });
          }
          
          if (result.finalResult) {
            _processCommand(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 2),
        localeId: 'zh_TW',
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false, // 不自动取消，避免频繁重启
          partialResults: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );

      // 监听成功启动
      if (mounted && _isCounting) {
        setState(() {
          _isListening = true;
          _isRestartingListening = false;
        });
      } else {
        _isRestartingListening = false;
      }
    } catch (e) {
      // 捕获异常，重置状态
      _isRestartingListening = false;
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }

      // 如果还在计数中，等待较长时间后重试
      if (_isCounting && mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (_isCounting && mounted && !_isRestartingListening) {
            _keepListening();
          }
        });
      }
    }

    // 监听结束后的处理（通过 onResult 或其他回调）
    // 注意：这里不再使用 .then()，因为可能会导致并发问题
    // 改为在错误处理中统一处理重试逻辑
  }

  // 辅助方法：在监听结束时重新启动
  void _scheduleRestartListening() {
    // 防止频繁重启
    if (_isRestartingListening || !_isCounting || !mounted || _isListening) return;

    // 延迟较长时间，确保完全清理和避免递归锁问题
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (_isCounting && mounted && !_isRestartingListening && !_isListening) {
        _keepListening();
      }
    });
  }

  Future<void> _stopListening() async {
    // 重置重启标志
    _isRestartingListening = false;
    
    try {
      await _speech.stop();
      // 等待停止完成，给系统更多时间清理
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    } catch (e) {
      // 忽略停止时的错误
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  void _processCommand(String command) {
    // 如果正在倒數或计数中，只处理停止命令
    if (_isCountingDown || _isCounting) {
      // 检查是否是停止命令
      String lowerCommand = command.toLowerCase().trim();
      if (lowerCommand.contains('停') || lowerCommand.contains('停止') || 
          lowerCommand == 'stop' || lowerCommand.contains('结束')) {
        _stopCounting();
      }
      // 其他命令在计数过程中静默忽略，不显示错误
      return;
    }
    
    // 解析命令，例如："倒數10秒" -> 10
    final RegExp regex = RegExp(r'倒數(\d+)秒');
    final match = regex.firstMatch(command);
    
    if (match != null) {
      int seconds = int.tryParse(match.group(1) ?? '') ?? 0;
      if (seconds > 0 && seconds <= 60) {
        _startCountdown(seconds);
      } else {
        setState(() {
          _statusText = '请说倒數1-60秒';
        });
        _safeSpeak('请说倒數1到60秒');
      }
    } else {
      // 只有在非计数模式下才显示未识别命令的错误
      if (!_isCountingDown && !_isCounting) {
        setState(() {
          _statusText = '未识别命令，请说"倒數X秒"';
        });
      }
      // 计数模式下静默忽略
    }
  }

  Future<void> _startCountdown(int seconds) async {
    if (_isCountingDown || _isCounting) return;

    setState(() {
      _isCountingDown = true;
      _countdownSeconds = seconds;
      _statusText = '开始倒數 $_countdownSeconds 秒';
      // 开始新的倒计时时，如果之前有未保存的记录，清除它
      if (_hasUnsavedRecord) {
        _hasUnsavedRecord = false;
        _unsavedTotalSeconds = 0;
      }
      _totalSeconds = 0; // 重置总时间
    });

    // 播放"好的，开始倒數"并等待完成
    await _safeSpeak('好的，开始倒數');
    await Future.delayed(const Duration(milliseconds: 800));

    // 倒计时 - 先播报初始数字
    if (_countdownSeconds > 0) {
      await _safeSpeak('$_countdownSeconds');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 倒计时循环
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() {
          _countdownSeconds--;
          _statusText = '倒數 $_countdownSeconds 秒';
        });
        
        // 安全播报数字
        _safeSpeak('$_countdownSeconds');
      } else {
        timer.cancel();
        setState(() {
          _countdownSeconds = 0;
          _statusText = '倒數完成';
        });
        
        // 播报"开始"然后开始计数
        _safeSpeak('开始').then((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isCountingDown = false;
              });
              _startCounting();
            }
          });
        });
      }
    });
  }

  void _startCounting() {
    setState(() {
      _isCounting = true;
      _currentSecond = 0;
      _totalSeconds = 0; // 重置总时间
      _nextAnnounceSecond = _announceInterval; // 设置首次播报时间
      _statusText = '计数中... 说"停"来停止';
    });

    // 根据设置决定是否立即开始监听
    int startListeningFromSeconds = _startListeningFromMinute * 60;
    if (startListeningFromSeconds == 0) {
      // 立即开始监听
      _startListening(continuous: true);
    } else {
      // 延迟到指定时间才开始监听
      Future.delayed(Duration(seconds: startListeningFromSeconds), () {
        if (_isCounting && mounted) {
          _startListening(continuous: true);
        }
      });
    }

    // 延迟1秒后开始计数（让"开始"语音完成）
    Future.delayed(const Duration(seconds: 1), () {
      if (!_isCounting) return;
      
      _countTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_isCounting) {
          timer.cancel();
          return;
        }
        
        setState(() {
          _currentSecond++;
          _totalSeconds++;
          // 更新状态文本
          if (_currentSecond >= 60) {
            int minutes = _currentSecond ~/ 60;
            int remainingSeconds = _currentSecond % 60;
            if (remainingSeconds == 0) {
              _statusText = '$minutes 分';
            } else {
              _statusText = '$minutes 分 $remainingSeconds 秒';
            }
          } else {
            _statusText = '$_currentSecond 秒鐘';
          }
        });
        
        // 根据设置的间隔播报
        bool shouldAnnounce = false;
        if (_announceInterval == 1) {
          // 每秒播报
          shouldAnnounce = true;
          _nextAnnounceSecond = _currentSecond + 1;
        } else if (_currentSecond == _nextAnnounceSecond) {
          // 达到播报时间
          shouldAnnounce = true;
          _nextAnnounceSecond += _announceInterval;
        } else if (_currentSecond == 1 && _announceInterval > 1) {
          // 首次播报（1秒时）
          shouldAnnounce = true;
          _nextAnnounceSecond = _announceInterval + 1;
        }
        
        if (shouldAnnounce) {
          String text = _formatAnnouncement(_currentSecond);
          // 直接调用，内部会处理队列
          _safeSpeak(text);
        }
      });
    });
  }

  String _formatAnnouncement(int seconds) {
    // 如果间隔为1秒，只播报数字
    if (_announceInterval == 1) {
      if (seconds >= 60) {
        // 超过60秒，转换为分钟秒格式
        int minutes = seconds ~/ 60;
        int remainingSeconds = seconds % 60;
        if (remainingSeconds == 0) {
          return '$minutes 分';
        } else {
          return '$minutes 分 $remainingSeconds 秒';
        }
      } else {
        // 60秒以内，只播报数字
        return '$seconds';
      }
    } else {
      // 间隔大于1秒，使用完整的格式
      if (seconds >= 60) {
        // 超过60秒，转换为分钟秒格式
        int minutes = seconds ~/ 60;
        int remainingSeconds = seconds % 60;
        if (remainingSeconds == 0) {
          return '$minutes 分';
        } else {
          return '$minutes 分 $remainingSeconds 秒';
        }
      } else {
        // 60秒以内，播报秒数
        return '$seconds 秒鐘';
      }
    }
  }

  void _stopCounting() {
    _countdownTimer?.cancel();
    _countTimer?.cancel();
    _listeningTimer?.cancel();
    
    // 重置重启标志，确保停止监听
    _isRestartingListening = false;
    _stopListening();
    
      // 停止TTS播报并清空队列
    _ttsTimeoutTimer?.cancel();
    _tts?.stop();
    setState(() {
      _isTtsSpeaking = false;
      _pendingAnnouncement = null;
    });

    int minutes = _totalSeconds ~/ 60;
    int seconds = _totalSeconds % 60;
    
    setState(() {
      _isCountingDown = false;
      _isCounting = false;
      _currentSecond = 0;
      _nextAnnounceSecond = 0;
    });

    // 只有在有计数时间时才播报
    if (_totalSeconds > 0) {
      setState(() {
        _statusText = '总共用了 $minutes 分 $seconds 秒';
        _hasUnsavedRecord = true;
        _unsavedTotalSeconds = _totalSeconds;
      });
      _safeSpeak('总共用了 $minutes 分 $seconds 秒');
      
      // 延迟后重置（但保留未保存记录状态）
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_hasUnsavedRecord) {
          setState(() {
            _totalSeconds = 0;
            _statusText = '请说"倒數10秒"开始';
          });
        }
      });
    } else {
      setState(() {
        _totalSeconds = 0;
        _statusText = '请说"倒數10秒"开始';
        _hasUnsavedRecord = false;
      });
    }
  }

  Future<void> _saveRecord() async {
    if (!_hasUnsavedRecord || _unsavedTotalSeconds == 0) return;

    try {
      final record = Record(
        dateTime: DateTime.now(),
        totalSeconds: _unsavedTotalSeconds,
      );

      await RecordDatabase.instance.createRecord(record);

      if (mounted) {
        setState(() {
          _hasUnsavedRecord = false;
          _unsavedTotalSeconds = 0;
          _totalSeconds = 0;
          _statusText = '记录已保存';
        });

        _safeSpeak('记录已保存');

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _statusText = '请说"倒數10秒"开始';
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = '保存失败，请重试';
        });
        _safeSpeak('保存失败');
      }
    }
  }

  void _showRecords() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RecordCalendarView(),
      ),
    );
  }

  void _showIntervalSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int selectedInterval = _announceInterval;
        int selectedStartMinute = _startListeningFromMinute;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('设置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '播报间隔：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ...([1, 5, 10, 15, 30].map((interval) => RadioListTile<int>(
                      title: Text(interval == 1 ? '每秒播报' : '每$interval秒播报'),
                      value: interval,
                      groupValue: selectedInterval,
                      onChanged: _isCounting || _isCountingDown
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  selectedInterval = value;
                                });
                                this.setState(() {
                                  _announceInterval = value;
                                });
                              }
                            },
                    ))),
                    const SizedBox(height: 20),
                    const Text(
                      '从第几分钟开始监听：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    // 显示当前选择的分钟数
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            selectedStartMinute == 0
                                ? '立即开始'
                                : '第 $selectedStartMinute 分钟',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    // 滑动选择器
                    Slider(
                      value: selectedStartMinute.toDouble(),
                      min: 0,
                      max: 60,
                      divisions: 60, // 可以精确选择0-60的任意整数
                      label: selectedStartMinute == 0
                          ? '立即开始'
                          : '第 $selectedStartMinute 分钟',
                      onChanged: _isCounting || _isCountingDown
                          ? null
                          : (value) {
                              final newValue = value.round();
                              setState(() {
                                selectedStartMinute = newValue;
                              });
                              this.setState(() {
                                _startListeningFromMinute = newValue;
                              });
                            },
                    ),
                    // 显示最小值、最大值标签
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '立即开始',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '60分钟',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    // 版本信息
                    const Text(
                      '版本信息',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    _buildInfoRow('版本号', BuildInfo.displayVersion),
                    const SizedBox(height: 5),
                    _buildInfoRow('构建时间', BuildInfo.displayBuildTime),
                    const SizedBox(height: 5),
                    _buildInfoRow('构建日期', BuildInfo.displayBuildDate),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('健身语音计数器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _isCounting || _isCountingDown
                ? null
                : _showRecords,
            tooltip: '查看记录',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _isCounting || _isCountingDown
                ? null
                : _showIntervalSettings,
            tooltip: '设置播报间隔',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 状态显示
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    _isListening
                        ? Icons.mic
                        : _isCountingDown || _isCounting
                            ? Icons.timer
                            : Icons.mic_none,
                    size: 60,
                    color: _isListening
                        ? Colors.red
                        : _isCountingDown || _isCounting
                            ? Colors.blue
                            : Colors.grey,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _statusText,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_commandText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '识别: $_commandText',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            // 倒计时显示
            if (_isCountingDown)
              Container(
                padding: const EdgeInsets.all(30),
                child: Text(
                  '$_countdownSeconds',
                  style: const TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),

              // 当前秒数显示
            if (_isCounting)
              Container(
                padding: const EdgeInsets.all(30),
                child: Text(
                  _currentSecond >= 60
                      ? '${_currentSecond ~/ 60} 分 ${_currentSecond % 60} 秒'
                      : '$_currentSecond 秒',
                  style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // 设置信息显示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    '播报间隔: ${_announceInterval == 1 ? "每秒" : "每$_announceInterval秒"}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '监听开始: ${_startListeningFromMinute == 0 ? "立即开始" : "第$_startListeningFromMinute分钟"}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isCounting || _isCountingDown
                      ? null
                      : (_isListening ? _stopListening : _startListening),
                  icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                  label: Text(_isListening ? '停止监听' : '开始语音'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                if (_isCounting || _isCountingDown)
                  ElevatedButton.icon(
                    onPressed: _stopCounting,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 40),

            // 总时间显示和保存按钮
            if (_hasUnsavedRecord || _totalSeconds > 0)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '总计: ${(_hasUnsavedRecord ? _unsavedTotalSeconds : _totalSeconds) ~/ 60} 分 ${(_hasUnsavedRecord ? _unsavedTotalSeconds : _totalSeconds) % 60} 秒',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_hasUnsavedRecord) ...[
                      const SizedBox(height: 15),
                      ElevatedButton.icon(
                        onPressed: _saveRecord,
                        icon: const Icon(Icons.save),
                        label: const Text('保存记录'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 15,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

