class Detection {
  final String label;
  final double confidence;
  final double x;      // 중심 x 좌표
  final double y;      // 중심 y 좌표
  final double w;      // 너비
  final double h;      // 높이

  Detection({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}