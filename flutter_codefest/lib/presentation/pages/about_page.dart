import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static final Uri _githubUri = Uri.parse(
    'https://github.com/Twcat0503/2025Taipei-codefest-team30',
  );

  static final Map<String, Uri> _memberLinks = {
    '伊藤蒼太': Uri.parse('https://itousouta.me'),
  };

  Future<void> _openUrl(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟連結')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '關於我們',
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAuthorSection(context),
                  const SizedBox(height: 16),
                  _buildGithubLink(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_2_outlined, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                '製作團隊',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '2025 臺北程式設計節城市通微服務大黑客松 · 團隊 30',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            '原始成員',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          _buildMemberNames(context, ['台貓', '南宮柳信', '伊藤蒼太', 'Z', 'q_nnn412']),
          const SizedBox(height: 12),
          Text(
            '後續維護',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          _buildMemberNames(context, ['伊藤蒼太', '台貓']),
        ],
      ),
    );
  }

  Widget _buildMemberNames(BuildContext context, List<String> names) {
    final colorScheme = Theme.of(context).colorScheme;
    final plainStyle = TextStyle(
      fontSize: 14,
      color: colorScheme.onSurfaceVariant,
    );
    final linkStyle = plainStyle.copyWith(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: colorScheme.primary,
    );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < names.length; i++) ...[
          if (i > 0) Text(' · ', style: plainStyle),
          Builder(
            builder: (context) {
              final link = _memberLinks[names[i]];
              if (link == null) return Text(names[i], style: plainStyle);
              return InkWell(
                onTap: () => _openUrl(context, link),
                child: Text(names[i], style: linkStyle),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildGithubLink(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openUrl(context, _githubUri),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.code, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '原始碼 (GitHub)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
