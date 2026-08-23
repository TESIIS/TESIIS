# flutter_codefest

TESIIS 臺灣避難收容處所地圖的前端（Flutter）。專案總覽、Docker 執行方式與 API 說明見 [repo 根目錄的 README](../README.md)。

實務上驗證過的目標平台是 **Chrome（Flutter Web）** 與 **macOS desktop**；Android／iOS 專案設定仍在，但不是主要交付對象。

## 執行

```bash
flutter pub get
flutter analyze                   # 應為 0 issues
flutter test                      # 應為 68 passed
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

正式版建置時指定後端位置：

```bash
flutter build web --dart-define=API_BASE_URL=https://api.example.tw/api
```

**後端位置只能經由 `--dart-define=API_BASE_URL` 傳入，不要硬編碼。** 不需要任何 API key——底圖走內政部國土測繪中心的免費 WMTS 服務。

## 目錄結構

```text
lib/
├── main.dart                     # 入口：載入字型設定、掛上 App
├── app.dart                      # MaterialApp、theme、首頁掛載
│
├── core/
│   ├── constants/map_constants.dart   # 地圖中心、縮放級距、bbox 上限等空間常數
│   ├── map/basemap.dart               # NLSC WMTS 圖層定義與來源標示 widget
│   ├── theme/                         # app_theme.dart、app_status_colors.dart
│   └── utils/                         # get_platform.dart、nearby_shelters.dart
│
├── data/
│   ├── datasources/
│   │   ├── api.dart                   # HTTP client，對 API_BASE_URL 發請求
│   │   └── request_cache.dart         # 以請求 URL 為 key 的有界 LRU（12 筆）
│   ├── models/                        # shelter.dart、shelter_page.dart、region_coordinate_stats.dart
│   └── repositories/shelters_repository.dart
│
├── domain/
│   ├── marker_clustering.dart         # 自寫網格式 clustering（不引外部套件）
│   ├── navigation_service.dart        # 組外部地圖導航 URL
│   └── shelter_filters.dart           # 災害／空間類型篩選群組
│
└── presentation/
    ├── pages/                         # map_page.dart、data_quality_page.dart、user_manual_page.dart
    ├── viewmodels/                    # shelter_map_view_model.dart、data_quality_view_model.dart
    └── widgets/
        ├── common/                    # coordinate_notice、disaster_chip、info_row、status_banner
        ├── map/                       # shelter_map_view、shelter_marker_layer、basemap_switcher、cluster_members_sheet
        ├── search/                    # search_toolbar、filter_chip_bar、search_results_list、edge_fade_overlay
        └── shelter/                   # nearby_shelter_panel、shelter_detail_sheet
```

沒有引入 state management 套件。畫面狀態集中在 `presentation/viewmodels/` 的兩個 `ChangeNotifier`（`ShelterMapViewModel` 是主要的那個），widget 只負責呈現。

## 動這個 package 之前該知道的四件事

### 1. NLSC 圖磚路徑是 `{z}/{y}/{x}`

與 OSM 系統的 `{z}/{x}/{y}` **相反**（WMTS 的 TileMatrix／TileRow／TileCol）。搞錯不會噴錯——伺服器照樣回 HTTP 200，只是給空白海洋圖磚（2 KB 而非 32 KB），地圖看起來像整片灰格。由 `test/basemap_test.dart` 守著。

### 2. 資料是視窗式串流，不是一次抓全量

App 不會在啟動時下載全國 5,854 筆清單：

- 地圖 marker 走 `/shelters/clusters`，每次視野變動重新拉取，回應是質心＋數量。
- 最近設施走 `/shelters/nearby`。
- 搜尋結果走 `limit`／`offset` 分頁，滾到底載入下一頁。

**不要為了方便而加回「先抓全量再在 client 過濾」的路徑**，那是全國化時刻意拆掉的東西。

### 3. `nearby_shelters.dart` 有兩個函式，別挑錯

`sortedByDistance`（不截斷）與 `nearestShelters(limit:)`（會截斷）。先前兩者是同一個 `limit = 5` 的函式，導致所有篩選與搜尋結果被砍成 5 筆。**排序時用 `sortedByDistance`。**

### 4. 座標欄位是交叉的

`Shelter.fromJson` 裡 **`座標y` → `latitude`、`座標x` → `longitude`**。弄反會把所有避難所畫到印度洋。

前端的災害條件判斷直接比 `== 'Y'`，靠的是 server 端 `HazardFlag.normalizeForOutput` 的輸出。改任一邊要同步另一邊——契約由 `test/shelter_model_test.dart` 與 `server/test/shelter_controller_test.dart` 兩邊各自守著。

## 地圖來源標示

地圖左下角的「© 內政部國土測繪中心」是 NLSC 使用規範的要求，實作在 `lib/core/map/basemap.dart`。**不要移除。** 詳見 [NOTICE.md](../NOTICE.md)。
