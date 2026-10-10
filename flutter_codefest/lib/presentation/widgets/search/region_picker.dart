import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/repositories/shelter_gateway.dart';

typedef RegionChoice = ({String? city, String? township, bool vulnerable});

Future<RegionChoice?> pickRegion(
  BuildContext context,
  ShelterGateway gateway, {
  String? city,
  String? township,
  bool vulnerable = false,
  bool forDownload = false,
  bool forAlerts = false,
}) => showDialog<RegionChoice>(
  context: context,
  builder: (context) => _RegionPicker(
    gateway: gateway,
    city: city,
    township: township,
    vulnerable: vulnerable,
    forDownload: forDownload,
    forAlerts: forAlerts,
  ),
);

class _RegionPicker extends StatefulWidget {
  const _RegionPicker({
    required this.gateway,
    this.city,
    this.township,
    required this.vulnerable,
    required this.forDownload,
    required this.forAlerts,
  });
  final ShelterGateway gateway;
  final String? city;
  final String? township;
  final bool vulnerable;
  final bool forDownload;
  final bool forAlerts;
  @override
  State<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<_RegionPicker> {
  late String? _city = widget.city;
  late String? _township = widget.township;
  late bool _vulnerable = widget.vulnerable;
  List<String> _cities = [];
  List<String> _townships = [];
  bool _loading = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_request;
    final cities = await widget.gateway.regions();
    final towns = _city == null
        ? <String>[]
        : await widget.gateway.regions(city: _city);
    if (!mounted || id != _request) return;
    setState(() {
      _cities = cities;
      _townships = towns;
      if (!_cities.contains(_city)) _city = null;
      if (!_townships.contains(_township)) _township = null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.forAlerts
          ? '選擇警報區域'
          : widget.forDownload
          ? '下載生活圈資料'
          : '行政區與需求',
    ),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              key: ValueKey('city-$_city-${_cities.length}'),
              initialValue: _city ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: '縣市'),
              items: [
                const DropdownMenuItem(value: '', child: Text('選擇縣市')),
                for (final city in _cities)
                  DropdownMenuItem(value: city, child: Text(city)),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _city = value == '' ? null : value;
                        _township = null;
                        _townships = [];
                        _loading = true;
                      });
                      _load();
                    },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('town-$_city-$_township-${_townships.length}'),
              initialValue: _township ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: '鄉鎮市區'),
              items: [
                const DropdownMenuItem(value: '', child: Text('全縣市')),
                for (final town in _townships)
                  DropdownMenuItem(value: town, child: Text(town)),
              ],
              onChanged: _loading || _city == null
                  ? null
                  : (value) =>
                        setState(() => _township = value == '' ? null : value),
            ),
            const SizedBox(height: 16),
            if (!widget.forDownload && !widget.forAlerts)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('適合避難弱者安置'),
                subtitle: const Text('依來源標示篩選，未提供資料的地點不納入。'),
                value: _vulnerable,
                onChanged: (value) => setState(() => _vulnerable = value!),
              ),
            Text(
              widget.forAlerts
                  ? '依官方公告的行政區資訊比對；僅標示縣市的公告會另外註明範圍較廣。'
                  : widget.forDownload
                  ? '下載所選區域全部避難所，之後可在裝置上搜尋與篩選。資料包不包含底圖與即時交通。'
                  : '查詢會同時套用目前的災害與空間條件。',
            ),
            if (_cities.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('無法載入區域。離線時僅提供已下載的區域。'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      if (!widget.forDownload)
        TextButton(
          onPressed: () => Navigator.pop(context, (
            city: null,
            township: null,
            vulnerable: false,
          )),
          child: const Text('清除區域'),
        ),
      FilledButton(
        onPressed: _loading || (widget.forDownload && _city == null)
            ? null
            : () => Navigator.pop(context, (
                city: _city,
                township: _township,
                vulnerable: _vulnerable,
              )),
        child: Text(widget.forDownload ? '下載' : '套用'),
      ),
    ],
  );
}
