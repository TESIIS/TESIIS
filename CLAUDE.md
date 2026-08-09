# CLAUDE.md

給 Claude Code（claude.ai/code）在這個 repo 工作時的指引。

## 專案概觀

臺北市避難設施查詢系統，2025 臺北程式設計節黑客松團隊 30 作品。兩個各自獨立的 Dart package，沒有共用 package 或 monorepo 工具：

- `server/` — Dart + shelf 的 HTTP API，代理臺北市 OpenData 並補上座標
- `flutter_codefest/` — Flutter App（地圖式查詢介面）

**不需要任何 API key。** 底圖用內政部國土測繪中心的免費 WMTS 服務。

## 常用指令

`flutter` 與 `dart` 來自 `~/flutter/bin`，預設 PATH 已包含。

```bash
# --- server ---
cd server
dart pub get
dart run bin/server.dart          # 預設 port 8080
dart run bin/server.dart 3000     # 位置參數指定 port
dart analyze                      # 應為 0 issues
dart test                         # 應為 85 passed
dart format .                     # CI 會檢查

# 重建座標表（上游資料更新後）
dart run tool/build_coordinates.dart --refresh --overpass --report

# --- flutter_codefest ---
cd flutter_codefest
flutter pub get
flutter analyze                   # 應為 0 issues
flutter test                      # 應為 22 passed
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

實務上可直接執行的目標是 `-d chrome` 與 macOS desktop。**本機沒有安裝 Chrome**，`flutter run -d chrome` 會失敗；要目視驗證請用 `flutter build web` 後自行起一個 static server。CocoaPods 與 Android SDK 的狀態請實際確認再下結論。

## 三件最重要的事

### 1. 座標不是上游來的

**臺北市 OpenData 這個資料集不回傳任何座標欄位。** 實測 401 筆只有 `名稱`/`門牌地址`/`縣市`/災害旗標等，沒有 `座標x`、`座標y`。

地圖上每一個點都來自 `server/data/shelter_coordinates.csv`——**這個檔案進版控**，由 `server/tool/build_coordinates.dart` 離線 join 三個資料集產生：

| 來源 | 說明 |
|---|---|
| 消防署避難收容處所點位檔 | 同類設施，最可信。但 272 筆臺北市資料有 2 筆座標離譜（標到屏東），靠 `TaipeiBounds` 攔下 |
| 北市警政APP_防空避難設備位置 | 6052 筆，自帶 WGS84 座標 |
| OpenStreetMap（Overpass，opt-in） | **ODbL**，會傳染。見 `NOTICE.md` |
| 同路段最近門牌內插 | 最後手段，標為 `approx` |

覆蓋率 380/401（94.8%）。API 每筆回傳 `座標來源` 與 `座標精度`，App 會據此標示品質——**不要移除這些標示**，這是對使用者誠實的部分。

`CoordinateSource.loadFromFile` 找不到檔案時**會拋例外**，不是靜默 fallback。這是刻意的：檔案進版控了，缺檔代表 checkout 有問題。

### 2. 上游資料的怪癖一律走 `shelter_fields.dart`

`server/lib/domain/entities/shelter_fields.dart` 是所有上游資料怪癖的單一處理點。先前同樣的邏輯散在 18 處，導致三個實際 bug。**不要在別處重新實作。**

2026-08-09 對全部 401 筆實測到的值域：

| 欄位 | 值域 |
|---|---|
| 水災 | Y(206) N(195) |
| 震災 | 備用(239) N(100) Y(62) |
| 土石流 | N(390) Y(6) 老舊聚落(5) |
| 海嘯 | N(391) 備用(10) — **完全沒有 Y** |
| 縣市 | 全部 `臺北市`（「臺」不是「台」） |

- **`HazardFlag`**：`備用` 與 `老舊聚落` 都代表「可用」。海嘯沒有任何原生 `Y`，拿掉 alias 會讓 `?tsunami=Y` 永遠回 0。`isYes` 與 `normalizeForOutput` 必須同步，否則 API 會自相矛盾。`?quake=備用` 這種 alias 查詢只回該變體（`isAliasRequest`）。
- **`ShelterText.splitVillages`**：`服務里別` 名目上以 `、` 分隔，實際混了 `。`、換行、全形逗號與註記 `(僅寒暑假可安置)`。只切 `[、，,]` 會弄壞 4 筆（`_id` 67 / 246 / 273 / 346）。
- **`ShelterText.namesEqual`**：對 縣市/鄉鎮/村里/類型 做 `臺`→`台` 折疊。
- **`ShelterNumber`**：數值欄位是字串且不保證是數字。`收容所面積` 有 `14,495`（千分位）與兩筆中文說明，`容納人數` 有一筆中文說明。
- **`ShelterAddress.normalize`**：座標 join 的 key。規則包含中文數字轉換（`汀州路三段四號` vs `汀州路3段4號`）、行政區前綴補齊、`之N`→`-N`、樓層移除。**改這裡務必跑 `dart test`**，`coordinate_source_test.dart` 會檢查覆蓋率沒掉。

### 3. 跨 repo 的隱性契約

前端 `_matchesSelectedFilters` 直接比 `== 'Y'`，靠的是 server 的 `normalizeForOutput`。改任一邊要同步另一邊。兩邊各有契約測試守著（`server/test/shelter_controller_test.dart`、`flutter_codefest/test/shelter_model_test.dart`）。

`Shelter.fromJson` 有欄位交換：**`座標y` → `latitude`、`座標x` → `longitude`**。弄反會把所有避難所畫到印度洋。

## 架構

### server

`bin/server.dart` 是唯一的 wiring 點，DI 用 `get_it`。請求流：

```text
bin/server.dart → ShelterController → ShelterService → ShelterRepositoryImpl
                                                        ├─ ShelterApi        (data.taipei, 10 分鐘快取)
                                                        └─ CoordinateSource  (本地 CSV)
```

`lib/` 底下每個檔案都有 consumer——先前約 470 行死碼（`application/`、`presentation/{routes,dtos,mappers,middlewares,responses}`、`core/logger/`、`core/logging/`）已全數刪除。**不要重新引入這種分層。**

- 要改 API 行為，動 `shelter_controller.dart` 與 `shelter_service.dart`。
- `_ShelterQuery.from(request)` 是所有端點共用的查詢解析，加參數改這裡。
- 5xx 一律回泛用訊息、細節寫 log。**不要把 `e.toString()` 放進 response body。**
- 先前有四個 `/api/debug/geocoding_*` 端點會把 query 參數內插進 SQL，已隨 SQLite 一起移除。**不要重新加入未保護的診斷端點。**

### flutter_codefest

`main.dart` → `MapScreen`（`lib/presentation/pages/home_page.dart`，約 1900 行）。沒有 state management 套件，所有狀態都在這個 `State` 裡用 `setState` 驅動。

- 地圖用 `flutter_map` + `lib/core/map/basemap.dart` 的 NLSC 圖層。
- **NLSC 圖磚路徑是 `{z}/{y}/{x}`**（WMTS 的 TileMatrix/TileRow/TileCol），與 OSM 的 `{z}/{x}/{y}` 相反。搞錯不會噴錯，伺服器照回 HTTP 200，只是給空白海洋圖磚（2 KB 而非 32 KB），地圖看起來像整片灰格。`basemap_test.dart` 守著。
- `nearby_shelters.dart` 刻意拆成 `sortedByDistance`（不截斷）與 `nearestShelters(limit:)`。**排序時不要用會截斷的那個**——先前兩者是同一個 `limit = 5` 的函式，導致所有篩選與搜尋結果被砍成 5 筆。
- 後端位置走 `--dart-define=API_BASE_URL`，不要硬編碼。
- 硬編碼的空間參數：可視範圍半徑 1500 m、臺北市 bbox lat 24.95–25.21 / lng 121.45–121.65、地圖中心 `LatLng(25.0375, 121.5651)`。

## 開源與機密

repo 是公開的。`CONTRIBUTING.md` 有完整的**禁止提交清單**，摘要：`.env`（`.env.example` 除外）、任何金鑰／憑證／簽章檔、`*.db`、`logs/`、`local.properties`、`google-services.json`。

- 座標 CSV 刻意**不含**聯絡人姓名與電話，只有 8 個欄位。**維持這樣。**
- `.githooks/pre-commit` 會擋，CI 也會跑 gitleaks。
- 授權分兩層：程式碼 MIT，資料另有授權（含會傳染的 ODbL）。見 `NOTICE.md`。
- 地圖畫面必須保留「© 內政部國土測繪中心」標示，這是使用規範要求。

## 工作原則

- **驗證優先於宣稱。** 這個 repo 的多數坑都是「看起來會動但實際不會」——空白圖磚回 200、上游 `?q=` 是 no-op、消防署座標標到屏東。跑起來看，不要只讀程式碼推論。
- 改動請以 `analyze` + `test` + 實際啟動驗證。測試現在是真的有效的保護網（server 85 / Flutter 22），不要讓它們變紅。
