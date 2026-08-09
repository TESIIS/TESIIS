## 這個 PR 做了什麼

<!-- 說明「為什麼」要改，不只是改了什麼。修 bug 請描述觸發條件。 -->

## 相關 issue

<!-- Closes #123 -->

## 驗證方式

<!-- 你實際跑了什麼確認它有效？貼上輸出。 -->

```
# cd server && dart analyze && dart test
# cd flutter_codefest && flutter analyze && flutter test
```

## 檢查清單

- [ ] `dart analyze` / `flutter analyze` 皆為 0 issues
- [ ] `dart test` / `flutter test` 全過
- [ ] 已逐行看過 `git diff --cached`，沒有金鑰、`.env`、`*.db`、log 或個資
      （見 [CONTRIBUTING.md](../CONTRIBUTING.md) 的禁止提交清單）
- [ ] Commit message 符合 Conventional Commits

<!-- 以下依情況勾選，不適用可刪除 -->

- [ ] **動到上游資料處理**：新規則寫在 `shelter_fields.dart`，沒有在別處重新實作，並附上實測筆數
- [ ] **動到座標管線**：已重跑 `dart run tool/build_coordinates.dart --report`，覆蓋率沒有下降
- [ ] **動到 API 回應格式**：前端 `Shelter.fromJson` 已同步，兩邊的契約測試都有更新
