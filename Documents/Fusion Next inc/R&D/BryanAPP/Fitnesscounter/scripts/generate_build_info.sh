#!/bin/bash

# 生成构建信息脚本
# 在构建时自动生成构建时间和日期

BUILD_TIME=$(date +"%Y-%m-%d %H:%M:%S")
BUILD_DATE=$(date +"%Y-%m-%d")

# 读取 lib/build_info.dart 文件
BUILD_INFO_FILE="lib/build_info.dart"

# 替换占位符
sed -i '' "s/BUILD_TIME_PLACEHOLDER/$BUILD_TIME/g" "$BUILD_INFO_FILE"
sed -i '' "s/BUILD_DATE_PLACEHOLDER/$BUILD_DATE/g" "$BUILD_INFO_FILE"

echo "Build info generated:"
echo "  Build Time: $BUILD_TIME"
echo "  Build Date: $BUILD_DATE"


