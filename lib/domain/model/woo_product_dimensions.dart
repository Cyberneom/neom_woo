class WooProductDimensions {
  final double length;
  final double width;
  final double height;

  WooProductDimensions({
    this.length = 0,
    this.width = 0,
    this.height = 0,
  });

  factory WooProductDimensions.fromJSON(Map<String, dynamic>? json) {
    if (json == null) return WooProductDimensions();
    return WooProductDimensions(
      length: double.tryParse(json['length']?.toString() ?? '') ?? 0.0,
      width: double.tryParse(json['width']?.toString() ?? '') ?? 0.0,
      height: double.tryParse(json['height']?.toString() ?? '') ?? 0.0,
    );
  }

  Map<String, dynamic> toJSON() {
    return {
      'length': length,
      'width': width,
      'height': height,
    };
  }
}
