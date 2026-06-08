# flutter_codefest

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

```
lib/
├── main.dart                  # 入口：設定 Provider、路由、Theme
├── core/                      # 核心模組（全域設定、工具、常數）
│   ├── config/                # 環境設定與常數（API base、env變數）
│   ├── theme/                 # 顏色、字型、暗黑模式設定
│   ├── utils/                 # 共用工具（日期格式化、驗證器、logger）
│   ├── errors/                # 自訂例外、錯誤處理
│   └── di/                    # 依賴注入（GetIt / Riverpod provider）
│
├── data/                      # 資料層（與外部交換資料）
│   ├── models/                # 資料模型（JSON ↔ Dart object）
│   ├── datasources/           # API / LocalDB / SharedPref
│   ├── repositories/          # 封裝邏輯、資料聚合（符合 domain interface）
│   └── mocks/                 # 測試／開發假資料
│
├── domain/                    # 商業邏輯層
│   ├── entities/              # 實體（純邏輯物件，不依賴 Flutter）
│   ├── repositories/          # 抽象介面（repository interfaces）
│   ├── usecases/              # UseCase：一個行為＝一個 class
│   └── services/              # Domain Service：複合邏輯（如 AI 推薦）
│
├── presentation/              # UI 層（Widget、State、ViewModel）
│   ├── pages/                 # 各畫面（HomePage, LoginPage, etc.）
│   ├── widgets/               # 可重用元件（Button, Card, ListItem）
│   ├── viewmodels/            # 狀態管理（MVVM ViewModel）
│   ├── navigation/            # 路由（GoRouter / AutoRoute）
│   └── localization/          # 多語系設定
│
├── app.dart                   # App widget / MaterialApp / router 註冊
└── injection.dart              # DI 容器初始化（GetIt / Provider 註冊）
```
