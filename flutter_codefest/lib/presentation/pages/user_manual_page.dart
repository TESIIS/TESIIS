import 'package:flutter/material.dart';

class UserManualPage extends StatelessWidget {
  const UserManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '使用手冊',
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colorScheme.primary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        elevation: 0,
      ),
      body: Container(
        color: colorScheme.surfaceContainerLowest,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              context,
              icon: Icons.search,
              title: '1. 搜尋避難所',
              content: [
                '• 點擊搜尋欄輸入地點、避難所名稱或地址',
                '• 系統會自動顯示搜尋建議',
                '• 點選建議項目即可查看詳細資訊',
                '• 使用分類篩選按鈕可快速篩選特定類型的避難所',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.filter_alt,
              title: '2. 分類篩選',
              content: [
                '• 打開搜尋欄後會顯示分類按鈕',
                '• 災害類型:土石流、海嘯、地震、水災',
                '• 空間類型:室內、室外',
                '• 可同時選擇多個分類進行複選篩選',
                '• 點擊已選取的分類可取消選取',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.my_location,
              title: '3. 定位功能',
              content: [
                '• 點擊定位按鈕 (🎯) 取得目前位置',
                '• 首次使用需授予定位權限',
                '• 定位成功後地圖會自動移至您的位置',
                '• 地圖上會顯示 1.5 公里範圍圈',
                '• 系統會自動計算並顯示最近的避難所',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.location_on,
              title: '4. 地圖標記',
              content: [
                '• 紅色標記:目前選中的避難所',
                '• 綠色標記:座標精確的避難所',
                '• 黃色標記:座標為概略值的避難所',
                '• 點擊標記可查看避難所詳細資訊',
                '• 藍色圓圈:1.5 公里搜尋範圍',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.info,
              title: '5. 避難所詳情',
              content: [
                '• 點擊避難所標記或列表項目查看詳情',
                '• 顯示名稱、地址、距離資訊',
                '• 顯示可容納的災害類型標籤',
                '• 顯示室內/室外空間類型',
                '• 可一鍵開始導航或查看更多詳情',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.navigation,
              title: '6. 導航功能',
              content: [
                '• 點擊「開始導航」按鈕',
                '• 自動開啟 Google 地圖導航',
                '• 提供最佳路線指引',
                '• 可選擇步行、開車等交通方式',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.home,
              title: '7. 常駐資訊面板',
              content: [
                '• 底部面板顯示距離最近的避難所',
                '• 即時顯示距離、名稱、地址',
                '• 顯示該避難所的災害類型標籤',
                '• 可直接點擊導航或查看詳情',
                '• 搜尋時會自動隱藏以節省空間',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.tips_and_updates,
              title: '8. 使用技巧',
              content: [
                '• 點擊地圖空白處可關閉搜尋欄和詳情頁',
                '• 使用雙指縮放地圖調整檢視範圍',
                '• 建議開啟定位服務以獲得最佳體驗',
                '• 分類篩選支援左右滑動查看所有選項',
                '• 可隨時點擊返回鍵回到地圖主畫面',
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              icon: Icons.warning_amber,
              title: '9. 注意事項',
              content: [
                '• 確保裝置已開啟定位服務',
                '• 需要網路連線才能使用地圖和搜尋功能',
                '• 導航功能需要安裝 Google 地圖應用程式',
                '• 避難所資訊僅供參考,實際以當地政府公告為準',
                '• 災害發生時請遵循當地政府指示',
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary, width: 1),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.help_outline,
                    color: colorScheme.primary,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '需要協助?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '如有任何問題或建議,歡迎聯絡我們',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> content,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: colorScheme.onPrimary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
