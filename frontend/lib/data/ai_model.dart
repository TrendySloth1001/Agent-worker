class AiModel {
  const AiModel({
    required this.id,
    required this.name,
    required this.provider,
    this.maker,
    this.about,
    this.contextTokens,
    this.speed,
  });

  final String id;
  final String name;
  final String provider;

  /// Who made the model, a friendly line on what it is good at, its context
  /// window in tokens and a rough speed feel (fast, balanced, deep). All
  /// come from the server and may be missing.
  final String? maker;
  final String? about;
  final int? contextTokens;
  final String? speed;

  factory AiModel.fromJson(Map<String, dynamic> json) => AiModel(
    id: json['id'] as String,
    name: json['name'] as String,
    provider: json['provider'] as String,
    maker: json['maker'] as String?,
    about: json['about'] as String?,
    contextTokens: (json['contextTokens'] as num?)?.toInt(),
    speed: json['speed'] as String?,
  );
}
