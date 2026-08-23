import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/models/shelter.dart';

/// Tells the user how much to trust the position shown for [shelter].
///
/// Every shelter in the nationwide dataset currently reports an exact
/// position: the NFA point file carries its own WGS84 columns, and a row
/// whose point falls outside its county's bounds is rejected rather than
/// shown. So in practice this widget stays quiet — it is a guard against the
/// data changing, not a caption on a known gap.
///
/// The approximate and missing cases are kept because they were real under
/// the retired Taipei pipeline, where every point came from joining 門牌地址
/// against a separate dataset: about 8% never matched, and the matches that
/// did were interpolated street positions off by 40–761 m. If a future source
/// reintroduces either, saying so is more honest than a map that looks
/// uniformly precise — which is exactly what someone needs to know before
/// walking somewhere during an emergency.
class CoordinateNotice extends StatelessWidget {
  const CoordinateNotice({super.key, required this.shelter});

  final Shelter shelter;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (String message, IconData icon) = switch (shelter) {
      _ when !shelter.hasCoordinate => (
        '此設施尚無精確座標,地圖上不會顯示標記。可用上方按鈕以地址開啟外部地圖。',
        Icons.location_off_outlined,
      ),
      _ when !shelter.isCoordinateExact => (
        '此位置為概略值(依鄰近門牌推估),實際入口可能相差數百公尺。',
        Icons.help_outline,
      ),
      _ => ('', Icons.check),
    };
    if (message.isEmpty) return const SizedBox.shrink();

    final color = colorScheme.tertiary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
