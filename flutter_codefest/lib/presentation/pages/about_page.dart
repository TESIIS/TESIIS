import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class _Member {
  const _Member({
    required this.name,
    required this.roles,
    this.link,
    this.avatarUrl,
  });

  final String name;
  final List<String> roles;
  final Uri? link;
  final String? avatarUrl; // 頭像圖片網址,留空則顯示姓名字首
}

final _members = [
  _Member(
    name: '伊藤蒼太',
    roles: const ['原始成員', '後續維護'],
    link: Uri.parse('https://itousouta.me'),
    avatarUrl: 'https://avatars.githubusercontent.com/u/193865350?v=4',
  ),
  _Member(
    name: '台貓',
    roles: const ['原始成員', '後續維護'],
    link: Uri.parse('https://twcat0503.org'),
    avatarUrl: 'https://avatars.githubusercontent.com/u/130988476?v=4',
  ),
  _Member(
    name: '南宮柳信',
    roles: const ['原始成員'],
    link: Uri.parse('https://github.com/nangong5421'),
    avatarUrl: 'https://avatars.githubusercontent.com/u/208151118?v=4',
  ),
  _Member(
    name: 'Z',
    roles: const ['原始成員'],
    link: Uri.parse('https://github.com/yuzen9622'),
    avatarUrl: 'https://avatars.githubusercontent.com/u/125567280?v=4',
  ),
  _Member(
    name: 'q_nnn412',
    roles: const ['原始成員'],
    link: Uri.parse('https://github.com/NiaN0412'),
  ),
];

final _githubUri = Uri.parse('https://github.com/TESIIS/TESIIS');

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

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
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildMemberCard(context),
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

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(
            Icons.shield_outlined,
            size: 34,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '2025 臺北程式設計節城市通微服務大黑客松',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '團隊 30「喵主餓餓女裝」',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildMemberCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
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
          ),
          for (final member in _members) ...[
            Divider(height: 1, color: colorScheme.outlineVariant),
            _buildMemberTile(context, member),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, _Member member) {
    final colorScheme = Theme.of(context).colorScheme;
    final link = member.link;

    return InkWell(
      onTap: link == null ? null : () => _openUrl(context, link),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.secondaryContainer,
              backgroundImage: member.avatarUrl == null
                  ? null
                  : NetworkImage(member.avatarUrl!),
              child: member.avatarUrl != null
                  ? null
                  : Text(
                      member.name.characters.first,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: link == null
                          ? colorScheme.onSurface
                          : colorScheme.primary,
                      decoration: link == null
                          ? TextDecoration.none
                          : TextDecoration.underline,
                      decorationColor: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final role in member.roles)
                        _buildRoleChip(context, role),
                    ],
                  ),
                ],
              ),
            ),
            if (link != null)
              Icon(
                Icons.open_in_new,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(BuildContext context, String role) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMaintainer = role == '後續維護';
    final background = isMaintainer
        ? colorScheme.primary.withValues(alpha: 0.12)
        : colorScheme.surfaceContainerHighest;
    final foreground = isMaintainer
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
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
