// Browser adapters kept outside the Flutter bundle so the same IndexedDB and
// service-worker contracts can also be exercised in real browser tests.
(() => {
  const base = new URL('.', document.baseURI);
  function database() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open('tesiis-preparedness', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('documents');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(new Error('IndexedDB is blocked'));
    });
  }
  async function documentTransaction(mode, value) {
    const db = await database();
    try {
      return await new Promise((resolve, reject) => {
        const transaction = db.transaction('documents', mode);
        const store = transaction.objectStore('documents');
        const request = store.get('library-v1');
        if (mode === 'readwrite') request.onsuccess = () => {
          const previous = JSON.parse(request.result ?? '{}');
          const next = JSON.parse(value);
          // Compare-and-swap inside one IDB transaction. A second open tab
          // cannot overwrite a newer plan with its stale in-memory document.
          if ((next._revision ?? 1) !== (previous._revision ?? 0) + 1) {
            transaction.abort();
            return;
          }
          store.put(value, 'library-v1');
        };
        transaction.oncomplete = () => resolve(mode === 'readonly' ? request.result ?? null : null);
        transaction.onabort = () => reject(transaction.error ?? new Error('Storage aborted'));
        transaction.onerror = () => reject(transaction.error);
      });
    } finally { db.close(); }
  }
  async function registration() {
    if (!('serviceWorker' in navigator)) throw new Error('This browser cannot prepare offline startup');
    // The generated manifest is present only in a production build.
    return navigator.serviceWorker.register(new URL('offline-sw.js', base), {scope: base.pathname, updateViaCache: 'none'});
  }
  function waitInstalled(worker) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { cleanup(); reject(new Error('Offline download timed out')); }, 180000);
      const cleanup = () => { clearTimeout(timeout); worker.removeEventListener('statechange', changed); };
      const changed = () => {
        if (worker.state === 'installed' || worker.state === 'activated') { cleanup(); resolve(); }
        else if (worker.state === 'redundant') { cleanup(); reject(new Error('Offline download failed')); }
      };
      worker.addEventListener('statechange', changed);
      changed();
    });
  }
  function workerMessage(worker, type) {
    return new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      const timer = setTimeout(() => { channel.port1.close(); reject(new Error('Worker did not respond')); }, 10000);
      channel.port1.onmessage = (event) => { clearTimeout(timer); channel.port1.close(); resolve(event.data); };
      worker.postMessage({type}, [channel.port2]);
    });
  }
  window.tesiis = {
    readLibrary: () => documentTransaction('readonly'),
    writeLibrary: (value) => documentTransaction('readwrite', value),
    async share(title, text) {
      if (!navigator.share) return false;
      try { await navigator.share({title, text}); return true; }
      catch (error) { return error.name === 'AbortError'; }
    },
    printCard(html) {
      const popup = window.open('', '_blank');
      if (!popup) throw new Error('請允許列印視窗');
      let printed = false;
      const print = () => { if (!printed) { printed = true; popup.print(); } };
      popup.addEventListener('load', print, {once: true});
      popup.document.open(); popup.document.write(html); popup.document.close();
      // document.close may finish before the listener is installed.
      if (popup.document.readyState === 'complete') print();
    },
    download(name, text, mime) {
      const url = URL.createObjectURL(new Blob([text], {type: mime}));
      const link = document.createElement('a'); link.href = url; link.download = name; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    },
    async prepareOffline() {
      const reg = await registration();
      await reg.update();
      if (reg.installing) await waitInstalled(reg.installing);
      if (reg.waiting) {
        const worker = reg.waiting;
        worker.postMessage({type: 'ACTIVATE'});
        await new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('Activation timed out')), 15000);
          const check = () => { if (worker.state === 'activated') { clearTimeout(timer); worker.removeEventListener('statechange', check); resolve(); } };
          worker.addEventListener('statechange', check); check();
        });
      }
      const active = reg.active ?? (await navigator.serviceWorker.ready).active;
      const status = await workerMessage(active, 'STATUS');
      if (!status.ready) throw new Error('離線啟動資源不完整');
      if (navigator.storage?.persist) await navigator.storage.persist();
    },
    async offlineReady() {
      if (!('serviceWorker' in navigator)) return false;
      const reg = await navigator.serviceWorker.getRegistration(base.href);
      if (!reg?.active || !reg.active.scriptURL.endsWith('/offline-sw.js')) return false;
      try { return (await workerMessage(reg.active, 'STATUS')).ready === true; }
      catch (_) { return false; }
    },
  };
  // Checking an existing installation does not trigger a first-visit download.
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistration(base.href).then((reg) => {
      if (!reg?.active?.scriptURL.endsWith('/offline-sw.js')) return;
      const showUpdate = () => {
        if (!reg.waiting || document.getElementById('tesiis-update')) return;
        const button = document.createElement('button');
        button.id = 'tesiis-update'; button.textContent = '應用程式已更新，點此重新載入';
        button.style.cssText = 'position:fixed;bottom:8px;left:8px;z-index:99999;padding:12px;border:0;border-radius:8px;background:#006874;color:white;cursor:pointer';
        button.onclick = () => {
          navigator.serviceWorker.addEventListener('controllerchange', () => location.reload(), {once: true});
          reg.waiting?.postMessage({type: 'ACTIVATE'});
        };
        document.body.append(button);
      };
      showUpdate();
      reg.addEventListener('updatefound', () => reg.installing?.addEventListener('statechange', showUpdate));
      reg.update().catch(() => {});
    }).catch(() => {});
  }
})();
