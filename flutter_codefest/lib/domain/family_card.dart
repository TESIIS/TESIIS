import 'dart:convert';
import 'package:flutter_codefest/data/models/preparedness.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/domain/shelter_links.dart';
import 'package:qr_flutter/qr_flutter.dart';

String familyPlanText(FamilyPlan plan) => [
  plan.title,
  if (plan.primary != null) '主要集合點：${shelterShareText(plan.primary!)}',
  if (plan.backup != null) '備用集合點：${shelterShareText(plan.backup!)}',
  if (plan.contact.isNotEmpty) '緊急聯絡：${plan.contact}',
  if (plan.notes.isNotEmpty) '約定：${plan.notes}',
  '準備清單：',
  for (final item in FamilyPlan.checklist)
    '${plan.checked.contains(item) ? '☑' : '☐'} $item',
  if (plan.updatedAt != null)
    '計畫更新：${plan.updatedAt!.toLocal().toIso8601String().substring(0, 16)}',
].join('\n\n');

String _qrSvg(String data) {
  final validation = QrValidator.validate(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
  );
  final image = QrImage(validation.qrCode!);
  final size = image.moduleCount + 8;
  final cells = StringBuffer();
  for (var y = 0; y < image.moduleCount; y++) {
    for (var x = 0; x < image.moduleCount; x++) {
      if (image.isDark(y, x)) {
        cells.write('<rect x="${x + 4}" y="${y + 4}" width="1" height="1"/>');
      }
    }
  }
  return '<svg aria-label="避難所連結 QR Code" width="160" height="160" viewBox="0 0 $size $size" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg"><rect width="$size" height="$size" fill="white"/><g fill="black">$cells</g></svg>';
}

/// Standalone, printable card. Every user/source string is escaped; all QR
/// graphics are inline, so opening the exported file requires no network.
String familyPlanHtml(FamilyPlan plan) {
  const escape = HtmlEscape();
  String e(String value) => escape.convert(value);
  String point(String label, Shelter? s) => s == null
      ? '<section><h2>$label</h2><p>尚未設定</p></section>'
      : '''
<section><h2>$label</h2><h3>${e(s.name)}</h3><p>${e(s.city)} ${e(s.district)}<br>${e(s.address)}</p>
<p>電話：${e(s.managerPhone.isEmpty ? s.contactPhone : s.managerPhone)}</p>
${_qrSvg(shelterLink(s).toString())}<p><a href="${e(shelterLink(s).toString())}">開啟避難所詳情</a></p></section>''';
  return '''<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${e(plan.title)}</title>
<style>body{font:18px/1.7 system-ui,sans-serif;color:#173e43;max-width:850px;margin:30px auto;padding:20px}h1{border-bottom:3px solid #006874}main{display:flex;gap:20px;flex-wrap:wrap}section{flex:1;min-width:250px;border:1px solid #a7c7c9;border-radius:12px;padding:20px;break-inside:avoid}p{white-space:pre-wrap;overflow-wrap:anywhere}a{color:#006874}footer{font-size:13px;color:#555}@media print{body{margin:0;padding:0}button{display:none}}</style></head><body>
<button onclick="window.print()">列印／另存 PDF</button><h1>${e(plan.title)}</h1><main>${point('主要集合點', plan.primary)}${point('備用集合點', plan.backup)}</main>
<h2>緊急聯絡</h2><p>${e(plan.contact.isEmpty ? '尚未填寫' : plan.contact)}</p><h2>家人約定</h2><p>${e(plan.notes)}</p><h2>準備清單</h2>
${FamilyPlan.checklist.map((item) => '<p>${plan.checked.contains(item) ? '☑' : '☐'} ${e(item)}</p>').join()}
<footer>TESIIS 家庭避難卡 · ${e(plan.updatedAt?.toLocal().toIso8601String().substring(0, 16) ?? '')}<br>地點資料來源：內政部消防署避難收容處所點位檔。集合點是家庭約定；開設情形依當地公告。</footer></body></html>''';
}
