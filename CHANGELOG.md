# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)。

## [Unreleased]

讓專案真正可用並完成開源化。這一輪修掉的是「clone 下來跑不動」的三個獨立原因。

### Added

- **座標資料管線。** 新增 `server/tool/build_coordinates.dart`，離線 join 三個政府開放資料集產生 `server/data/shelter_coordinates.csv` 並進版控。401 筆避難所中 380 筆（94.8%）取得座標，先前是 0 筆。
- `GET /api/shelters/nearby?lat=&lng=&radius=&limit=` — 距離計算移到 server 端，回傳 `距離公尺` 與 `excludedWithoutCoordinates`。
- API 每筆回應新增 `座標來源` 與 `座標精度`；`/stats` 新增 `coordinateCoverage`。
- 上游資料快取（`CACHE_TTL_SECONDS`，預設 10 分鐘），含上游失敗時的 stale-on-error 降級。
- 底圖切換（通用電子地圖／暗色／正射影像），三種皆為 NLSC 免費圖層。
- App 明確標示座標品質：無座標的設施仍會列出並提供「以地址開啟外部地圖」，`approx` 座標會顯示概略位置警語。
- 測試從零建立：server 85 個、Flutter 22 個。
- CI（analyze／format／test／web build／gitleaks／禁止檔名檢查）與每週上游資料監看排程。
- 開源治理：`LICENSE`（MIT）、`NOTICE.md`（資料授權，含 ODbL 說明）、`CONTRIBUTING.md`（含禁止提交清單）、`SECURITY.md`、`CODE_OF_CONDUCT.md`、issue／PR 範本、`.githooks/pre-commit` 機密掃描。

### Changed

- **地圖底圖從 Google Maps 換成內政部國土測繪中心 WMTS。** 整個專案不再需要任何 API key。`google_maps_flutter`、`pointer_interceptor`、`web/env.js` 機制一併移除。
- 座標來源從 gitignored 的 SQLite 檔改為進版控的 CSV，`sqlite3` 相依與啟發式表格偵測整套移除。
- 後端設定改用 `COORDINATES_CSV`（取代 `GEOCODING_DB`）。
- App 後端位置改用 `--dart-define=API_BASE_URL`，取代硬編碼的 `http://localhost:8080/api`。
- `Shelter.latitude/longitude` 從 `dynamic` 改為 `double?`，移除散落各處的防禦性型別轉換。
- 前端災害條件送出值從 `'true'` 改為 `'Y'`，與 API 文件一致。
- `/shelters` 與 `/shelters/stats` 統一取用同一份資料，不再一個抓 3000 筆、一個抓 2000 筆。

### Fixed

- **篩選與搜尋結果被截斷成最多 5 筆。** `getNearestShelters` 的 `limit` 預設值是 5，卻被當作單純的排序函式呼叫。已拆成 `sortedByDistance`（不截斷）與 `nearestShelters(limit:)`。
- 地圖更新的 `_isUpdating` 旗標沒有 `try/finally` 保護，中途拋例外會永久卡死，地圖不再更新。
- iOS `Info.plist` 缺少 `NSLocationWhenInUseUsageDescription`，取得定位時會直接 crash。
- macOS 缺少 `com.apple.security.network.client` entitlement，沙箱擋掉所有 API 呼叫。
- `/shelters/stats` 回應的 `filters` 遺漏 `villages`。
- `byRegion` 的村里計數與 township 總數口徑不一致（一邊去重、一邊重複累加）。
- 上游 `收容所面積` 為中文說明時，UI 會顯示成「俟搬遷後重新評估 ㎡」。
- catch-all 404 路由註冊在 `io.serve` 之後，未匹配的請求不會落到它。
- 只處理 `SIGINT`、未處理 `SIGTERM`，容器環境下會被硬殺。

### Removed

- **四個未保護的 `/api/debug/geocoding_*` 端點**，其 `table` query 參數直接字串內插進 SQL（`PRAGMA table_info($table)`、`SELECT * FROM $table`），且沒有任何開關可在正式環境關閉。
- 5xx 回應不再把 `e.toString()` 放進 body（會外洩上游 URL、檔案路徑與 stack 細節），改為泛用訊息 + 寫入 log。
- 約 470 行零 consumer 的死碼：`lib/application/`、`presentation/{routes,dtos,mappers,middlewares,responses}`、`core/logger/`、`core/logging/`、`core/errors/` 的三個檔案，以及 `filter_api_response.dart`（前端）。
- 未使用的相依：`sqlite3`、`path`、`json_annotation`、`build_runner`、`json_serializable`（後端），`permission_handler`、`pointer_interceptor`、`google_maps_flutter`（前端）。
- Android 的 `ACCESS_BACKGROUND_LOCATION` 權限——這個 App 沒有背景定位需求。

### Security

- 新增 `.githooks/pre-commit` 與 CI 的 gitleaks job，阻擋金鑰與禁止檔案進版控。
- `.gitignore` 的保護規則同步寫進 `server/` 與 `flutter_codefest/`，避免 repo 拆分後保護失效。
- 稽核結果：git 歷史中沒有任何機密外洩（`git log --all --full-history` 對 `*.env`／`*.db`／`*key*` 零命中，全 repo `AIza` 前綴零命中）。

## [1.0.0]

- 黑客松初始版本。
