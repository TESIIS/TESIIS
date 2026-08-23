# 全國化技術 Roadmap

> **狀態（2026-08-24 核對）：Phase 0–5 皆已完成並上線。**
> 本頁保留原始規劃內容作為決策記錄，各階段開頭補上實際落地情況。
>
> | 階段 | 狀態 | 備註 |
> |---|---|---|
> | Phase 0 — 臺北獨立 Web 基線 | ✅ 完成 | |
> | Phase 1 — 全國資料模型與快照 | ✅ 完成 | 快照 5,854 筆／22 縣市，拒絕 119 筆 |
> | Phase 2 — API 擴充 | ✅ 完成 | 另超出規劃做了 `/shelters/clusters` |
> | Phase 3 — 全國 Web UX | ✅ 完成 | 低速網路與空資料 e2e 測試已加入 |
> | Phase 4 — TDX 交通資訊 | ✅ 完成 | `TdxClient` + `/api/transit/nearby`；不含捷運 |
> | Phase 5 — 發布與維運 | ✅ 完成 | GHCR 多架構 image、deploy 安全網 fallback、15 分鐘排程監控 |

## 目標

將原本 401 筆臺北市避難設施的獨立 Web，擴充為支援臺灣 22 縣市的查詢服務，
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

### Phase 0 — 臺北獨立 Web 基線 ✅

> 已完成。`compose.yaml` 起 `api` + `web` 兩個 service，web 以 Nginx 反向代理 `/api`；
> `/healthz` 回傳資料源、快照時間與各縣市筆數；`bin/server.dart` 同時處理 SIGINT 與
> SIGTERM（Windows 除外）。日誌只走 stdout／stderr。

- Flutter Web 與 Dart API 各自容器化。
- Nginx 對外提供單一 origin，`/api` 反向代理到內部 API。
- 新增 `/healthz`、容器 health check、SIGTERM graceful shutdown。
- 取消檔案日誌依賴，容器只輸出 stdout／stderr。
- 修正 Web title、PWA manifest 與獨立站描述，禁止 iframe 內嵌。

驗收：`docker compose up --build` 後，首頁、搜尋、篩選、定位拒絕狀態與 API
皆可使用。

### Phase 1 — 全國資料模型與快照 ✅

> 已完成。`NfaShelterApi` + `ShelterSnapshotSource` + `NfaShelterMapper` 就位；
> deterministic ID 以 FNV-1a 產生（`NFA-{cityCode}-{hash}`）；品質閘門改用
> `core/geo/taiwan_bounds.dart` 的 22 縣市 bounding box（金門縣因烏坵鄉飛地用兩個 box）。
> 產出 `data/shelters_nationwide.csv`（5,854 筆通過，98.0%）與
> `data/shelters_rejected.csv`（119 筆，全為 `out_of_county_bounds`）。
> `.github/workflows/upstream-data-check.yml` 的 `check-nationwide` job 每週一重跑並保留 90 天 artifact。

1. 建立 `NfaShelterApi`／`NfaShelterSnapshot`，解析全國 CSV。
2. 定義不依賴來源欄名的 normalized schema：
   - `sourceId`, `name`, `cityCode`, `cityName`, `township`, `village`
   - `address`, `location`, `capacity`, `hazards`, `indoor`, `outdoor`
   - `accessible`, `source`, `sourceUpdatedAt`, `coordinateQuality`
3. 以來源 ID 為主；缺少穩定 ID 時，以正規化縣市／地址／名稱產生 deterministic ID。
4. 對臺灣本島、澎湖、金門、連江分別做座標範圍與行政區品質檢查。
5. 將通過驗證的 JSON/CSV snapshot 隨 image 發布；上游失敗時仍提供舊快照。

驗收門檻：22 縣市皆有資料、總筆數異常變動會使 CI 失敗、每筆都有來源與更新時間。

### Phase 2 — API 擴充 ✅

> 已完成，且超出原規劃：除了 `/api/regions`、`bbox` 過濾、`snapshotUpdatedAt`／`dataSource`／
> `dataFreshness` 中繼資料之外，另加了 `/api/shelters/clusters`（server 端網格分群，
> 全台視野回應從 ~470 KB 降到數 KB）與 `disasters`／`spaces` 篩選群組參數
> （群內 OR、跨群 AND）。`limit` 預設值改為 `Env.maxSnapshotItems`，並新增 `truncated` 欄位。

- `GET /api/regions`：縣市、鄉鎮與資料筆數。
- `GET /api/shelters?city=&township=&bbox=&limit=&offset=`：區域與 viewport 查詢。
- `GET /api/shelters/nearby`：保留現有介面並支援全國。
- 回傳 `snapshotUpdatedAt`、`dataSource` 與座標品質統計。
- 對 query、bbox、limit 設定上限，避免一次回傳／計算全國資料。

驗收門檻：每個縣市至少一個 contract test；同一組 filter 在 list、stats、nearby
端點結果一致。

### Phase 3 — 全國 Web UX ✅

> 已完成。前端改為視窗式串流（marker 走 `/shelters/clusters`、附近走 `/shelters/nearby`、
> 搜尋走 `limit`／`offset` 分頁），自寫網格 clustering 在 `domain/marker_clustering.dart`，
> 離線快取改為有界 LRU（`data/datasources/request_cache.dart`，12 筆）。
> 地圖預設中心改為臺灣地理中心，`TaipeiBounds` 警語已移除。
> `e2e/tests/smoke.spec.ts` 現在有 6 項：首頁載入／搜尋／開啟詳情／縣市涵蓋／
> 空資料搜尋／低速網路（Chromium CDP `Network.emulateNetworkConditions` 模擬
> ~6Mbps）。低速網路測試順便量出一個真實瓶頸：`NotoSansTC.ttf`（~12MB）不在
> `nginx.conf` 的 `gzip_types` 清單裡（nginx 預設沒有 `.ttf` 的 MIME type，
> 所以連歸類都歸類不到，更別說壓縮）——這個字型無論本機或正式站都是原始大小
> 傳輸。測試的 timeout 是照這個真實情況量出來的（120s），不是憑空抓的數字；
> 要不要順手修 `nginx.conf` 幫這個字型加 MIME type + gzip 是後續可以做的優化，
> 這次沒有動它。

- 初次進站優先使用使用者定位；未授權時顯示全國視野與縣市選擇器。
- 地圖依 viewport 請求資料，加入 marker clustering；不建立 5,000 個以上 Widget。
- 搜尋結果顯示縣市／鄉鎮，避免同名設施無法辨識。
- 將目前 `TaipeiBounds` 警告改成資料涵蓋／離線狀態提示。
- 保留桌面與 390px 行動版 smoke test，加入低速網路與空資料測試。

驗收門檻：全國初始載入不下載完整明細；一般行動裝置可在 3 秒內操作第一個畫面。

### Phase 4 — TDX 交通資訊 ✅

> 已完成。`server/lib/data/datasources/external/tdx_client.dart` 處理 OAuth2
> client-credentials token 快取（24 小時效期，提前 60 秒重抓）與失敗 backoff；
> `GET /api/transit/nearby?lat=&lng=&city=&radius=&limit=` 平行查詢公車
> （`Bus/Stop/City/{tdxName}`，需要 `city` 才會查）、台鐵、高鐵（皆
> `$spatialFilter=nearby(...)`，TDX 硬限制半徑 1000m），依距離排序合併回傳；
> 任一子系統失敗會標記 `partial: true` 而不是整體失敗，全部失敗或未設定憑證則
> 回 503 `{"available":false}`。前端 `NearbyTransitSection` 掛在避難所詳情頁，
> 不可用時整段不顯示。
>
> **範圍內沒做**：捷運（Metro）——TDX 沒有跨系統的全國「附近站點」端點，捷運
> 要先判斷是哪個系統（TRTC/KRTC/TYMC/…）才能查，複雜度高但涵蓋範圍小，留待
> 之後有需要再做。

驗收門檻：沒有 TDX credentials 時主站仍可用；TDX timeout 時回傳可辨識的降級狀態
——皆已用真實 TDX 憑證與瀏覽器 smoke test 驗證過。

### Phase 5 — 發布與維運 ✅

> 已完成。`.github/workflows/ci.yml` 在 master push 時新增 `publish-images` +
> `merge-manifests` 兩個 job：`publish-images` 用 matrix（`ubuntu-latest` /
> `ubuntu-24.04-arm` 原生 runner，不用 QEMU——`server/Dockerfile` 的
> `dart compile exe` 是 AOT 編譯，模擬下已知會慢或不穩）分別建置 `server`／
> `web` 兩個 image 的 amd64／arm64 版本並以 digest push 到 GHCR；
> `merge-manifests` 把兩個 digest 合併成多架構 manifest，標
> `ghcr.io/tesiis/server:latest`／`ghcr.io/tesiis/web:latest`。
> `compose.yaml` 兩個 service 都加了 `image:`（`build:` 保留不動，本機
> `docker compose up --build` 行為不變）。`deploy.yml` 改成
> `docker compose pull && docker compose up -d || docker compose up -d --build`
> ——pull 失敗（例如 GHCR package 還沒設成 public）會自動退回原本的本機建置
> 路徑，deploy 不會因為這次改動而壞掉。新增 `.github/workflows/monitor.yml`
> 每 15 分鐘打正式站 `/healthz`，檢查 `status`、22 縣市筆數、座標涵蓋率
> （floor 90%）與 latency（floor 5s），失敗時走 GitHub 內建的排程失敗 email
> 通知，沒有另外接 Slack／webhook。
>
> **一次性手動步驟**：GHCR package 第一次由 Actions 建立時預設是 private，
> 即使 repo 是 public 也一樣，需要到 `ghcr.io/tesiis/server` 與
> `ghcr.io/tesiis/web` 的 package 設定裡手動改成 public，VPS 才能匿名
> `docker pull`（改之前 deploy 靠上面的 fallback 照常運作，只是還沒吃到
> 「不用在 VPS 上重新編譯」的好處）。

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
