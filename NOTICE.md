# 第三方資料與服務授權

本專案的**程式碼**以 MIT 授權（見 [LICENSE](LICENSE)）。但 repo 內含的**資料檔**與執行期呼叫的**外部服務**各有自己的條款，兩者不能混為一談。使用或再散布本專案前請先讀完這一頁。

---

## 一、repo 內再散布的資料

### `server/data/shelter_coordinates.csv`

這是本專案唯一進版控的資料檔，也是地圖上每一個標記的座標來源。它是由下列來源 join 產生的衍生資料，因此**混合了多種授權**。CSV 的 `source` 欄位標明每一列的來源，可據以逐列判斷。

| `source` 欄位值 | 原始資料 | 提供機關 | 授權 | 筆數 |
|---|---|---|---|---|
| `nfa_point_file` | [避難收容處所點位檔](https://data.gov.tw/dataset/73242) | 內政部消防署 | 政府資料開放授權條款第 1 版 | 251 |
| `taipei_airraid` | [北市警政APP_防空避難設備位置](https://data.taipei/dataset/detail?id=83eecdf1-3bbb-40f9-9484-b55b700c37ef) | 臺北市政府警察局 | 政府資料開放授權條款第 1 版 | 108 |
| `osm_overpass` | OpenStreetMap（經 Overpass API） | OpenStreetMap contributors | **ODbL 1.0** | 21 |
| `manual` | 人工從公開地圖目視填入 | — | 座標事實本身不受著作權保護 | 0 |
| `none` | 無座標 | — | — | 21 |

> **ODbL 是唯一有傳染性的一條。** `source=osm_overpass` 的 21 列衍生自 OpenStreetMap，受 ODbL 1.0 規範：再散布這份 CSV（或其衍生資料庫）時必須標示 `© OpenStreetMap contributors`，且衍生資料庫需以相同授權釋出。
>
> 若你需要一份授權單純的座標表，執行下列指令重建，並手動補齊那 21 筆（座標事實本身不受著作權保護，人工從公開地圖讀取後標記為 `manual` 即可）：
>
> ```bash
> cd server
> dart run tool/build_coordinates.dart --report   # 不加 --overpass
> ```
>
> 不使用 Overpass 時的覆蓋率約 89%（其餘由同路段門牌內插補齊），純政府開放資料的精確比對覆蓋率為 72.6%。

### `server/data/coordinates_needs_review.csv`

同上授權。這份檔案列出所有 `confidence != exact` 的列，供人工複核用。

---

## 二、執行期呼叫的外部服務

### 內政部國土測繪中心 WMTS 底圖

App 的地圖底圖來自 `https://wmts.nlsc.gov.tw/`，使用 `EMAP`／`EMAP6`／`PHOTO2` 三個圖層。**不需要 API key、不需要註冊帳號。**

依其使用規範，**顯示圖磚的畫面必須標示來源**。本專案在地圖左下角以 `RichAttributionWidget` 標示「© 內政部國土測繪中心」（實作見 [`flutter_codefest/lib/core/map/basemap.dart`](flutter_codefest/lib/core/map/basemap.dart)）。**移除該標示即違反使用規範。**

### 臺北市資料大平臺 OpenData API

Server 執行期向 `https://data.taipei/api/v1/dataset/` 讀取「臺北市可供避難收容處所一覽表」（dataset ID `4c92dbd4-d259-495a-8390-52628119a4dd`，401 筆），授權為**政府資料開放授權條款第 1 版**。此資料**不隨 repo 散布**，每次請求即時取得（含 10 分鐘記憶體快取）。

### Overpass API（僅離線建置時使用）

`server/tool/build_coordinates.dart --overpass` 會呼叫 `https://overpass-api.de/api/interpreter`。這是由捐贈硬體維運的免費公共服務，本工具已依其使用規範設定識別用 User-Agent 並批次化請求。**執行期不會呼叫它。**

### Google Maps（僅外部導航連結）

App 的「開始導航」按鈕以 `url_launcher` 開啟 `https://www.google.com/maps/...` 連結，交給裝置上的地圖應用處理。這是一般公開網址，**不需要 API key，也沒有嵌入任何 Google 地圖 SDK**。

---

## 三、程式相依套件

各套件授權見各自的 `pubspec.yaml` 與 pub.dev 頁面。主要相依：

| 套件 | 授權 |
|---|---|
| `flutter_map` | BSD-3-Clause |
| `latlong2` | Apache-2.0 |
| `geolocator` | MIT |
| `flutter_svg` | MIT |
| `url_launcher` | BSD-3-Clause |
| `shelf` / `shelf_router` / `shelf_cors_headers` | BSD-3-Clause / MIT |
| `get_it` | MIT |
| `http` / `logging` | BSD-3-Clause |

---

## 四、資料正確性聲明

本系統為**查詢輔助工具**，非官方災害應變系統。

- 上游資料非即時（截至 2026-08-09，`_importdate` 為 2025-11-28）。
- 401 筆中有 21 筆無法定位，另有 89 筆座標為依鄰近門牌**推估的概略值**，可能與實際入口相差數十公尺。App 會在介面上明確標示這兩種情況。
- **災時請以臺北市政府即時公告為準。**
