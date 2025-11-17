#!/bin/bash

# 恢复构建信息占位符脚本
# 构建完成后恢复占位符，避免提交构建时间到版本控制

BUILD_INFO_FILE="lib/build_info.dart"

# 恢复占位符
sed -i '' "s/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}/BUILD_TIME_PLACEHOLDER/g" "$BUILD_INFO_FILE"
sed -i '' "s/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/BUILD_DATE_PLACEHOLDER/g" "$BUILD_INFO_FILE"

echo "Build info placeholders restored"


