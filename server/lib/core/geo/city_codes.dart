// lib/core/geo/city_codes.dart

/// County/city metadata: canonical (臺-spelled) display name, ISO 3166-2:TW
/// code, and the PascalCase English name TDX's `{City}` path parameter uses
/// (Phase 4 — kept here rather than duplicated because it's the same 22-row
/// table doing double duty).
///
/// Look up with [ShelterText.normalizeName]'s output (臺→台 folded) — [byCode]
/// keys are normalised the same way [TaiwanBounds.byCounty] uses.
class CityCode {
  const CityCode({
    required this.normalizedName,
    required this.displayName,
    required this.isoCode,
    required this.tdxName,
  });

  /// 臺→台 folded, matches `TaiwanBounds.byCounty` keys.
  final String normalizedName;

  /// Canonical 臺-spelled form, for display/output.
  final String displayName;

  /// ISO 3166-2:TW subdivision code.
  final String isoCode;

  /// PascalCase English name TDX expects in its `{City}` path parameter.
  /// 新竹市/新竹縣 and 嘉義市/嘉義縣 differ only by the `County` suffix — easy
  /// to swap by mistake, which silently returns the wrong city's stops.
  final String tdxName;
}

class CityCodes {
  const CityCodes._();

  static const List<CityCode> all = [
    CityCode(
      normalizedName: '台北市',
      displayName: '臺北市',
      isoCode: 'TPE',
      tdxName: 'Taipei',
    ),
    CityCode(
      normalizedName: '新北市',
      displayName: '新北市',
      isoCode: 'NWT',
      tdxName: 'NewTaipei',
    ),
    CityCode(
      normalizedName: '基隆市',
      displayName: '基隆市',
      isoCode: 'KEE',
      tdxName: 'Keelung',
    ),
    CityCode(
      normalizedName: '桃園市',
      displayName: '桃園市',
      isoCode: 'TAO',
      tdxName: 'Taoyuan',
    ),
    CityCode(
      normalizedName: '新竹市',
      displayName: '新竹市',
      isoCode: 'HSZ',
      tdxName: 'Hsinchu',
    ),
    CityCode(
      normalizedName: '新竹縣',
      displayName: '新竹縣',
      isoCode: 'HSQ',
      tdxName: 'HsinchuCounty',
    ),
    CityCode(
      normalizedName: '苗栗縣',
      displayName: '苗栗縣',
      isoCode: 'MIA',
      tdxName: 'Miaoli',
    ),
    CityCode(
      normalizedName: '台中市',
      displayName: '臺中市',
      isoCode: 'TXG',
      tdxName: 'Taichung',
    ),
    CityCode(
      normalizedName: '彰化縣',
      displayName: '彰化縣',
      isoCode: 'CHA',
      tdxName: 'Changhua',
    ),
    CityCode(
      normalizedName: '南投縣',
      displayName: '南投縣',
      isoCode: 'NAN',
      tdxName: 'Nantou',
    ),
    CityCode(
      normalizedName: '雲林縣',
      displayName: '雲林縣',
      isoCode: 'YUN',
      tdxName: 'Yunlin',
    ),
    CityCode(
      normalizedName: '嘉義市',
      displayName: '嘉義市',
      isoCode: 'CYI',
      tdxName: 'Chiayi',
    ),
    CityCode(
      normalizedName: '嘉義縣',
      displayName: '嘉義縣',
      isoCode: 'CYQ',
      tdxName: 'ChiayiCounty',
    ),
    CityCode(
      normalizedName: '台南市',
      displayName: '臺南市',
      isoCode: 'TNN',
      tdxName: 'Tainan',
    ),
    CityCode(
      normalizedName: '高雄市',
      displayName: '高雄市',
      isoCode: 'KHH',
      tdxName: 'Kaohsiung',
    ),
    CityCode(
      normalizedName: '屏東縣',
      displayName: '屏東縣',
      isoCode: 'PIF',
      tdxName: 'Pingtung',
    ),
    CityCode(
      normalizedName: '宜蘭縣',
      displayName: '宜蘭縣',
      isoCode: 'ILA',
      tdxName: 'Yilan',
    ),
    CityCode(
      normalizedName: '花蓮縣',
      displayName: '花蓮縣',
      isoCode: 'HUA',
      tdxName: 'Hualien',
    ),
    CityCode(
      normalizedName: '台東縣',
      displayName: '臺東縣',
      isoCode: 'TTT',
      tdxName: 'Taitung',
    ),
    CityCode(
      normalizedName: '澎湖縣',
      displayName: '澎湖縣',
      isoCode: 'PEN',
      tdxName: 'Penghu',
    ),
    CityCode(
      normalizedName: '金門縣',
      displayName: '金門縣',
      isoCode: 'KIN',
      tdxName: 'Kinmen',
    ),
    CityCode(
      normalizedName: '連江縣',
      displayName: '連江縣',
      isoCode: 'LIE',
      tdxName: 'Lienchiang',
    ),
  ];

  static final Map<String, CityCode> _byNormalizedName = {
    for (final c in all) c.normalizedName: c,
  };

  /// [normalizedName] must already be 臺→台 folded.
  static CityCode? byNormalizedName(String normalizedName) =>
      _byNormalizedName[normalizedName];
}
