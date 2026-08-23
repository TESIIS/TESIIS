# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)。

## [Unreleased]

讓專案真正可用並完成開源化。這一輪修掉的是「clone 下來跑不動」的三個獨立原因。

### Added

- **座標資料管線。** 新增 `server/tool/build_coordinates.dart`，離線 join 兩個政府開放資料集產生 `server/data/shelter_coordinates.csv` 並進版控。401 筆避難所中 370 筆（92.3%）取得座標，先前是 0 筆。進版控的座標表**只含政府資料開放授權條款第 1 版的資料**；以 OpenStreetMap 補齊的 `--overpass` 是 opt-in 且預設不使用，因為它會讓成果落入具傳染性的 ODbL。以 2.5 個百分點的覆蓋率換取單純的授權條件。
- `GET /api/shelters/nearby?lat=&lng=&radius=&limit=` — 距離計算移到 server 端，回傳 `距離公尺` 與 `excludedWithoutCoordinates`。
- API 每筆回應新增 `座標來源` 與 `座標精度`；`/stats` 新增 `coordinateCoverage`。
- 上游資料快取（`CACHE_TTL_SECONDS`，預設 10 分鐘），含上游失敗時的 stale-on-error 降級。
- 底圖切換（通用電子地圖／暗色／正射影像），三種皆為 NLSC 免費圖層。
- App 明確標示座標品質：無座標的設施仍會列出並提供「以地址開啟外部地圖」，`approx` 座標會顯示概略位置警語。
- 測試從零建立：server 96 個、Flutter 22 個。
- CI（analyze／format／test／web build／gitleaks／禁止檔名檢查）與每週上游資料監看排程。
- 開源治理：`LICENSE`（MIT）、`NOTICE.md`（資料授權與再散布標示要求）、`CONTRIBUTING.md`（含禁止提交清單）、`SECURITY.md`、`CODE_OF_CONDUCT.md`、issue／PR 範本、`.githooks/pre-commit` 機密掃描。
- **前端離線快取。** 每次成功抓到避難所清單後存進 `shared_preferences`；API 連不上時改用上次快取的資料並標示「顯示上次快取資料」，不再直接空白。地圖圖磚快取不在範圍內。
- 步行時間概估（直線距離 ÷ 1.4 m/s），顯示在避難所詳情與最近避難所面板；明確標示為概算而非真實路線。
- `/shelters/stats` 的 `byRegion` 新增每個縣市／鄉鎮／村里的座標品質統計（`coordinateQuality`：`total`／`withCoordinates`／`missing`／`bySource`／`byConfidence`），供資料品質頁面使用。前端新增「座標資料品質」頁，依缺座標數排序列出各鄉鎮。
- `e2e/`：Playwright 端對端煙霧測試（首頁載入、搜尋、開啟避難所詳情），對著 `docker compose up --build` 的完整站台跑；CI 新增對應 job。
- **全國化：主資料源換成消防署全國避難收容處所點位檔。** 新增 `server/tool/build_nationwide_snapshot.dart`，直接下載已含座標的全國點位檔（22 縣市、5,973 筆），逐縣市座標品質閘門驗證後產生並 commit `server/data/shelters_nationwide.csv`（5,854 筆通過，98.0%）與 `server/data/shelters_rejected.csv`（含拒絕原因）。`server/lib/core/geo/taiwan_bounds.dart` 取代 `taipei_bounds.dart`，改成 22 縣市各自的 bounding box（金門縣因烏坵鄉飛地需要兩個 box）。臺北市既有的 `build_coordinates.dart`／`shelter_coordinates.csv` 保留不動，作為次要資料源與授權來源記錄。
- **既有 API 線上契約（中文 key）維持不變**，全國化屬於內部資料源替換，`/api/shelters`、`/api/shelters/stats`、`/api/shelters/nearby` 的既有欄位不改不刪；新增 `核子事故`（NFA 才有的災害類型）、`truncated`（分頁是否被截斷）、`snapshotUpdatedAt`／`dataSource`／`dataFreshness` 中繼資料。
- `GET /api/regions[?city=]`：22 縣市（或指定縣市的鄉鎮）清單，各自帶座標品質統計，供縣市選擇器與資料品質頁面使用。
- `/shelters`、`/shelters/stats`、`/shelters/nearby` 新增 `?bbox=minLng,minLat,maxLng,maxLat` 過濾（上限 2° × 2°）。
- 前端新增自寫網格式 marker clustering（`flutter_codefest/lib/domain/marker_clustering.dart`），避免全國搜尋或密集行政區一次渲染數千個 marker widget；刻意不加現成套件，理由與 `csv_codec.dart` 手刻 CSV parser 相同。搜尋結果新增縣市／鄉鎮前綴，避免全國同名設施（「活動中心」「○○國小」）無法辨識。

### Changed

- **地圖底圖從 Google Maps 換成內政部國土測繪中心 WMTS。** 整個專案不再需要任何 API key。`google_maps_flutter`、`pointer_interceptor`、`web/env.js` 機制一併移除。
- 座標來源從 gitignored 的 SQLite 檔改為進版控的 CSV，`sqlite3` 相依與啟發式表格偵測整套移除。
- 後端設定改用 `COORDINATES_CSV`（取代 `GEOCODING_DB`）。
- App 後端位置改用 `--dart-define=API_BASE_URL`，取代硬編碼的 `http://localhost:8080/api`。
- `Shelter.latitude/longitude` 從 `dynamic` 改為 `double?`，移除散落各處的防禦性型別轉換。
- 前端災害條件送出值從 `'true'` 改為 `'Y'`，與 API 文件一致。
- `/shelters` 與 `/shelters/stats` 統一取用同一份資料，不再一個抓 3000 筆、一個抓 2000 筆。
- 導航連結的 `travelmode` 從 `driving` 改為 `walking`——這是避難步行導引，不是開車導航。
- 地圖預設中心點從臺北車站改成臺灣地理中心（南投埔里附近），拿掉「超出臺北市範圍」警語——全國資料下這個警語本身就是錯的。
- `server/lib/domain/services/shelter_service.dart` 的 `computeStats`：`items` 與每層 `villages`/`townships` 內嵌的 `shelters` 陣列改成預設不回傳，`?include=items,shelters` 才加。401 筆臺北市資料時無過濾的 `/shelters/stats` 還好，5,854 筆全國資料會讓同一筆資料在回應裡重複出現 2-3 次、變成好幾 MB 的 JSON——這是全國化後第一個會壞掉的端點，資料品質頁面正好打這支 API。

### Fixed

- `GET /shelters` 的 `limit` 預設值 1000：401 筆臺北市資料時從沒觸發過，換成全國 5,854 筆後前端會**默默拿到被砍掉三分之二的清單、卻沒有任何錯誤或截斷提示**。預設值改成 `Env.maxSnapshotItems`（8000），並新增 `truncated` 欄位讓 client 隨時能判斷清單是否完整。
- `HazardFlag.normalizeForOutput` 只把「是」正規化成 `Y`，沒有對應把「否」正規化成 `N`——臺北市資料的災害欄位本來就是原生 `N`，這條路徑從沒被踩過，直到全國資料用「是／否」才讓 `"室內":"Y"` 旁邊出現 `"室外":"否"` 這種不一致的 API 輸出。
- 全國資料的座標品質閘門用 FNV-1a 雜湊產生 `收容所編號`，Dart 原生 `int` 是固定 64-bit 沒有 bignum 自動升級，雜湊值 sign bit 為 1 時 `toRadixString` 會印出帶負號的字串（例如 `NFA-CHA--1186...`）而非乾淨的十六進位。
- 避難所詳情頁的「救濟站」對每一筆全國資料都顯示「否」。NFA 資料沒有「救濟支站」欄位，API 回傳 `null`，前端把 null 轉成空字串後又用 `== 'Y' ? '是' : '否'` 判斷——空字串永遠不等於 `'Y'`，於是「不知道」被顯示成肯定的「不是」。改成只有 `Y`/`N` 兩種原生值才顯示，其餘（含 NFA 的空值）直接不顯示這一行，跟其他缺欄位的呈現方式一致。
- `.github/workflows/upstream-data-check.yml` 只監看臺北市次要管線（`build_coordinates.dart`），現在地圖的命脈——全國快照——完全沒人在看，上游改格式或掉筆數不會有任何警訊。新增 `check-nationwide` job，跑 `build_nationwide_snapshot.dart --refresh --report`（工具本身的品質閘門就是覆蓋率檢查），並把報告與被拒清單存成 90 天的 artifact。
- 搜尋結果每一列都會噴一次 `ListTile background color or ink splashes may be invisible` 的 framework 斷言——結果清單外層的 `Container` 用 `BoxDecoration` 畫背景，擋在 `ListTile` 與最近的 `Material` 祖先之間。改用 `Material` 承載背景色/圓角/陰影，順便讓清單內容的圓角裁切正確（原本捲動內容不會被裁成圓角）。
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
