import '../../domain/entities/shelter.dart';

Map<String, dynamic> shelterToJson(Shelter e) {
  return {
    'id': e.id,
    'importDate': e.importDate?.toIso8601String(),
    '收容所編號': e.shelterCode,
    '名稱': e.name,
    '縣市': e.city,
    '郵遞區號': e.zipcode,
    '鄉鎮': e.township,
    '村里': e.village,
    '門牌地址': e.address,
    '類型': e.type,
    '水災': e.flood,
    '震災': (e.quake == '備用') ? 'Y' : e.quake,
    '土石流': (e.landslide == '老舊聚落') ? 'Y' : e.landslide,
    '海嘯': (e.tsunami == '備用') ? 'Y' : e.tsunami,
    '救濟支站': e.relief,
    '無障礙設施': e.accessible,
    '室內': e.indoor,
    '室外': e.outdoor,
    '服務里別': (e.serviceVillages ?? '')
        .split(RegExp(r'[、，,]'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList(),
    '容納人數': e.capacity,
    '收容所面積(平方公尺)': e.area,
    '聯絡人姓名': e.contactName,
    '聯絡人連絡電話': e.contactPhone,
    '管理人姓名': e.managerName,
    '管理人連絡電話': e.managerPhone,
    '備考': e.notes,
    '座標x': e.x,
    '座標y': e.y,
  };
}
