import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_codefest/core/platform/preparedness_platform.dart'
    as platform;
import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/models/preparedness.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/repositories/preparedness_store.dart';
import 'package:flutter_codefest/data/repositories/shelter_gateway.dart';
import 'package:flutter_codefest/domain/family_card.dart';
import 'package:flutter_codefest/presentation/widgets/search/region_picker.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/share_shelter_sheet.dart';

Future<bool> saveAction(
  BuildContext context,
  Future<void> Function() action, {
  String? message,
}) async {
  try {
    await action();
    if (context.mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作未完成，請確認連線、儲存空間，或重新整理後重試。')),
      );
    }
    return false;
  }
}

Future<void> editFavorite(
  BuildContext context,
  PreparednessStore store,
  Shelter shelter,
) async {
  final saved = store.favorite(shelter.shelterId);
  final group = TextEditingController(text: saved?.group ?? '常用');
  final note = TextEditingController(text: saved?.note ?? '');
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(saved == null ? '收藏避難所' : '編輯收藏'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(shelter.name),
              TextField(
                controller: group,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: '分組',
                  hintText: '住家、公司、父母家',
                ),
              ),
              TextField(
                controller: note,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '私人備註'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('儲存收藏'),
        ),
      ],
    ),
  );
  if (result == true && context.mounted) {
    await saveAction(
      context,
      () => store.saveFavorite(shelter, group: group.text, note: note.text),
      message: '已儲存到這台裝置',
    );
  }
  // Let the dialog's reverse transition finish before disposing controllers.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  group.dispose();
  note.dispose();
}

class PreparednessPage extends StatelessWidget {
  const PreparednessPage({
    super.key,
    required this.store,
    required this.gateway,
  });
  final PreparednessStore store;
  final ShelterGateway gateway;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('我的避難準備'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: '收藏'),
            Tab(text: '家庭計畫'),
            Tab(text: '離線資料'),
            Tab(text: '設定'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Column(
          children: [
            if (store.storageError != null)
              MaterialBanner(
                content: Text(store.storageError!),
                actions: [
                  TextButton(onPressed: store.load, child: const Text('重試')),
                ],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _Favorites(store: store, gateway: gateway),
                  _PlanEditor(store: store),
                  _Downloads(store: store, gateway: gateway),
                  _Settings(store: store),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Favorites extends StatefulWidget {
  const _Favorites({required this.store, required this.gateway});
  final PreparednessStore store;
  final ShelterGateway gateway;
  @override
  State<_Favorites> createState() => _FavoritesState();
}

class _FavoritesState extends State<_Favorites> {
  final Set<String> _compare = {};
  String? _group;
  bool _refreshing = false;
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final success = await saveAction(context, () async {
      if (widget.gateway.localOnly) throw StateError('需要網路才能更新');
      for (final favorite in widget.store.favorites) {
        try {
          final fresh = await widget.gateway.detail(favorite.shelter.shelterId);
          if (widget.gateway.usedOffline) throw StateError('目前使用保存的資料');
          await widget.store.saveFavorite(
            fresh,
            group: favorite.group,
            note: favorite.note,
            status: 'updated',
          );
        } on ApiException catch (e) {
          if (e.statusCode != 404) rethrow;
          await widget.store.saveFavorite(
            favorite.shelter,
            group: favorite.group,
            note: favorite.note,
            status: 'unavailable',
          );
        }
      }
    });
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('收藏資料已更新')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = widget.store.favorites;
    final groups = favorites.map((f) => f.group).toSet();
    final selected = favorites
        .where((f) => _compare.contains(f.shelter.shelterId))
        .map((f) => f.shelter)
        .toList();
    final visible = favorites
        .where((f) => _group == null || f.group == _group)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('收藏、備註與家庭計畫保存在這台裝置。可以分享地點連結，或匯出家庭卡。'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: favorites.isEmpty || _refreshing ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(_refreshing ? '更新中…' : '更新收藏資料'),
            ),
            FilledButton.tonalIcon(
              onPressed: selected.length < 2
                  ? null
                  : () => _showComparison(context, selected),
              icon: const Icon(Icons.compare_arrows),
              label: Text('比較 ${selected.length}/3'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('全部分組'),
              selected: _group == null,
              onSelected: (_) => setState(() => _group = null),
            ),
            for (final group in groups)
              ChoiceChip(
                label: Text(group),
                selected: _group == group,
                onSelected: (_) => setState(() => _group = group),
              ),
          ],
        ),
        if (favorites.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text('還沒有收藏。從地圖開啟避難所，點選「收藏」即可保存。'),
          ),
        for (final f in visible)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(f.shelter.name),
                    subtitle: Text(
                      '${f.group} · ${f.shelter.city}${f.shelter.district}\n${f.shelter.address}',
                    ),
                    isThreeLine: true,
                    onTap: () => Navigator.pop(context, f.shelter),
                    leading: Checkbox(
                      value: _compare.contains(f.shelter.shelterId),
                      onChanged: (value) {
                        if (value == true && selected.length >= 3) return;
                        setState(() {
                          if (value == true) {
                            _compare.add(f.shelter.shelterId);
                          } else {
                            _compare.remove(f.shelter.shelterId);
                          }
                        });
                      },
                    ),
                  ),
                  if (f.note.isNotEmpty) Text(f.note),
                  if (f.status == 'unavailable')
                    const Text('來源已找不到此編號，保留最後保存的摘要。請重新確認地點。'),
                  if (f.status == 'updated') const Text('已更新保存摘要'),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context, f.shelter),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('查看地點'),
                      ),
                      TextButton(
                        onPressed: () =>
                            editFavorite(context, widget.store, f.shelter),
                        child: const Text('編輯'),
                      ),
                      TextButton(
                        onPressed: () => showShelterShare(context, f.shelter),
                        child: const Text('分享'),
                      ),
                      TextButton(
                        onPressed: () => saveAction(
                          context,
                          () =>
                              widget.store.removeFavorite(f.shelter.shelterId),
                          message: '已移除收藏；家庭計畫中的地點仍保留',
                        ),
                        child: const Text('移除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _showComparison(BuildContext context, List<Shelter> shelters) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('避難所比較'),
        content: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('項目')),
                for (final s in shelters)
                  DataColumn(
                    label: SizedBox(
                      width: 150,
                      child: Text(s.name, softWrap: true),
                    ),
                  ),
              ],
              rows: [
                DataRow(
                  cells: [
                    const DataCell(Text('行政區')),
                    for (final s in shelters)
                      DataCell(Text('${s.city}${s.district}')),
                  ],
                ),
                for (final entry in <String, String Function(Shelter)>{
                  '水災': (s) => Shelter.flagLabel(s.flood),
                  '地震': (s) => Shelter.flagLabel(s.earthquake),
                  '土石流': (s) => Shelter.flagLabel(s.landslide),
                  '海嘯': (s) => Shelter.flagLabel(s.tsunami),
                  '核子事故': (s) => Shelter.flagLabel(s.nuclear),
                  '室內': (s) => Shelter.flagLabel(s.indoor),
                  '室外': (s) => Shelter.flagLabel(s.outdoor),
                  '弱者安置標示': (s) =>
                      s.isNfa ? Shelter.flagLabel(s.accessible) : '未提供',
                  '預計收容人數': (s) => s.capacity > 0 ? '${s.capacity} 人' : '未提供',
                }.entries)
                  DataRow(
                    cells: [
                      DataCell(Text(entry.key)),
                      for (final s in shelters) DataCell(Text(entry.value(s))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({required this.store});
  final PreparednessStore store;
  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor>
    with AutomaticKeepAliveClientMixin {
  late final _title = TextEditingController(text: widget.store.plan.title);
  late final _contact = TextEditingController(text: widget.store.plan.contact);
  late final _notes = TextEditingController(text: widget.store.plan.notes);
  late Shelter? _primary = widget.store.plan.primary;
  late Shelter? _backup = widget.store.plan.backup;
  late final _checked = {...widget.store.plan.checked};
  @override
  bool get wantKeepAlive => true;
  @override
  void dispose() {
    _title.dispose();
    _contact.dispose();
    _notes.dispose();
    super.dispose();
  }

  FamilyPlan _current() => FamilyPlan(
    title: _title.text.trim().isEmpty ? '我的家庭避難計畫' : _title.text.trim(),
    primary: _primary,
    backup: _backup,
    contact: _contact.text.trim(),
    notes: _notes.text.trim(),
    checked: {..._checked},
    updatedAt: DateTime.now(),
  );
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final choices = <String, Shelter>{
      for (final f in widget.store.favorites) f.shelter.shelterId: f.shelter,
      if (_primary != null) _primary!.shelterId: _primary!,
      if (_backup != null) _backup!.shelterId: _backup!,
    };
    Widget picker(
      String label,
      Shelter? value,
      Shelter? other,
      void Function(Shelter?) change,
    ) => DropdownButtonFormField<String>(
      key: ValueKey('$label-${value?.shelterId}'),
      initialValue: value?.shelterId ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('尚未設定')),
        for (final s in choices.values)
          if (s.shelterId != other?.shelterId)
            DropdownMenuItem(
              value: s.shelterId,
              child: Text(
                '${s.name}（${s.city}）',
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
      onChanged: (code) => setState(() => change(choices[code])),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '計畫名稱'),
        ),
        const Text('先收藏地點，再設定主要與備用集合點。'),
        const SizedBox(height: 16),
        picker('主要集合點', _primary, _backup, (s) => _primary = s),
        const SizedBox(height: 16),
        picker('備用集合點', _backup, _primary, (s) => _backup = s),
        const SizedBox(height: 16),
        TextField(
          controller: _contact,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(labelText: '緊急聯絡人與電話'),
        ),
        TextField(
          controller: _notes,
          maxLength: 2000,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '家人約定',
            hintText: '集合方式、入口、不同情境的安排',
          ),
        ),
        const SizedBox(height: 12),
        Text('準備清單', style: Theme.of(context).textTheme.titleMedium),
        for (final item in FamilyPlan.checklist)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item),
            value: _checked.contains(item),
            onChanged: (value) => setState(() {
              if (value!) {
                _checked.add(item);
              } else {
                _checked.remove(item);
              }
            }),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => saveAction(
                context,
                () => widget.store.savePlan(_current()),
                message: '家庭計畫已儲存',
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('儲存計畫'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final plan = _current();
                final text = familyPlanText(plan);
                if (!await platform.shareText(plan.title, text)) {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已複製家庭避難計畫')));
                  }
                }
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('分享文字'),
            ),
            if (platform.canPrint)
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    platform.printCard(familyPlanHtml(_current()));
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('請允許開啟列印視窗，或下載避難卡')),
                    );
                  }
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('列印／PDF'),
              ),
            if (platform.canPrint)
              OutlinedButton.icon(
                onPressed: () => platform.downloadText(
                  'TESIIS-family-card.html',
                  familyPlanHtml(_current()),
                  'text/html;charset=utf-8',
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('下載避難卡'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('匯出的卡片含你填寫的聯絡資訊與備註，可在離線時開啟與列印；QR Code 連到個別避難所。'),
      ],
    );
  }
}

class _Downloads extends StatefulWidget {
  const _Downloads({required this.store, required this.gateway});
  final PreparednessStore store;
  final ShelterGateway gateway;
  @override
  State<_Downloads> createState() => _DownloadsState();
}

class _DownloadsState extends State<_Downloads> {
  bool _busy = false;
  bool _shellReady = false;
  String? _progress;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final value = await platform.offlineAppReady();
      if (mounted) setState(() => _shellReady = value);
    } catch (_) {}
  }

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _progress = '正在下載離線啟動資源與字型…';
    });
    await saveAction(context, platform.prepareOfflineApp, message: '離線啟動資源已備妥');
    await _check();
    if (mounted) {
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  Future<void> _download({OfflinePackage? existing}) async {
    final choice = existing == null
        ? await pickRegion(context, widget.gateway, forDownload: true)
        : (city: existing.city, township: existing.township, vulnerable: false);
    if (choice == null || choice.city == null || !mounted) return;
    setState(() {
      _busy = true;
      _progress = '正在下載 ${choice.city}${choice.township ?? ''}…';
    });
    final success = await saveAction(context, () async {
      final package = await widget.gateway.download(
        choice.city!,
        choice.township,
      );
      await widget.store.savePackage(package);
    }, message: '區域資料已完整保存');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });
    if (success && !_shellReady) await _prepare();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text('下載生活圈後，可離線搜尋、篩選與查看詳情。地圖底圖、即時交通與外部導航需要網路；精簡清單可直接使用已下載資料。'),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.download),
            label: const Text('下載區域'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _prepare,
            icon: Icon(_shellReady ? Icons.offline_pin : Icons.install_mobile),
            label: Text(_shellReady ? '檢查離線啟動更新' : '準備離線啟動'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(_shellReady ? '✓ 已備妥離線啟動資源' : '離線啟動尚未就緒；資料包與啟動資源會分別顯示狀態。'),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
        Text(_progress ?? '處理中…'),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('使用離線資料'),
        subtitle: const Text('只查詢已下載區域，可用來確認斷網前的準備。'),
        value: widget.store.offlineMode,
        onChanged: widget.store.packages.isEmpty
            ? null
            : (value) => saveAction(
                context,
                () => widget.store.settings(offlineMode: value),
              ),
      ),
      if (widget.store.packages.isEmpty)
        const Padding(padding: EdgeInsets.all(20), child: Text('還沒有下載區域資料。')),
      for (final package in widget.store.packages)
        Card(
          child: ListTile(
            title: Text(package.label),
            subtitle: Text(
              '${package.shelters.length} 處 · ${(package.bytes / 1024).toStringAsFixed(0)} KB\n下載：${package.downloadedAt.toLocal().toString().substring(0, 16)}\n版本：${package.version}\n來源：消防署${package.freshness == 'live' ? '' : '（備援／暫存資料）'}',
            ),
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: '管理 ${package.label}',
              onSelected: (value) {
                if (value == 'update') {
                  _download(existing: package);
                } else {
                  saveAction(
                    context,
                    () => widget.store.removePackage(package.key),
                    message: '已刪除區域資料包',
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'update', child: Text('更新資料包')),
                const PopupMenuItem(value: 'delete', child: Text('刪除資料包')),
              ],
            ),
          ),
        ),
    ],
  );
}

class _Settings extends StatelessWidget {
  const _Settings({required this.store});
  final PreparednessStore store;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('顯示與操作', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      DropdownButtonFormField<ThemeMode>(
        key: ValueKey(store.themeMode),
        initialValue: store.themeMode,
        decoration: const InputDecoration(labelText: '主題'),
        items: const [
          DropdownMenuItem(value: ThemeMode.light, child: Text('淺色')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
          DropdownMenuItem(value: ThemeMode.system, child: Text('跟隨系統')),
        ],
        onChanged: (mode) =>
            saveAction(context, () => store.settings(theme: mode)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('大字模式'),
        value: store.largeText,
        onChanged: (value) =>
            saveAction(context, () => store.settings(largeText: value)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('精簡清單模式'),
        subtitle: const Text('使用清單查詢，減少地圖與動畫。'),
        value: store.listMode,
        onChanged: (value) =>
            saveAction(context, () => store.settings(listMode: value)),
      ),
    ],
  );
}
