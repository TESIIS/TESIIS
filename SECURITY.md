# 安全性政策

## 回報安全性問題

**請不要開公開 issue 回報安全性問題。**

請透過 GitHub 的 [Private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)（repo 頁面 → Security → Report a vulnerability）回報。

回報時請附上：

- 影響的元件（`server/` 或 `flutter_codefest/`）與版本／commit
- 重現步驟
- 你評估的影響範圍

### 回應時間

這是黑客松作品，由志願者維護，沒有專職資安團隊。我們的目標是：

| 階段 | 目標時間 |
|---|---|
| 確認收到 | 5 個工作天內 |
| 初步評估 | 14 個工作天內 |
| 修補或說明不修補的理由 | 視嚴重程度，會與回報者溝通 |

請在我們回應之前先不要公開揭露。

---

## 這個專案的安全模型

有幾件事值得部署者事先知道。

### 沒有認證，也不該有

Server 只做一件事：代理公開的政府開放資料。**它不儲存任何使用者資料、不接受寫入、沒有資料庫、沒有 session。** 所有回應內容本來就是公開資料。

因此 API 本身沒有認證機制，這是刻意的。如果你要部署到公開網路，請自行考慮：

- **速率限制**：server 對上游有 10 分鐘記憶體快取（`CACHE_TTL_SECONDS`），所以流量不會直接打到內政部消防署的點位檔來源，但你的主機仍可能被打。建議在前面放反向代理處理 rate limit。
- **CORS**：目前用 `shelf_cors_headers` 預設值（允許所有來源）。公開部署前請縮小到你自己的網域。位置在 [`server/bin/server.dart`](server/bin/server.dart)。

### 已經移除的攻擊面

先前版本有四個 `/api/debug/geocoding_*` 端點，會把 query 參數直接字串內插進 SQL（`PRAGMA table_info($table)`、`SELECT * FROM $table`），且沒有任何開關可以在正式環境關掉。這些端點連同整個 SQLite 相依已在改用 CSV 座標表時移除。

如果你從舊版本升級，請確認 `/api/debug/*` 回 404。現行程式碼中已無任何 `/debug` 路由。

### 錯誤訊息不外洩內部細節

5xx 回應只給泛用訊息（`Internal server error. See server logs for details.`），詳細錯誤與 stack trace 只寫進 log。

**server 不再寫檔案日誌**——`bin/server.dart` 把 log 全部導向 stdout／stderr（`WARNING` 以上走 stderr），由容器 runtime 收集。這代表：

- 你的 log 收集端（`docker compose logs`、journald、任何 log 聚合服務）會拿到請求路徑與錯誤細節，**可能含使用者查詢內容與來源 IP，請當作敏感資料處理並設定保存期限。**
- `.gitignore` 仍排除 `logs/`／`*.log`，防的是舊版殘留或你自己導向檔案的情況。

### 定位資料

App 取得的 GPS 座標**只留在裝置端**，用於計算距離與地圖置中，不會送到 server（`/api/shelters/nearby` 端點會收到座標，但 server 不記錄，只用於當次計算）。

iOS 的用途說明字串在 `ios/Runner/Info.plist`，Android 權限在 `AndroidManifest.xml`。已刻意**移除** `ACCESS_BACKGROUND_LOCATION`——這個 App 沒有背景定位需求。

### 沒有 API key

改用內政部國土測繪中心的免費 WMTS 底圖之後，整個專案不需要任何金鑰。這本身就是最好的金鑰外洩防護。詳見 [NOTICE.md](NOTICE.md)。

---

## 給貢獻者

防止機密外洩的規範與工具見 [CONTRIBUTING.md](CONTRIBUTING.md) 的「禁止提交清單」。摘要：

```bash
git config core.hooksPath .githooks   # 安裝 pre-commit 掃描
```

CI 每個 PR 都會跑 gitleaks 與禁止檔名檢查。
