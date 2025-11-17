#!/bin/bash

# 构建前脚本 - 在构建时生成构建信息

echo "Generating build info..."

# 使用 Dart 脚本生成构建信息
dart build_runner.dart

echo "Build info generated successfully!"


