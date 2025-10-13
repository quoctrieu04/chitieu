class Category {
  final int id;
  final String name;

  Category({required this.id, required this.name});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: (j['id'] ?? j['_id'] ?? 0) is int
            ? (j['id'] ?? j['_id']) as int
            : int.tryParse((j['id'] ?? j['_id'] ?? '0').toString()) ?? 0,

        // đọc được cả 'ten' (VN) lẫn 'name' (EN), fallback về chuỗi rỗng
        name: ((j['ten'] ?? j['name'] ?? '')).toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        // nếu backend dùng 'ten' thì đổi lại 'ten': name
        'name': name,
      };
}
