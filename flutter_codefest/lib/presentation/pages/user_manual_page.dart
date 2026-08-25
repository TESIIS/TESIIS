import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:url_launcher/url_launcher.dart';

final _issuesUri = Uri.parse('https://github.com/TESIIS/TESIIS/issues');

class _SectionData {
  const _SectionData({
    required this.icon,
    required this.title,
    required this.content,
  });

  final IconData icon;
  final String title;
  final List<String> content;
}

const _sections = [
  _SectionData(
    icon: Icons.search,
    title: '1. 搜尋避難所',
    content: [
      '• 點擊搜尋欄輸入地點、避難所名稱或地址',
      '• 系統會自動顯示搜尋建議',
      '• 點選建議項目即可查看詳細資訊',
      '• 使用分類篩選按鈕可快速篩選特定類型的避難所',
    ],
  ),
  _SectionData(
    icon: Icons.filter_alt,
    title: '2. 分類篩選',
    content: [
      '• 打開搜尋欄後會顯示分類按鈕',
      '• 災害類型：土石流、海嘯、地震、水災',
      '• 空間類型：室內、室外',
      '• 可同時選擇多個分類進行複選篩選',
      '• 點擊已選取的分類可取消選取',
    ],
  ),
  _SectionData(
    icon: Icons.my_location,
    title: '3. 定位功能',
    content: [
      '• 點擊定位按鈕（🎯）取得目前位置',
      '• 首次使用需授予定位權限',
      '• 定位成功後地圖會自動移至您的位置',
      '• 系統會自動計算並顯示最近的避難所',
    ],
  ),
  _SectionData(
    icon: Icons.location_on,
    title: '4. 地圖標記',
    content: [
      '• 紅色標記：目前選中的避難所',
      '• 綠色標記：座標精確的避難所',
      '• 黃色標記：座標為概略值的避難所',
      '• 點擊標記可查看避難所詳細資訊',
      '• 縮小時相近的避難所會合併成數量圓圈，點擊可放大查看',
    ],
  ),
  _SectionData(
    icon: Icons.info,
    title: '5. 避難所詳情',
    content: [
      '• 點擊避難所標記或列表項目查看詳情',
      '• 顯示名稱、地址、距離資訊',
      '• 顯示適用的災害類型標籤',
      '• 顯示室內／室外空間類型',
      '• 可一鍵開始導航',
    ],
  ),
  _SectionData(
    icon: Icons.navigation,
    title: '6. 導航功能',
    content: [
      '• 點擊「開始導航」按鈕',
      '• 系統會開啟 Google 地圖網頁或應用程式',
      '• 未開啟定位也可搜尋避難所位置',
      '• 已定位時會預設以步行路線導航',
      '• 可在 Google 地圖內切換其他交通方式',
    ],
  ),
  _SectionData(
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
  _SectionData(
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
  _SectionData(
    icon: Icons.warning_amber,
    title: '9. 注意事項',
    content: [
      '• 確保裝置已開啟定位服務',
      '• 需要網路連線才能使用地圖和搜尋功能',
      '• 導航需要網路連線並會離開本系統',
      '• 避難所資訊僅供參考，實際以當地政府公告為準',
      '• 災害發生時請遵循當地政府指示',
    ],
  ),
];

class UserManualPage extends StatelessWidget {
  const UserManualPage({super.key});

  Future<void> _openIssues(BuildContext context) async {
    final launched = await launchUrl(
      _issuesUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟 GitHub Issues')));
    }
  }

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
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= MapConstants.desktopBreakpoint;

    if (!isDesktop) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in _sections) ...[
            _buildSection(context, section),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 16),
          _buildHelpCard(context),
        ],
      );
    }

    // Desktop: the 9 sections used to run down a single centered column,
    // most of a wide window sitting empty on either side of it. A two-up
    // `Wrap` uses that width instead — `LayoutBuilder` sizes each card off
    // the actually-available width rather than a hardcoded column width, so
    // it keeps working across the whole desktop range, not just one size.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 16.0;
              final cardWidth = (constraints.maxWidth - spacing) / 2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final section in _sections)
                        SizedBox(
                          width: cardWidth,
                          child: _buildSection(context, section),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildHelpCard(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHelpCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary, width: 1),
      ),
      child: Column(
        children: [
          Icon(Icons.help_outline, color: colorScheme.primary, size: 40),
          const SizedBox(height: 8),
          Text(
            '需要協助？',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '如有任何問題或建議，歡迎透過 GitHub Issues 告訴我們。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openIssues(context),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('前往 GitHub Issues'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, _SectionData section) {
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
        mainAxisSize: MainAxisSize.min,
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
                Icon(section.icon, color: colorScheme.onPrimary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.title,
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
              mainAxisSize: MainAxisSize.min,
              children: section.content
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: colorScheme.onSurface,
                        ),
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
