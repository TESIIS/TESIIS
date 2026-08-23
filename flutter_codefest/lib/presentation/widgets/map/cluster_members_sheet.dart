import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/models/shelter.dart';

/// Lists the individual shelters folded into a cluster that's still grouped
/// at the map's maximum zoom — the only way left to open one of them once
/// zooming in further can no longer split the cluster apart.
class ClusterMembersSheet extends StatelessWidget {
  const ClusterMembersSheet({super.key, required this.members});

  final List<Shelter> members;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '這個位置有 ${members.length} 個避難設施',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: members.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final shelter = members[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.location_on,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    title: Text(
                      shelter.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      shelter.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    onTap: () => Navigator.pop(context, shelter),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
