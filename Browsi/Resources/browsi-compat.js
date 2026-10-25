// Browsi: fills in Chrome-only extension APIs that WebKit doesn't provide, so Chrome extensions'
// background scripts don't crash on startup. Loaded before the extension's own background script.
// WebKit's API objects hide unknown members, so `chrome`/`browser` are replaced by proxies that add
// fallbacks and otherwise forward to the real API (functions stay bound to the real objects).
(() => {
  const real = globalThis.chrome || globalThis.browser;
  if (!real || real.__browsiCompat) return;

  const event = () => {
    const listeners = new Set();
    return {
      addListener: (f) => listeners.add(f), removeListener: (f) => listeners.delete(f),
      hasListener: (f) => listeners.has(f), hasListeners: () => listeners.size > 0,
    };
  };
  const enumOf = (...names) => Object.freeze(Object.fromEntries(names.map((n) => [n.toUpperCase().replace(/[^A-Z0-9]+/g, '_'), n])));
  // Only resource types WebKit accepts.
  const resourceTypes = enumOf('main_frame', 'sub_frame', 'stylesheet', 'script', 'image', 'font', 'object',
    'xmlhttprequest', 'ping', 'csp_report', 'media', 'websocket', 'other');
  const lazy = (f) => ({ lazy: f });

  const fallbacks = {
    runtime: {
      onUpdateAvailable: lazy(event), onRestartRequired: lazy(event), onBrowserUpdateAvailable: lazy(event),
      onSuspend: lazy(event), onSuspendCanceled: lazy(event), onUserScriptMessage: lazy(event),
      PlatformOs: enumOf('mac', 'win', 'android', 'cros', 'linux', 'openbsd', 'fuchsia'),
      PlatformArch: enumOf('arm', 'arm64', 'x86-32', 'x86-64', 'mips', 'mips64'),
      OnInstalledReason: enumOf('install', 'update', 'chrome_update', 'shared_module_update'),
      ContextType: enumOf('TAB', 'POPUP', 'BACKGROUND', 'OFFSCREEN_DOCUMENT', 'SIDE_PANEL'),
      requestUpdateCheck: (cb) => { if (cb) cb('no_update', {}); return Promise.resolve({ status: 'no_update' }); },
      getContexts: async () => [],
      restart: () => {},
    },
    webRequest: {
      ResourceType: resourceTypes,
      OnBeforeRequestOptions: enumOf('blocking', 'requestBody', 'extraHeaders'),
      OnBeforeSendHeadersOptions: enumOf('requestHeaders', 'blocking', 'extraHeaders'),
      OnHeadersReceivedOptions: enumOf('blocking', 'responseHeaders', 'extraHeaders'),
      MAX_HANDLER_BEHAVIOR_CHANGED_CALLS_PER_10_MINUTES: 20,
      handlerBehaviorChanged: (cb) => { if (cb) cb(); return Promise.resolve(); },
    },
    declarativeNetRequest: {
      ResourceType: resourceTypes,
      RuleActionType: enumOf('block', 'redirect', 'allow', 'upgradeScheme', 'modifyHeaders', 'allowAllRequests'),
      DomainType: enumOf('firstParty', 'thirdParty'),
      onRuleMatchedDebug: lazy(event),
      MAX_NUMBER_OF_REGEX_RULES: 1000, MAX_NUMBER_OF_DYNAMIC_RULES: 30000, MAX_NUMBER_OF_SESSION_RULES: 5000,
      MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES: 5000, MAX_NUMBER_OF_UNSAFE_SESSION_RULES: 5000,
      GUARANTEED_MINIMUM_STATIC_RULES: 30000, MAX_NUMBER_OF_ENABLED_STATIC_RULESETS: 50, MAX_NUMBER_OF_STATIC_RULESETS: 100,
      setExtensionActionOptions: async () => {}, isRegexSupported: async () => ({ isSupported: true }),
      getAvailableStaticRuleCount: async () => 30000,
    },
    webNavigation: {
      onCreatedNavigationTarget: lazy(event), onHistoryStateUpdated: lazy(event), onReferenceFragmentUpdated: lazy(event),
      onTabReplaced: lazy(event), onBeforeNavigate: lazy(event), onCommitted: lazy(event),
      onDOMContentLoaded: lazy(event), onCompleted: lazy(event), onErrorOccurred: lazy(event),
    },
    tabs: { TAB_ID_NONE: -1, onHighlighted: lazy(event), onReplaced: lazy(event), onZoomChange: lazy(event) },
    management: {
      getSelf: async () => ({ installType: 'normal', enabled: true, id: real.runtime && real.runtime.id }),
      onEnabled: lazy(event), onDisabled: lazy(event), onInstalled: lazy(event), onUninstalled: lazy(event),
    },
    idle: { onStateChanged: lazy(event), queryState: async () => 'active', setDetectionInterval: () => {} },
    offscreen: { hasDocument: async () => false, createDocument: async () => {}, closeDocument: async () => {},
                 Reason: enumOf('DOM_PARSER', 'BLOBS', 'CLIPBOARD', 'WORKERS', 'LOCAL_STORAGE') },
    sidePanel: { setPanelBehavior: async () => {}, setOptions: async () => {}, open: async () => {} },
    downloads: { onCreated: lazy(event), onChanged: lazy(event) },
    privacy: {}, contentSettings: {}, identity: {},
  };

  const cache = new Map();
  const resolve = (table, key) => {
    let v = table[key];
    if (v && v.lazy) table[key] = v = v.lazy();
    return v;
  };

  // WebKit rejects match patterns with schemes it doesn't support (ws://, wss://, ftp://…).
  const supportedPattern = (p) => p === '<all_urls>' || /^(\*|https?|file):\/\//.test(p);
  const sanitizedEvent = (key, ev) => {
    if (cache.has(key)) return cache.get(key);
    const wrapped = new Proxy(ev, {
      get(t, k) {
        if (k === 'addListener') {
          return (cb, filter, ...rest) => {
            if (filter && Array.isArray(filter.urls)) {
              const urls = filter.urls.filter(supportedPattern);
              filter = { ...filter, urls: urls.length ? urls : ['<all_urls>'] };
            }
            return t.addListener(cb, filter, ...rest);
          };
        }
        const v = Reflect.get(t, k);
        return typeof v === 'function' ? v.bind(t) : v;
      },
    });
    cache.set(key, wrapped);
    return wrapped;
  };

  const wrapNamespace = (name, target) => {
    const table = fallbacks[name] || {};
    const key = 'ns:' + name;
    if (cache.has(key)) return cache.get(key);
    const proxy = new Proxy(target || {}, {
      get(t, k) {
        let v;
        try { v = target ? Reflect.get(t, k) : undefined; } catch (e) { v = undefined; }
        if (v === undefined && k in table) return resolve(table, k);
        if (name === 'webRequest' && v && typeof v === 'object' && typeof v.addListener === 'function')
          return sanitizedEvent(name + '.' + String(k), v);
        return typeof v === 'function' ? v.bind(t) : v;
      },
      has(t, k) { return k in table || (target ? Reflect.has(t, k) : false); },
    });
    cache.set(key, proxy);
    return proxy;
  };

  const top = new Proxy(real, {
    get(t, k) {
      if (k === '__browsiCompat') return true;
      let v;
      try { v = Reflect.get(t, k); } catch (e) { v = undefined; }
      if (typeof k === 'string' && (k in fallbacks) && (v === undefined || (v && typeof v === 'object')))
        return wrapNamespace(k, v);
      return typeof v === 'function' ? v.bind(t) : v;
    },
    has(t, k) { return k in fallbacks || Reflect.has(t, k); },
  });

  for (const name of ['chrome', 'browser']) {
    try { Object.defineProperty(globalThis, name, { value: top, configurable: true, writable: true }); } catch (e) {}
  }
})();
