class ApiResponse<T> {
  final bool success;
  final T data;

  ApiResponse({required this.success, required this.data});

  /// 泛型 fromJson，需要傳入一個函式來解析 T
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic json) fromJsonT,
  ) {
    return ApiResponse(success: json['success'], data: fromJsonT(json['data']));
  }
}
