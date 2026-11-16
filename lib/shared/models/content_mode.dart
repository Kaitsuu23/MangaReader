class ContentMode {
  final String id;
  final String name;
  final String description;
  final bool isDefault;
  final bool isDeletable;
  final List<String> enabledSources;
  final List<String> disabledSources;

  const ContentMode({
    required this.id,
    required this.name,
    this.description = '',
    this.isDefault = false,
    this.isDeletable = true,
    this.enabledSources = const [],
    this.disabledSources = const [],
  });

  factory ContentMode.fromJson(Map<String, dynamic> json) {
    return ContentMode(
      id: json['id'] as String? ?? 'normal',
      name: json['name'] as String? ?? 'Normal',
      description: json['description'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      isDeletable: json['isDeletable'] as bool? ?? true,
      enabledSources: List<String>.from(json['enabledSources'] as Iterable? ?? []),
      disabledSources: List<String>.from(json['disabledSources'] as Iterable? ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'isDefault': isDefault,
    'isDeletable': isDeletable,
    'enabledSources': enabledSources,
    'disabledSources': disabledSources,
  };

  ContentMode copyWith({
    String? id,
    String? name,
    String? description,
    bool? isDefault,
    bool? isDeletable,
    List<String>? enabledSources,
    List<String>? disabledSources,
  }) {
    return ContentMode(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isDefault: isDefault ?? this.isDefault,
      isDeletable: isDeletable ?? this.isDeletable,
      enabledSources: enabledSources ?? this.enabledSources,
      disabledSources: disabledSources ?? this.disabledSources,
    );
  }

  static const String defaultNormalId = 'normal';
  static const String defaultRestrictedId = 'restricted';

  static const ContentMode normal = ContentMode(
    id: defaultNormalId,
    name: 'Normal',
    description: 'Mode katalog utama',
    isDefault: true,
    isDeletable: false,
    enabledSources: [],
    disabledSources: [],
  );

  static const ContentMode restricted = ContentMode(
    id: defaultRestrictedId,
    name: 'Restricted',
    description: 'Mode terpisah',
    isDefault: false,
    isDeletable: true,
    enabledSources: [],
    disabledSources: [],
  );

  static List<ContentMode> defaultModes() => [
    normal,
    restricted,
  ];
}
