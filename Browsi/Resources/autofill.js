(() => {
  if (window.__browsiAutofill) return;
  window.__browsiAutofill = true;
  const bridge = window.webkit?.messageHandlers?.browsiPasswords;
  if (!bridge) return;
  const send = (msg) => bridge.postMessage(msg);

  const visible = (el) => !!(el && el.offsetParent !== null && !el.disabled && el.type !== "hidden");
  const usernameFor = (pw) => {
    const scope = pw.form || document;
    const inputs = [...scope.querySelectorAll("input")].filter(visible);
    const idx = inputs.indexOf(pw);
    for (let i = idx - 1; i >= 0; i--) {
      const t = (inputs[i].type || "text").toLowerCase();
      if (["text", "email", "tel"].includes(t) || inputs[i].autocomplete === "username") return inputs[i];
    }
    return scope.querySelector('input[autocomplete="username"], input[type="email"]');
  };
  const setValue = (el, v) => {
    if (!el) return;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(el, v);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  };

  // ---------- capture on submit ----------
  let lastSent = "";
  const capture = (pw) => {
    if (!pw || !pw.value) return;
    const user = usernameFor(pw);
    const key = (user?.value || "") + "\u0000" + pw.value;
    if (key === lastSent) return;
    lastSent = key;
    send({ type: "submit", username: user?.value || "", password: pw.value });
  };
  const passwordIn = (root) => [...(root || document).querySelectorAll('input[type="password"]')].find((p) => p.value);
  document.addEventListener("submit", (e) => capture(passwordIn(e.target)), true);
  document.addEventListener("click", (e) => {
    const btn = e.target.closest?.('button, input[type="submit"], [role="button"]');
    if (btn) capture(passwordIn(btn.form || btn.closest("form") || document));
  }, true);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && e.target?.type === "password") capture(e.target);
  }, true);

  // ---------- autofill dropdown ----------
  let host, panel;
  const hide = () => { if (host) host.style.display = "none"; };
  const ensurePanel = () => {
    if (host) return;
    host = document.createElement("div");
    host.style.cssText = "position:absolute;z-index:2147483647;display:none;";
    const shadow = host.attachShadow({ mode: "closed" });
    shadow.innerHTML = `<style>
      .p{font:13px -apple-system,system-ui;min-width:220px;padding:6px;border-radius:12px;
         background:rgba(250,250,252,.72);backdrop-filter:blur(24px) saturate(180%);-webkit-backdrop-filter:blur(24px) saturate(180%);
         border:1px solid rgba(255,255,255,.6);box-shadow:0 12px 32px rgba(0,0,0,.18);color:#111;
         animation:pop .22s cubic-bezier(.2,.9,.3,1.3)}
      @media (prefers-color-scheme: dark){.p{background:rgba(40,40,46,.72);color:#eee;border-color:rgba(255,255,255,.12)}}
      @keyframes pop{from{opacity:0;transform:translateY(-4px) scale(.96)}to{opacity:1;transform:none}}
      .h{font-size:11px;opacity:.6;padding:4px 8px}
      .i{display:flex;gap:8px;align-items:center;padding:7px 8px;border-radius:8px;cursor:default}
      .i:hover{background:rgba(127,127,255,.18)}
      .k{width:18px;height:18px;border-radius:5px;background:linear-gradient(135deg,#8a7bff,#4fb3ff);display:grid;place-items:center;color:#fff;font-size:11px}
    </style><div class="p"><div class="h">🔑 Saved in Keychain</div><div class="l"></div></div>`;
    panel = shadow.querySelector(".l");
    document.documentElement.appendChild(host);
    document.addEventListener("mousedown", (e) => { if (e.target !== host) hide(); }, true);
  };

  const show = async (field) => {
    let names;
    try { names = await bridge.postMessage({ type: "accounts" }); } catch { return; }
    if (!names || !names.length) return;
    ensurePanel();
    const pw = field.type === "password" ? field : field.form?.querySelector('input[type="password"]') || document.querySelector('input[type="password"]');
    const user = pw ? usernameFor(pw) : field;
    panel.innerHTML = "";
    for (const name of names) {
      const row = document.createElement("div");
      row.className = "i";
      row.innerHTML = `<span class="k">●</span><span></span>`;
      row.lastChild.textContent = name || "(no username)";
      row.addEventListener("mousedown", async (e) => {
        e.preventDefault(); e.stopPropagation();
        hide();
        let secret;
        try { secret = await bridge.postMessage({ type: "fill", username: name }); } catch { return; }
        if (secret == null) return;
        setValue(user, name);
        setValue(pw, secret);
        lastSent = name + "\u0000" + secret;
      });
      panel.appendChild(row);
    }
    const r = field.getBoundingClientRect();
    host.style.left = `${r.left + scrollX}px`;
    host.style.top = `${r.bottom + scrollY + 4}px`;
    host.style.display = "block";
  };

  document.addEventListener("focusin", (e) => {
    const el = e.target;
    if (!(el instanceof HTMLInputElement)) return;
    if (el.type === "password" || (el.form && el.form.querySelector('input[type="password"]') && usernameFor(el.form.querySelector('input[type="password"]')) === el)) {
      show(el);
    }
  }, true);
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") hide(); }, true);
})();
