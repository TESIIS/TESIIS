# 生活圈避難準備

## 操作

### 收藏與分享

1. 從地圖或搜尋結果開啟避難所，點「收藏」，填入分組與私人備註。
2. 在「我的避難準備 → 收藏」查看、編輯、更新或移除收藏。勾選 2～3 處可比較設施條件。
3. 「分享」提供個別避難所連結、QR Code 與裝置分享選單；不支援裝置分享時改複製文字。

收藏以 `收容所編號` 識別，整數 `id` 只是資料列序號。來源名稱／地址改變時可能產生新的編號；更新收藏遇到 404 會保留舊摘要並標示找不到來源。分享網址只包含地點編號，不包含 GPS、私人備註或家庭聯絡人。

### 替家人查附近設施

- 「行政區與需求」可選縣市、鄉鎮與「適合避難弱者安置」條件。
- 點「指定查詢地點」後在地圖點選位置，也可長按或右鍵。
- 選擇 500、1,000、3,000 或 5,000 公尺半徑。橘色標記是查詢起點，與裝置 GPS 分開保存於當次工作階段。
- 清除「指定位置」晶片可回復一般查詢；定位按鈕取得位置成功後可改回使用裝置位置。
- 關鍵字、災害、空間與行政區條件會套用到查詢結果；災害群組內為 OR、空間群組內為 OR、不同群組間為 AND。

### 家庭避難卡

在「家庭計畫」從收藏選擇不同的主要與備用集合點，填入聯絡人、約定與準備清單後儲存。

- 計畫自帶地點摘要，移除收藏或區域資料包不會移除計畫中的集合點。
- 可分享文字；Web 另提供列印／PDF 與 HTML 避難卡下載。
- HTML 卡片內嵌 QR Code，離線開啟仍可閱讀與列印。QR Code 連向各地點的網站詳情。
- 卡片包含你填入的聯絡資訊與備註。資料保存在目前裝置／瀏覽器，沒有帳號或伺服器端家庭資料庫。

### 離線使用

1. 連線時開啟「離線資料 → 下載區域」，選擇縣市，或進一步選擇鄉鎮。
2. 等待資料包保存；首次使用會接著準備離線啟動資源。資源包含程式、渲染器與字型，下載大小隨建置而異（目前約 53 MiB）。
3. 確認區域卡片有筆數、版本、下載日期，且上方顯示「已備妥離線啟動資源」。
4. 可開啟「使用離線資料」試用，或直接斷網重新開啟 `/app/`。
5. 在已下載區域內可以重新搜尋、套用新條件、分群、查距離、查看詳情與家庭計畫。可使用精簡清單模式。

資料包與啟動資源分開顯示狀態：保存資料包成功，不代表啟動資源一定下載成功。後者失敗時可再次點「準備離線啟動」。資料下載及寫入驗證通過後才替換舊包；版本更新未完整下載時，原本可用的 Service Worker 保持啟用。

離線結果只代表已下載範圍。底圖、即時交通與外部導航需要網路；地圖圖磚不會批次下載。Web 嘗試申請持久儲存，但瀏覽器仍可能因清除網站資料或儲存政策而移除本機內容，使用前可在離線資料頁檢查狀態。

### 顯示設定

「設定」提供淺色／深色／跟隨系統、大字與精簡清單模式，設定保存在裝置上。地圖工具列也可直接切換清單與地圖。

## 資料語意

- 容量是消防署資料中的**預計收容人數**，不代表即時剩餘名額。
- 全國來源的「適合避難弱者安置」保留原意；具體的輪椅入口、電梯與廁所資訊不能從這個欄位推定。
- `資料取得時間`／`dataUpdatedAt` 表示系統取得該版本的時間，不等同地方政府更新公告的時間。
- 距離與步行時間概估仍以直線計算；外部地圖提供其自己的導航路線。

## API

### 單筆地點

```text
GET /api/shelters/<shelterCode>
```

200 回傳 `{success, dataSource, dataFreshness, dataUpdatedAt, data}`；不存在回 404。特殊字元應作 URL path segment 編碼。靜態路由 `stats`、`nearby`、`clusters`、`package` 優先於動態編號路由。

### 完整區域包

```text
GET /api/shelters/package?city=臺北市&township=中正區
```

`city` 必填，`township` 選填。其他篩選／分頁參數會回 400，以免部分資料被誤當成完整區域。一次讀取同一份 repository 資料後回傳：

```json
{
  "success": true,
  "schemaVersion": 1,
  "snapshotVersion": "nfa-v1-…",
  "coverage": {"city": "臺北市", "township": "中正區"},
  "total": 123,
  "truncated": false,
  "dataSource": "nfa_point_file",
  "dataFreshness": "live",
  "dataUpdatedAt": "…",
  "data": []
}
```

上例為結構示意，實際 `data.length` 必須等於 `total`。`snapshotVersion` 是內容版本檢查碼，不作為資料認證；不因單純的取得時間或資料列序號改變而更新。

## 實作位置

| 元件 | 位置 |
|---|---|
| 原子儲存、收藏、設定、計畫 | `flutter_codefest/lib/data/repositories/preparedness_store.dart` |
| 線上／離線資料存取 | `flutter_codefest/lib/data/repositories/shelter_gateway.dart` |
| 本機篩選／搜尋／距離 | `flutter_codefest/lib/domain/offline_query.dart` |
| IndexedDB、分享、列印 | `flutter_codefest/web/preparedness.js` |
| 離線啟動及版本更新 | `flutter_codefest/web/offline-sw.js` |
| 建置資源清單 | `flutter_codefest/tool/prepare_web.dart` |
| 收藏／計畫／下載／設定 UI | `flutter_codefest/lib/presentation/pages/preparedness_page.dart` |

Web 的 IndexedDB 使用單一版本化文件原子提交。Dart 端序列化寫入，成功後才更新畫面；跨分頁以 revision 比對避免舊資料覆寫新計畫。寫入失敗可重新整理以讀取最新資料後重試。原生平台透過 SharedPreferences 保存；主要驗證目標為 Web。

## 建置與驗證

```bash
cd flutter_codefest
flutter pub get
flutter analyze
flutter test
flutter build web --base-href /app/ --dart-define=API_BASE_URL=/api
dart run tool/prepare_web.dart
```

完整 `build/web/` 必須部署到 `/app/`。`offline-sw.js` 與 `offline-manifest.js` 不應使用長效 HTTP 快取。啟動資源完整下載後才切換版本，已有使用者會看到重新載入提示。首次進站不會自動下載整份離線啟動資源。

Docker 的 Web 建置與 GitHub Actions 已包含資源清單產生步驟。

若本機沒有 Docker，可在完成上述建置後使用正式 Web 成品與 Dart API 跑測試：

```powershell
# 在 e2e/ 執行；須先於 server/ 執行 dart pub get
$env:LOCAL_STACK='1'
npx playwright test --workers=1
```

`serve-local.mjs` 使用 18088（Web）和 18081（API），測試時固定讓主資料源不可用以驗證進版控快照，並停用 TDX。它是測試用啟動器；正式部署使用既有 Nginx／Compose。

新增測試涵蓋：儲存失敗不覆寫、併發寫入、損壞文件、跨區包去重、條件一致性、晚到 GPS、404 與離線降級、分享資訊、HTML 跳脫、行動收藏、家庭卡匯出，以及清除 HTTP 快取後的離線新分頁搜尋。
