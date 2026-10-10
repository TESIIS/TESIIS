import 'package:shared_preferences/shared_preferences.dart';

Future<String?> readLibrary() async =>
    (await SharedPreferences.getInstance()).getString('preparedness_v1');
Future<void> writeLibrary(String value) async {
  if (!await (await SharedPreferences.getInstance()).setString(
    'preparedness_v1',
    value,
  )) {
    throw StateError('無法儲存資料');
  }
}

bool get networkAvailable => true;
bool get canPrint => false;
Future<bool> shareText(String title, String text) async => false;
void printCard(String html) {}
void downloadText(String name, String text, String mime) {}
Future<void> prepareOfflineApp() async {}
Future<bool> offlineAppReady() async => true;
