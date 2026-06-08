class Env {
  static const baseUrl = "https://data.taipei/api/v1/dataset";

  // 北市警政APP_防空避難設備位置 / 最新指定資料集
  static const shelterDatasetId = '4c92dbd4-d259-495a-8390-52628119a4dd';
  // 本地 geocoding sqlite 檔案路徑（用於補足座標）
  static const geocodingDbPath = 'lib/data/datasources/database/geoapify_results.db';
}
