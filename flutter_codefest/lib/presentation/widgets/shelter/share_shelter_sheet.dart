import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_codefest/core/platform/preparedness_platform.dart'
    as platform;
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/domain/shelter_links.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<void> showShelterShare(BuildContext context, Shelter shelter) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final link = shelterLink(shelter).toString();
        return AlertDialog(
          title: const Text('分享避難所'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shelter.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(shelter.address),
                  const SizedBox(height: 16),
                  Semantics(
                    label: '避難所分享連結 QR Code',
                    image: true,
                    child: QrImageView(
                      data: link,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  SelectableText(link),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('關閉'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已複製分享連結')));
                }
              },
              child: const Text('複製連結'),
            ),
            FilledButton(
              onPressed: () async {
                final text = shelterShareText(shelter);
                final shared = await platform.shareText(shelter.name, text);
                if (!shared) {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已複製避難所資訊')));
                  }
                }
              },
              child: const Text('分享資訊'),
            ),
          ],
        );
      },
    );
