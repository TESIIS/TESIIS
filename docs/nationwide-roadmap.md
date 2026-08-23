# 全國化技術 Roadmap

## 目標

將目前 401 筆臺北市避難設施的獨立 Web，擴充為支援臺灣 22 縣市的查詢服務，
同時維持下列原則：

- 災時即使上游暫時不可用，服務仍能提供最近一次驗證過的資料快照。
- 地圖不一次繪製全國所有 marker，行動裝置仍能流暢操作。
- TDX 金鑰只存在後端，絕不進入 Flutter bundle 或 Git。
- 每筆資料保留來源、更新時間與座標品質，不把推估點偽裝成精確點。

## 資料來源定位

### 避難設施主資料

以消防署「避難收容處所點位檔」作為全國主資料。目前檔案約 5,973 筆，已包含
縣市鄉鎮、地址、經緯度、容納人數、適用災害、室內／室外與弱者安置欄位。

現有 `tool/build_coordinates.dart` 已經下載這份全國檔案，但只取臺北市來補座標；
全國化時應新增獨立的 NFA adapter，直接產生標準化 Shelter entity，不再用臺北市
OpenData 當全國主表。

### TDX

TDX 沒有避難收容所主資料。它在本系統的責任是：

- 提供標準化縣市代碼與行政區對照。
- 第二階段提供避難所附近的公車站、軌道站或公共運輸資訊。
- Client Credentials token 由後端取得並快取，Flutter 不接觸 Client Secret。

參考：

- [消防署避難收容處所點位檔](https://data.gov.tw/dataset/73242)
- [TDX API 服務](https://tdx.transportdata.tw/api-service/swagger)
- [TDX API 授權驗證](https://motc-ptx.gitbook.io/tdx-xin-shou-zhi-yin/api-shi-yong-shuo-ming/api-shou-quan-yan-zheng-yu-shi-yong-fang-shi)

## 分階段實作

### Phase 0 — 臺北獨立 Web 基線（本次）

- Flutter Web 與 Dart API 各自容器化。
- Nginx 對外提供單一 origin，`/api` 反向代理到內部 API。
- 新增 `/healthz`、容器 health check、SIGTERM graceful shutdown。
- 取消檔案日誌依賴，容器只輸出 stdout／stderr。
- 修正 Web title、PWA manifest 與獨立站描述，禁止 iframe 內嵌。

驗收：`docker compose up --build` 後，首頁、搜尋、篩選、定位拒絕狀態與 API
皆可使用。

### Phase 1 — 全國資料模型與快照

1. 建立 `NfaShelterApi`／`NfaShelterSnapshot`，解析全國 CSV。
2. 定義不依賴來源欄名的 normalized schema：
   - `sourceId`, `name`, `cityCode`, `cityName`, `township`, `village`
   - `address`, `location`, `capacity`, `hazards`, `indoor`, `outdoor`
   - `accessible`, `source`, `sourceUpdatedAt`, `coordinateQuality`
3. 以來源 ID 為主；缺少穩定 ID 時，以正規化縣市／地址／名稱產生 deterministic ID。
4. 對臺灣本島、澎湖、金門、連江分別做座標範圍與行政區品質檢查。
5. 將通過驗證的 JSON/CSV snapshot 隨 image 發布；上游失敗時仍提供舊快照。

驗收門檻：22 縣市皆有資料、總筆數異常變動會使 CI 失敗、每筆都有來源與更新時間。

### Phase 2 — API 擴充

- `GET /api/regions`：縣市、鄉鎮與資料筆數。
- `GET /api/shelters?city=&township=&bbox=&limit=&offset=`：區域與 viewport 查詢。
- `GET /api/shelters/nearby`：保留現有介面並支援全國。
- 回傳 `snapshotUpdatedAt`、`dataSource` 與座標品質統計。
- 對 query、bbox、limit 設定上限，避免一次回傳／計算全國資料。

驗收門檻：每個縣市至少一個 contract test；同一組 filter 在 list、stats、nearby
端點結果一致。

### Phase 3 — 全國 Web UX

- 初次進站優先使用使用者定位；未授權時顯示全國視野與縣市選擇器。
- 地圖依 viewport 請求資料，加入 marker clustering；不建立 5,000 個以上 Widget。
- 搜尋結果顯示縣市／鄉鎮，避免同名設施無法辨識。
- 將目前 `TaipeiBounds` 警告改成資料涵蓋／離線狀態提示。
- 保留桌面與 390px 行動版 smoke test，加入低速網路與空資料測試。

驗收門檻：全國初始載入不下載完整明細；一般行動裝置可在 3 秒內操作第一個畫面。

### Phase 4 — TDX 交通資訊

- 新增 server-side `TdxClient`，實作 token expiry buffer、timeout、retry、快取與
  circuit breaker。
- 將中文縣市名稱映射到 TDX City/County code。
- 先做「避難所附近公共運輸站點」唯讀功能，不讓 TDX 故障阻斷避難所主流程。
- UI 與文件依 TDX 規範標示資料來源。

驗收門檻：沒有 TDX credentials 時主站仍可用；TDX timeout 時回傳可辨識的降級狀態。

### Phase 5 — 發布與維運

- CI 建置 `linux/amd64` 與 `linux/arm64` images，推送 GHCR。
- 每週抓取新資料到暫存區，完成 schema、筆數、縣市與座標檢查後才發布 snapshot。
- 監控 `/healthz`、上游更新時間、各縣市筆數、座標缺漏率與 API latency。
- 正式環境由外層 reverse proxy／load balancer 終止 TLS；Compose 不保存使用者定位。

## 建議的完成定義

- `docker compose up --build` 可從乾淨 clone 啟動。
- Chrome、Safari、Firefox 的桌面與行動版皆通過核心查詢流程。
- API 與 Web 不包含 TDX Client Secret、個人定位紀錄或使用者查詢日誌。
- 任一上游服務中斷時，已發布的避難所快照仍可查詢。
- 22 縣市資料品質報告可由 CI 重現並留存。
