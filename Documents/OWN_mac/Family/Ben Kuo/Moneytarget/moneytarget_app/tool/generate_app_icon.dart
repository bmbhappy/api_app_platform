import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  const size = 512;
  final image = img.Image(width: size, height: size);

  const bgTop = _Color(0x0f, 0x76, 0x6e);
  const bgBottom = _Color(0x11, 0x5e, 0x59);

  // Background gradient.
  for (var y = 0; y < size; y++) {
    final t = y / (size - 1);
    final color = bgTop.lerp(bgBottom, t);
    for (var x = 0; x < size; x++) {
      image.setPixelRgba(x, y, color.r, color.g, color.b, 255);
    }
  }

  final centerX = size ~/ 2;
  final centerY = (size * 0.46).round();

  // Target rings.
  _drawRing(image, centerX, centerY, size * 0.50, size * 0.46,
      const _Color(15, 23, 42, 160));
  _drawRing(image, centerX, centerY, size * 0.39, size * 0.33,
      const _Color(165, 243, 252, 180));
  _drawRing(image, centerX, centerY, size * 0.28, size * 0.22,
      const _Color(254, 249, 195, 230));
  _drawDisk(
      image, centerX, centerY, size * 0.16, const _Color(15, 23, 42, 80));

  // Coin.
  final coinX = (size * 0.66).round();
  final coinY = (size * 0.66).round();
  _drawRadialGradientDisk(
    image,
    coinX,
    coinY,
    size * 0.30,
    const _Color(251, 191, 36),
    const _Color(245, 158, 11),
  );
  _drawRing(image, coinX, coinY, size * 0.27, size * 0.23,
      const _Color(253, 230, 138, 240));
  _drawRing(image, coinX, coinY, size * 0.20, size * 0.18,
      const _Color(253, 230, 138, 180));

  // Currency glyph approximation.
  _drawCurrencyMark(image, coinX, coinY, size * 0.18);

  // Arrow.
  _drawArrow(image,
      baseX: size * 0.36,
      baseY: size * 0.76,
      angleDegrees: -22,
      shaftWidth: size * 0.085,
      shaftLength: size * 0.38,
      headLength: size * 0.18,
      headHalfWidth: size * 0.22,
      shaftColor: const _Color(56, 189, 248, 220),
      headColor: const _Color(186, 230, 253, 230));

  final output = File('assets/app_icon.png');
  output.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('Generated ${output.path}');
}

void _drawDisk(
  img.Image image,
  int cx,
  int cy,
  double radius,
  _Color color,
) {
  final minX = max(0, (cx - radius).floor());
  final maxX = min(image.width - 1, (cx + radius).ceil());
  final minY = max(0, (cy - radius).floor());
  final maxY = min(image.height - 1, (cy + radius).ceil());

  final radiusSquared = radius * radius;
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final distSquared = dx * dx + dy * dy;
      if (distSquared <= radiusSquared) {
        color.writeTo(image, x, y);
      }
    }
  }
}

void _drawRing(
  img.Image image,
  int cx,
  int cy,
  double outerRadius,
  double innerRadius,
  _Color color,
) {
  final minX = max(0, (cx - outerRadius).floor());
  final maxX = min(image.width - 1, (cx + outerRadius).ceil());
  final minY = max(0, (cy - outerRadius).floor());
  final maxY = min(image.height - 1, (cy + outerRadius).ceil());

  final outerSquared = outerRadius * outerRadius;
  final innerSquared = innerRadius * innerRadius;
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final distSquared = dx * dx + dy * dy;
      if (distSquared <= outerSquared && distSquared >= innerSquared) {
        color.writeTo(image, x, y);
      }
    }
  }
}

void _drawRadialGradientDisk(
  img.Image image,
  int cx,
  int cy,
  double radius,
  _Color inner,
  _Color outer,
) {
  final minX = max(0, (cx - radius).floor());
  final maxX = min(image.width - 1, (cx + radius).ceil());
  final minY = max(0, (cy - radius).floor());
  final maxY = min(image.height - 1, (cy + radius).ceil());

  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final distSquared = dx * dx + dy * dy;
      if (distSquared <= radius * radius) {
        final dist = sqrt(distSquared) / radius;
        final color = inner.lerp(outer, dist);
        color.writeTo(image, x, y);
      }
    }
  }
}

void _drawCurrencyMark(img.Image image, int cx, int cy, double size) {
  final thickness = max(2, (size * 0.18).round());
  final halfWidth = (size * 0.30).round();
  final halfHeight = (size * 0.45).round();
  final barSpacing = (size * 0.22).round();

  final stroke = const _Color(30, 41, 59);

  // Vertical stem.
  for (var y = cy - halfHeight; y <= cy + halfHeight; y++) {
    for (var x = cx - thickness; x <= cx + thickness; x++) {
      stroke.writeTo(image, x, y);
    }
  }

  // Curved body approximation (two horizontal bars).
  for (var yOffset in [-barSpacing, barSpacing]) {
    for (var y = cy + yOffset - thickness; y <= cy + yOffset + thickness; y++) {
      for (var x = cx - halfWidth; x <= cx + halfWidth; x++) {
        stroke.writeTo(image, x, y);
      }
    }
  }
}

void _drawArrow(
  img.Image image, {
  required double baseX,
  required double baseY,
  required double angleDegrees,
  required double shaftWidth,
  required double shaftLength,
  required double headLength,
  required double headHalfWidth,
  required _Color shaftColor,
  required _Color headColor,
}) {
  final angle = angleDegrees * pi / 180.0;
  final cosA = cos(angle);
  final sinA = sin(angle);

  final totalLength = shaftLength + headLength;
  final bounds = totalLength + headHalfWidth;
  final minX = max(0, (baseX - bounds).floor());
  final maxX = min(image.width - 1, (baseX + bounds).ceil());
  final minY = max(0, (baseY - bounds).floor());
  final maxY = min(image.height - 1, (baseY + bounds).ceil());

  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x - baseX;
      final dy = y - baseY;

      final localX = dx * cosA + dy * sinA;
      final localY = -dx * sinA + dy * cosA;

      if (localY < 0 || localY > totalLength) continue;

      if (localY <= shaftLength) {
        if (localX.abs() <= shaftWidth / 2) {
          shaftColor.writeTo(image, x, y);
        }
        continue;
      }

      final headY = localY - shaftLength;
      final headWidthAtY =
          headHalfWidth * (1 - (headY / headLength).clamp(0.0, 1.0));

      if (headY >= 0 &&
          headY <= headLength &&
          localX.abs() <= headWidthAtY) {
        headColor.writeTo(image, x, y);
      }
    }
  }
}

class _Color {
  const _Color(this.r, this.g, this.b, [this.a = 255]);

  final int r;
  final int g;
  final int b;
  final int a;

  _Color lerp(_Color other, double t) {
    t = t.clamp(0.0, 1.0);
    return _Color(
      _lerpComponent(r, other.r, t),
      _lerpComponent(g, other.g, t),
      _lerpComponent(b, other.b, t),
      _lerpComponent(a, other.a, t),
    );
  }

  void writeTo(img.Image image, int x, int y) {
    if (x < 0 ||
        y < 0 ||
        x >= image.width ||
        y >= image.height ||
        a == 0) {
      return;
    }

    if (a == 255) {
      image.setPixelRgba(x, y, r, g, b, 255);
      return;
    }

    final current = image.getPixel(x, y);
    final cr = current.r;
    final cg = current.g;
    final cb = current.b;
    final ca = current.a;

    final alpha = a / 255.0;
    final outA = (alpha + ca / 255.0 * (1 - alpha)).clamp(0.0, 1.0);
    if (outA == 0) {
      image.setPixelRgba(x, y, 0, 0, 0, 0);
      return;
    }
    final outR = ((r * alpha + cr * (ca / 255.0) * (1 - alpha)) / outA)
        .clamp(0.0, 255.0)
        .round();
    final outG = ((g * alpha + cg * (ca / 255.0) * (1 - alpha)) / outA)
        .clamp(0.0, 255.0)
        .round();
    final outB = ((b * alpha + cb * (ca / 255.0) * (1 - alpha)) / outA)
        .clamp(0.0, 255.0)
        .round();
    image.setPixelRgba(x, y, outR, outG, outB, (outA * 255).round());
  }

  static int _lerpComponent(int a, int b, double t) =>
      (a + (b - a) * t).round().clamp(0, 255);
}

