class Item {
  final int id;
  final String title;
  final String description;
  final String createdAt;

  Item({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'created_at': createdAt,
    };
  }
}
