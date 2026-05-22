class WooLineItem {

  String productId;
  int quantity;

  WooLineItem({
    required this.productId,
    required this.quantity,
  });

  // Convert a LineItem object to a JSON map
  Map<String, dynamic> toJSON() {
    return {
      'product_id': productId,
      'quantity': quantity,
    };
  }

  // Create a LineItem object from a JSON map.
  //
  // WooCommerce normally sends [quantity] as an int, but some plugin
  // integrations emit it as a numeric string. Parse defensively so a
  // malformed webhook does not crash the order pipeline.
  factory WooLineItem.fromJSON(Map<String, dynamic> json) {
    final rawQty = json['quantity'];
    final int qty = rawQty is int
        ? rawQty
        : rawQty is num
            ? rawQty.toInt()
            : rawQty is String
                ? int.tryParse(rawQty) ?? 0
                : 0;
    return WooLineItem(
      productId: (json['product_id'] ?? '').toString(),
      quantity: qty,
    );
  }
}
