// 构建信息
// 此文件在构建时自动生成

class BuildInfo {
  static const String version = '1.0.0+1';
  static const String buildTime = 'BUILD_TIME_PLACEHOLDER';
  static const String buildDate = 'BUILD_DATE_PLACEHOLDER';
  
  static String get displayVersion => version;
  
  static String get displayBuildTime {
    if (buildTime == 'BUILD_TIME_PLACEHOLDER') {
      return '开发模式';
    }
    return buildTime;
  }
  
  static String get displayBuildDate {
    if (buildDate == 'BUILD_DATE_PLACEHOLDER') {
      return DateTime.now().toString().split(' ')[0];
    }
    return buildDate;
  }
}

