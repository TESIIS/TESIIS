// lib/domain/entities/shelter.dart

class Shelter {
  final int id; // _id
  final DateTime? importDate; // _importdate.date
  final String shelterCode; // 收容所編號
  final String name; // 名稱
  final String city; // 縣市
  final String zipcode; // 郵遞區號
  final String township; // 鄉鎮
  final String village; // 村里
  final String address; // 門牌地址
  final String type; // 類型
  final String? flood; // 水災
  final String? quake; // 震災
  final String? landslide; // 土石流
  final String? tsunami; // 海嘯
  final String? relief; // 救濟支站
  final String? accessible; // 無障礙設施
  final String? indoor; // 室內
  final String? outdoor; // 室外
  final String? serviceVillages; // 服務里別
  final int capacity; // 容納人數
  final double? area; // 收容所面積（平方公尺）
  final String? contactName; // 聯絡人姓名
  final String? contactPhone; // 聯絡人連絡電話
  final String? managerName; // 管理人姓名
  final String? managerPhone; // 管理人連絡電話
  final String? notes; // 備考
  // Coordinates never come from the OpenData dataset — it has no such columns.
  // They are joined in from the committed coordinate table; see
  // data/shelter_coordinates.csv and CoordinateSource.
  final double? x; // 座標x = longitude
  final double? y; // 座標y = latitude

  /// Which dataset the coordinate came from, or null when there is none.
  /// Exposed so clients can distinguish a surveyed government point from a
  /// best-effort name match.
  final String? coordinateSource;

  /// How much to trust the coordinate: exact / name_match / approx.
  final String? coordinateConfidence;

  Shelter({
    required this.id,
    required this.importDate,
    required this.shelterCode,
    required this.name,
    required this.city,
    required this.zipcode,
    required this.township,
    required this.village,
    required this.address,
    required this.type,
    this.flood,
    this.quake,
    this.landslide,
    this.tsunami,
    this.relief,
    this.accessible,
    this.indoor,
    this.outdoor,
    this.serviceVillages,
    required this.capacity,
    this.area,
    this.contactName,
    this.contactPhone,
    this.managerName,
    this.managerPhone,
    this.notes,
    this.x,
    this.y,
    this.coordinateSource,
    this.coordinateConfidence,
  });

  bool get hasCoordinate => x != null && y != null;
}
