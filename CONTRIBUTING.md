# 貢獻指南

歡迎參與。這是一個防災用途的公開專案，資料正確性比功能數量重要。

---

## 禁止提交清單（先讀這一段）

這個 repo 是公開的。以下內容一旦推上去就等同公開發布，**即使事後 force push 刪掉，GitHub 的 fork、cache 與各種鏡像仍可能留存**。請務必遵守。

### 絕不提交

| 類別 | 具體檔案 |
|---|---|
| 環境設定 | `.env`、`.env.local`、`.env.production` 等（**`.env.example` 是範本，必須進版控**） |
| 金鑰與憑證 | 任何 API key、access token、OAuth secret、GCP service account JSON、`*.pem`、`*.p12` |
| 簽章檔 | `*.keystore`、`*.jks`、`*.mobileprovision`、`android/key.properties` |
| 平台設定 | `google-services.json`、`GoogleService-Info.plist`、`local.properties` |
| 資料庫檔 | `*.db`、`*.sqlite`、`*.sqlite3` |
| 日誌 | `logs/`、`*.log` — 可能含使用者查詢內容與 IP |
| 建置產物 | `build/`、`.dart_tool/`、`web/env.js` |

### 關於個資

上游資料集含**聯絡人／管理人姓名與電話**。這些是公務聯絡資訊，屬於政府開放資料的一部分，可以保留與傳輸。

現況（請先看清楚再動資料檔）：

- `server/data/shelters_nationwide.csv`（現行主資料，5,854 列）**含 `manager_name` 與 `manager_phone` 兩欄，且每一列都有值**。這是上游消防署點位檔原本就公開的欄位，隨這個公開 repo 一起散布。細節見 [NOTICE.md](NOTICE.md)。
- `server/data/shelter_coordinates.csv`（臺北市時期，執行期已不使用）刻意只有 `shelter_code, name, address, lng, lat, source, confidence, updated_at` 八欄，**不含任何聯絡資訊**，請維持這樣。
- **不要**提交任何含真實民眾個資的資料檔（使用者回報、定位紀錄、查詢紀錄等）。政府開放資料裡的公務聯絡窗口不算，民眾個資一律不行。

### 提交前必做

```bash
# 1. 逐行看過自己的 diff，不要只看檔名
git diff --cached

# 2. 安裝 pre-commit hook（每個 clone 做一次就好）
git config core.hooksPath .githooks
```

hook 會擋掉上述檔案類型與常見的金鑰字串形狀。它是安全網，**不是替代你自己看 diff**。CI 也會跑 [gitleaks](https://github.com/gitleaks/gitleaks) 與檔名檢查，所以繞過 hook 只會讓 PR 在 CI 掛掉。

### 如果不小心提交了機密

1. **立刻撤銷該金鑰**（到發行方後台 revoke／regenerate）。這是第一優先，比清理 git 歷史重要得多——歷史清得掉，已經外流的 key 收不回來。
2. 通知維護者（見 [SECURITY.md](SECURITY.md)）。
3. 清理歷史用 `git filter-repo` 或 BFG，並強制所有協作者重新 clone。

---

## 開發環境

`flutter` 與 `dart` 來自 Flutter SDK（實測於 Flutter 3.44.9；兩個 package 的 `sdk` 約束皆為 `^3.9.2`）。兩個 package 各自獨立，各自 `pub get`。

```bash
# --- 後端 ---
cd server
dart pub get
dart run bin/server.dart          # 預設 port 8080
dart analyze                      # 應為 0 issues
dart test                         # 應為 175 passed

# --- 前端 ---
cd flutter_codefest
flutter pub get
flutter analyze                   # 應為 0 issues
flutter test                      # 應為 68 passed
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

端對端測試需要整套服務跑起來，見 [README.md](README.md#測試與-ci)。

**不需要任何 API key。** 底圖用內政部國土測繪中心的免費 WMTS 服務。如果你在文件裡看到要設定 Google Maps key 的說明，那是舊版本殘留，請一併修掉。

---

## 這個 codebase 的幾條規矩

這些不是風格偏好，是踩過坑之後的結論。

### 1. 上游資料的怪癖一律走 `shelter_fields.dart`

[`server/lib/domain/entities/shelter_fields.dart`](server/lib/domain/entities/shelter_fields.dart) 是所有「上游資料值不照牌理出牌」的單一處理點：`HazardFlag`（災害旗標別名）、`ShelterText`（服務里別切分、臺／台折疊）、`ShelterNumber`（千分位與中文說明值）、`ShelterAddress`（地址正規化）。

先前同樣的邏輯散在 18 處，導致三個實際 bug。**不要在別處重新實作這些規則。**

具體來說：

- **兩個資料源的值域不一樣，別只照其中一邊寫判斷。**
  - 消防署全國點位檔（現行主資料）：災害欄位是 `Y`／`N`，但 `室內`／`室外`／`具無障礙設施` 是 `是`／`否`。
  - 臺北市 OpenData（臺北市離線管線）：`震災` 有 239 筆是 `備用`、`土石流` 有 5 筆是 `老舊聚落`，兩者都代表「可用」；`海嘯` 欄位**完全沒有字面 `Y`**，只有 `備用`，拿掉別名處理會讓 `?tsunami=Y` 永遠回 0 筆。
- 輸出與過濾必須用同一組判斷（`HazardFlag.isYes` 與 `normalizeForOutput`），否則 API 會自相矛盾——`normalizeForOutput` 只正規化「是」而漏掉「否」，就是全國化時真的踩到的 bug（`"室內":"Y"` 旁邊出現 `"室外":"否"`）。
- `服務里別` 名目上以 `、` 分隔，實際還混了 `。`、換行與括號註記。只切 `[、，,]` 會弄壞 4 筆。一律用 `ShelterText.splitVillages`。
- 數值欄位是字串且不保證是數字（臺北市資料有 `14,495`、`俟搬遷後重新評估`）。用 `ShelterNumber`。

### 2. 主資料是自帶座標的全國點位檔，臺北市那套已退居離線

現行地圖畫的每一個點都來自 [`server/data/shelters_nationwide.csv`](server/data/shelters_nationwide.csv)（5,854 列，22 縣市），由 [`server/tool/build_nationwide_snapshot.dart`](server/tool/build_nationwide_snapshot.dart) 產生並進版控。上游消防署點位檔本身就帶 WGS84 經緯度，所以這 5,854 列的 `coordinate_confidence` 全是 `exact`。

執行期的 DI（[`server/lib/core/di/injection.dart`](server/lib/core/di/injection.dart)）只註冊 `NfaShelterApi` 與 `ShelterSnapshotSource`。**`CoordinateSource` 與 data.taipei 的 `ShelterApi` 已不在執行路徑上。**

上游資料更新後重建快照：

```bash
cd server
dart run tool/build_nationwide_snapshot.dart --refresh --report
```

工具內建座標品質閘門：逐列用 `server/lib/core/geo/taiwan_bounds.dart` 的 22 縣市 bounding box 檢查，不通過的寫進 `data/shelters_rejected.csv`（目前 119 列，原因皆為 `out_of_county_bounds`）。**筆數或縣市涵蓋掉下去代表上游有問題，不要直接 commit 過去。**

#### 臺北市座標表（`shelter_coordinates.csv`）

臺北市 OpenData 那個資料集**不回傳任何座標欄位**，所以全國化之前地圖靠 [`server/tool/build_coordinates.dart`](server/tool/build_coordinates.dart) 離線 join 出 401 筆的對照表。這條管線保留著，但已不供執行期使用。要重建：

```bash
cd server
dart run tool/build_coordinates.dart --refresh --report
```

> **不要加 `--overpass`。** 那個旗標會用 OpenStreetMap 補齊剩下的點，覆蓋率能多 2.5 個百分點，但產出的 CSV 會落入 ODbL（share-alike，具傳染性），使 [NOTICE.md](NOTICE.md) 目前「只含政府開放資料」的授權結論失效。帶著 `--overpass` 重建的成果不會被接受。

改動地址正規化規則時務必跑 `dart test`——`coordinate_source_test.dart` 會檢查覆蓋率沒有掉下去。

### 3. 跨 repo 的隱性契約

前端直接比對 `== 'Y'`，靠的是 server 端 `normalizeForOutput` 的輸出。改任一邊都要同步改另一邊。這個契約由 `server/test/shelter_controller_test.dart` 與 `flutter_codefest/test/shelter_model_test.dart` 兩邊各自守住。

另外：`座標y` 對應 `latitude`、`座標x` 對應 `longitude`——**是交叉的**，弄反會把所有避難所畫到印度洋。

### 4. NLSC 圖磚路徑是 `{z}/{y}/{x}`

與 OSM 系統的 `{z}/{x}/{y}` 相反。搞錯不會噴錯，伺服器照樣回 HTTP 200，只是回空白海洋圖磚（2 KB 而非 32 KB），地圖看起來像整片灰格。由 `basemap_test.dart` 守住。

---

## Commit 與 PR

- Commit message 用 [Conventional Commits](https://www.conventionalcommits.org/)，英文，祈使句，小寫開頭，不加句號：
  - `feat:` 新功能／`fix:` 修 bug／`refactor:` 不改行為的重構
  - `perf:` 效能／`test:` 測試／`docs:` 文件／`chore:` 雜項與設定
- 一個 commit 一件事，不要把不相關的變更混在一起。
- PR 請說明**為什麼**要改，不只是改了什麼。如果是修 bug，請描述觸發條件。
- 動到資料處理邏輯的 PR 請附上實測數字（幾筆受影響、覆蓋率變化）。

---

## 回報問題

開 issue 時請附上：

- 你在哪個平台（Web／Android／iOS／macOS）與哪個版本
- 後端啟動時印出的 `[DI] Nationwide snapshot: ...` 那一行（含筆數、縣市數與快照時間）
- 如果是資料錯誤，請附上該避難所的 `收容所編號`

**安全性問題請不要開公開 issue**，見 [SECURITY.md](SECURITY.md)。
