class Pagination {
  final int page;
  final int? maxPage;
  final bool hasNextPage;
  final int? nextPage;
  final int? prevPage;

  Pagination({
    required this.page,
    this.maxPage,
    required this.hasNextPage,
    this.nextPage,
    this.prevPage,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    final page = (json['page'] as num?)?.toInt() ?? 1;
    final maxPage = (json['maxPage'] as num?)?.toInt();
    final nextPage = (json['nextPage'] as num?)?.toInt();
    final prevPage = (json['prevPage'] as num?)?.toInt();

    final bool hasNext = (json['hasNextPage'] as bool?) ??
        (nextPage != null && nextPage > 0) ||
        (maxPage != null ? page < maxPage : false);

    return Pagination(
      page: page,
      maxPage: maxPage,
      hasNextPage: hasNext,
      nextPage: nextPage,
      prevPage: prevPage,
    );
  }

  Map<String, dynamic> toJson() => {
    'page': page,
    'maxPage': maxPage,
    'hasNextPage': hasNextPage,
    'nextPage': nextPage,
    'prevPage': prevPage,
  };
}
