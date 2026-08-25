{{flutter_js}}
{{flutter_build_config}}

const loading = document.getElementById("app-loading");
const status = loading?.querySelector(".app-loading__status");

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    if (status) status.textContent = "正在初始化地圖引擎…";
    const appRunner = await engineInitializer.initializeEngine();
    if (status) status.textContent = "正在開啟應用程式…";
    await appRunner.runApp();
    loading?.remove();
  },
});
