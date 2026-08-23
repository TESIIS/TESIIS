# 第三方資料與服務授權

本專案的**程式碼**以 MIT 授權（見 [LICENSE](LICENSE)）。但 repo 內含的**資料檔**與執行期呼叫的**外部服務**各有自己的條款，兩者不能混為一談。使用或再散布本專案前請先讀完這一頁。

> 本頁最後核對於 2026-08-23，對應的快照 `source_updated_at` 為 `2026-08-22T18:47:48Z`。

---

## 一、repo 內再散布的資料

repo 內有三個進版控的資料檔。**`shelters_nationwide.csv` 是現行地圖的資料來源**，另外兩個是臺北市時期的產物，現在只服務離線工具與人工複核。

| 檔案 | 筆數 | 角色 |
|---|---|---|
| `server/data/shelters_nationwide.csv` | 5,854 | **現行主資料。** 全國 22 縣市快照，執行期的備援底線 |
| `server/data/shelters_rejected.csv` | 119 | 未通過座標品質閘門而被排除的列，附拒絕原因 |
| `server/data/shelter_coordinates.csv` | 401 | 臺北市時期的座標對照表。執行期已不再載入 |

### `server/data/shelters_nationwide.csv`（主資料）

由 `server/tool/build_nationwide_snapshot.dart` 下載並驗證後產生，全部 5,854 列的 `source` 欄位皆為 `nfa_point_file`。

| `source` 欄位值 | 原始資料 | 提供機關 | 授權 | 筆數 |
|---|---|---|---|---|
| `nfa_point_file` | [避難收容處所點位檔](https://data.gov.tw/dataset/73242) | 內政部消防署 | 政府資料開放授權條款第 1 版 | 5,854 |

- 上游檔案本身即帶 WGS84 經緯度，因此全部 5,854 列的 `coordinate_confidence` 均為 `exact`，**沒有任何推估座標**。
- 建置工具會以 `server/lib/core/geo/taiwan_bounds.dart` 的 22 縣市各自 bounding box 逐列檢查；落在錯誤縣市、海上或預設位置的列不進主檔，改寫入 `shelters_rejected.csv`（本次 119 列，原因皆為 `out_of_county_bounds`）。
- 通過率 5,854 / 5,973（98.0%）。

**授權單純：單一來源、政府資料開放授權條款第 1 版，沒有 copyleft／share-alike 條款。** 再散布時依該條款標示出處即可（見下方「資料來源標示」）。

重建方式：

```bash
cd server
dart run tool/build_nationwide_snapshot.dart --report            # 用本機快取
dart run tool/build_nationwide_snapshot.dart --refresh --report  # 重新下載上游
```

#### 個資注意：本檔含管理人姓名與電話

`shelters_nationwide.csv` 有 24 個欄位，其中 **`manager_name` 與 `manager_phone` 兩欄在全部 5,854 列皆有值**。這些是上游點位檔原本就公開的**公務聯絡資訊**，隨政府資料開放授權條款第 1 版釋出，但它們確實隨本 repo 一起公開散布。fork、鏡像或再散布本檔即等同再散布這兩欄。

> 這一點與 [CONTRIBUTING.md](CONTRIBUTING.md) 早期「進版控檔案不含聯絡資訊」的敘述不同——那條規則寫於只有 `shelter_coordinates.csv`（8 欄、刻意不含聯絡資訊）的時期。現況以本頁為準。

### `server/data/shelters_rejected.csv`

同上授權（內政部消防署，政府資料開放授權條款第 1 版）。6 個欄位：`city, township, village, name, address, reject_reason`，不含座標與聯絡資訊。供人工複核上游座標異常用。

### `server/data/shelter_coordinates.csv`（臺北市時期，執行期已不使用）

全國化之前，臺北市 OpenData 的避難收容處所一覽表**不回傳任何座標欄位**，所以地圖上每個點都靠這張離線 join 出來的對照表。全國化後主資料改為自帶座標的消防署點位檔，這張表已不再被 server 載入——`server/lib/core/di/injection.dart` 只註冊 `NfaShelterApi` 與 `ShelterSnapshotSource`。它保留在版控中的理由是 `server/tool/build_coordinates.dart` 仍可重建它，以及保存臺北市管線的授權歸屬記錄。

| `source` 欄位值 | 原始資料 | 提供機關 | 授權 | 筆數 |
|---|---|---|---|---|
| `nfa_point_file` | [避難收容處所點位檔](https://data.gov.tw/dataset/73242) | 內政部消防署 | 政府資料開放授權條款第 1 版 | 252 |
| `taipei_airraid` | [北市警政APP_防空避難設備位置](https://data.taipei/dataset/detail?id=83eecdf1-3bbb-40f9-9484-b55b700c37ef) | 臺北市政府警察局 | 政府資料開放授權條款第 1 版 | 118 |
| `none` | 無座標 | — | — | 31 |

這張表 8 個欄位（`shelter_code, name, address, lng, lat, source, confidence, updated_at`），**刻意不含聯絡人姓名與電話**。

> 早期版本曾以 OpenStreetMap（經 Overpass API）補齊 21 筆，那些列受 **ODbL 1.0** 規範，具傳染性。**現行的 CSV 已不含任何 OSM 衍生資料**，取而代之的是同路段最近門牌內插（標為 `confidence=approx`，來源仍歸屬於提供該鄰近門牌的政府資料集）。代價是覆蓋率由 94.8% 降為 92.3%（370/401），無座標筆數由 21 增為 31。
>
> 重建時 **`--overpass` 為 opt-in，加了就會重新引入 ODbL，預設不要加**：
>
> ```bash
> cd server
> dart run tool/build_coordinates.dart --report   # 現行做法，不加 --overpass
> ```
>
> `approx` 座標的實測誤差為 **40–761 公尺，中位數約 200 公尺**（公園、地下街這類佔地大或入口不明確的設施最差）。任何說明文字請寫「數百公尺」，不要寫成「數十公尺」。

### `server/data/coordinates_needs_review.csv`

臺北市管線的附屬產物，同上授權。列出**有座標但 `confidence != exact`** 的 85 列供人工複核。**無座標的 31 列不在其中**（產生器只收 `hasCoordinate` 的列），要人工補齊請直接對 `shelter_coordinates.csv` 篩 `source=none`。

### 資料來源標示

依政府資料開放授權條款第 1 版第 4 條，再散布本 repo 的資料檔或其衍生物時請標示：

```text
包含內政部消防署「避難收容處所點位檔」，依政府資料開放授權條款第 1 版提供。
```

若一併散布 `shelter_coordinates.csv`，再加上：

```text
包含臺北市政府警察局「北市警政APP_防空避難設備位置」，依政府資料開放授權條款第 1 版提供。
```

---

## 二、執行期呼叫的外部服務

### 內政部消防署 避難收容處所點位檔（主資料源）

Server 執行期向 `Env.nfaPointFileUrl`（預設為內政部 `opdadm.moi.gov.tw` 的資源下載端點）取得全國點位檔，授權為**政府資料開放授權條款第 1 版**。取得後於記憶體快取 `CACHE_TTL_SECONDS`（預設 600 秒）。

上游失敗、或回傳筆數與縣市涵蓋看起來不合理時，會退回 repo 內已驗證的 `shelters_nationwide.csv` 快照，而非直接錯誤。因此外部來源暫時不可用時地圖仍可查詢。

### 內政部國土測繪中心 WMTS 底圖

App 的地圖底圖來自 `https://wmts.nlsc.gov.tw/`，使用 `EMAP`／`EMAP6`／`PHOTO2` 三個圖層。**不需要 API key、不需要註冊帳號。**

依其使用規範，**顯示圖磚的畫面必須標示來源**。本專案在地圖左下角以 `RichAttributionWidget` 標示「© 內政部國土測繪中心」（實作見 [`flutter_codefest/lib/core/map/basemap.dart`](flutter_codefest/lib/core/map/basemap.dart)）。**移除該標示即違反使用規範。**

### 臺北市資料大平臺 OpenData API（僅離線工具使用）

`server/tool/build_coordinates.dart` 會向 `https://data.taipei/api/v1/dataset/` 讀取「臺北市可供避難收容處所一覽表」（dataset ID `4c92dbd4-d259-495a-8390-52628119a4dd`）與「北市警政APP_防空避難設備位置」（`39ca53a1-c861-40bc-b329-fc9b28c10e01`），授權為**政府資料開放授權條款第 1 版**。

**全國化後，執行期的 server 已不再呼叫 data.taipei**，只有重建臺北市座標表這個離線步驟會用到。

### Overpass API（opt-in，現行建置流程未使用）

`server/tool/build_coordinates.dart --overpass` 會呼叫 `https://overpass-api.de/api/interpreter`。這是由捐贈硬體維運的免費公共服務，本工具已依其使用規範設定識別用 User-Agent 並批次化請求。**執行期不會呼叫它，且現行進版控的 CSV 並非以此旗標建置。**

> 加上 `--overpass` 重建會讓產出的 CSV 含有 OSM 衍生資料，因而落入 **ODbL 1.0**（share-alike，具傳染性）。若你這麼做，再散布時必須標示 `© OpenStreetMap contributors` 並以相同授權釋出衍生資料庫，本頁第一節的授權結論即不再適用。

### Google Maps（僅外部導航連結）

App 的「開始導航」按鈕以 `url_launcher` 開啟 `https://www.google.com/maps/...` 連結，交給裝置上的地圖應用處理。這是一般公開網址，**不需要 API key，也沒有嵌入任何 Google 地圖 SDK**。

### TDX（尚未實作）

`server/lib/core/geo/city_codes.dart` 保留了 22 縣市對應 TDX `{City}` 路徑參數的 `tdxName` 欄位，但**目前沒有任何程式碼呼叫 TDX**，也沒有 TDX 相關的執行期相依或憑證。規劃見 [docs/nationwide-roadmap.md](docs/nationwide-roadmap.md) 的 Phase 4。

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
| `shared_preferences` | BSD-3-Clause |
| `shelf` / `shelf_router` / `shelf_cors_headers` | BSD-3-Clause / MIT |
| `get_it` | MIT |
| `http` / `logging` | BSD-3-Clause |

### 字型

`flutter_codefest/assets/fonts/NotoSansTC.ttf` 是 Google Noto Sans TC（可變字重字型），隨 app 打包以避免 Web 版 CanvasKit 在執行期向 Google 字型 CDN 現抓中文字型造成的白屏／缺字。授權為 **SIL Open Font License 1.1**，全文見同目錄 `OFL.txt`。

---

## 四、資料正確性聲明

本系統為**查詢輔助工具**，非官方災害應變系統。

- 上游資料非即時。進版控快照的 `source_updated_at` 為 `2026-08-22T18:47:48Z`，內容則來自消防署該次發布的點位檔。
- 全國 5,854 筆全數帶有上游提供的精確座標，但**座標指向的是設施的地址定位，不保證是災時實際的開放入口**。
- 另有 119 筆因座標落在所屬縣市範圍之外而被排除，這些設施**不會出現在地圖上**，清單見 `shelters_rejected.csv`。
- 臺北市時期的 `shelter_coordinates.csv` 中有 31 筆無座標、79 筆為推估座標（誤差 40–761 公尺），該表現已不供執行期使用。
- **災時請以各地方政府的即時公告為準。**
