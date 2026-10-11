class AiModel {
  const AiModel({required this.id, required this.name, required this.provider});

  final String id;
  final String name;
  final String provider;

  factory AiModel.fromJson(Map<String, dynamic> json) => AiModel(
    id: json['id'] as String,
    name: json['name'] as String,
    provider: json['provider'] as String,
  );
}
