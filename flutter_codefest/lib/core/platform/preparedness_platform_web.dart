import 'dart:js_interop';

@JS('tesiis.readLibrary')
external JSPromise<JSString?> _read();
@JS('tesiis.writeLibrary')
external JSPromise<JSAny?> _write(JSString value);
@JS('navigator.onLine')
external JSBoolean get _online;
@JS('tesiis.share')
external JSPromise<JSBoolean> _share(JSString title, JSString text);
@JS('tesiis.printCard')
external void _print(JSString html);
@JS('tesiis.download')
external void _download(JSString name, JSString text, JSString mime);
@JS('tesiis.prepareOffline')
external JSPromise<JSAny?> _prepare();
@JS('tesiis.offlineReady')
external JSPromise<JSBoolean> _ready();

Future<String?> readLibrary() async => (await _read().toDart)?.toDart;
Future<void> writeLibrary(String value) async {
  await _write(value.toJS).toDart;
}

bool get networkAvailable => _online.toDart;
bool get canPrint => true;
Future<bool> shareText(String title, String text) async =>
    (await _share(title.toJS, text.toJS).toDart).toDart;
void printCard(String html) => _print(html.toJS);
void downloadText(String name, String text, String mime) =>
    _download(name.toJS, text.toJS, mime.toJS);
Future<void> prepareOfflineApp() async {
  await _prepare().toDart;
}

Future<bool> offlineAppReady() async => (await _ready().toDart).toDart;
