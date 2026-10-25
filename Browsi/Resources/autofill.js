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

  // ---------- autofill dropdown (native macOS AutoFill look) ----------
  let host, list, items = [], shownNames = [], sel = 0, anchor = null, allNames = [], icon = "", pwField = null, userField = null;
  const hide = () => { if (host) host.style.display = "none"; anchor = null; };
  const isOpen = () => !!(host && host.style.display !== "none");
  const siteName = () => {
    const meta = document.querySelector('meta[property="og:site_name"], meta[name="application-name"], meta[name="apple-mobile-web-app-title"]');
    const m = meta?.content?.trim();
    if (m && m.length <= 40) return m;
    const parts = location.hostname.replace(/^www\./, "").split(".");
    const label = parts.length > 1 ? parts[parts.length - 2] : parts[0];
    return label ? label[0].toUpperCase() + label.slice(1) : location.hostname;
  };
  const returnGlyph = `<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M16 4v6.5a2 2 0 0 1-2 2H4.5"/><path d="M8 8.5 4 12.5l4 4"/></svg>`;
  const ensurePanel = () => {
    if (host) return;
    host = document.createElement("div");
    host.style.cssText = "position:absolute;z-index:2147483647;display:none;";
    const shadow = host.attachShadow({ mode: "closed" });
    shadow.innerHTML = `<style>
      :host{all:initial}
      .p{box-sizing:border-box;font:13px/1.25 -apple-system,BlinkMacSystemFont,system-ui;-webkit-font-smoothing:antialiased;
         padding:5px;border-radius:14px;color:rgba(0,0,0,.88);
         background:rgba(244,244,246,.78);-webkit-backdrop-filter:blur(30px) saturate(190%);backdrop-filter:blur(30px) saturate(190%);
         box-shadow:0 0 0 .5px rgba(0,0,0,.14),inset 0 0 0 .5px rgba(255,255,255,.55),0 10px 32px rgba(0,0,0,.18),0 2px 6px rgba(0,0,0,.08);
         animation:in .14s ease-out;cursor:default;user-select:none;-webkit-user-select:none}
      @keyframes in{from{opacity:0;transform:translateY(-3px)}to{opacity:1;transform:none}}
      .i{display:flex;align-items:center;gap:12px;padding:7px 10px 7px 9px;border-radius:9px;min-height:38px}
      .i + .i{margin-top:1px}
      .ic{flex:none;width:32px;height:32px;background-size:contain;background-repeat:no-repeat;background-position:center}
      .ic.fb{border-radius:8px;background:linear-gradient(160deg,#3a3a3c,#1c1c1e)}
      .t{flex:1;min-width:0;display:flex;flex-direction:column;gap:1px}
      .u{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .s{font-size:12px;color:rgba(0,0,0,.5);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .r{flex:none;display:none;opacity:.95}
      .i.on{background:#0a64f0;background:color(display-p3 .04 .40 .96);color:#fff}
      .i.on .s{color:rgba(255,255,255,.82)}
      .i.on .r{display:block}
      @media (prefers-color-scheme: dark){
        .p{background:rgba(40,40,44,.74);color:rgba(255,255,255,.92);
           box-shadow:0 0 0 .5px rgba(0,0,0,.6),inset 0 0 0 .5px rgba(255,255,255,.14),0 10px 32px rgba(0,0,0,.45)}
        .s{color:rgba(255,255,255,.55)}
      }
    </style><div class="p" role="listbox" aria-label="Saved passwords"></div>`;
    list = shadow.querySelector(".p");
    document.documentElement.appendChild(host);
    document.addEventListener("mousedown", (e) => { if (e.target !== host) hide(); }, true);
    addEventListener("resize", hide);
  };
  const select = (i) => {
    sel = (i + items.length) % items.length;
    items.forEach((el, j) => { el.classList.toggle("on", j === sel); el.setAttribute("aria-selected", j === sel); });
  };
  const fill = async (name) => {
    hide();
    let secret;
    try { secret = await bridge.postMessage({ type: "fill", username: name }); } catch { return; }
    if (secret == null) return;
    setValue(userField, name);
    setValue(pwField, secret);
    lastSent = name + "\u0000" + secret;
  };
  const render = (names) => {
    list.innerHTML = "";
    const site = siteName();
    shownNames = names;
    items = names.map((name) => {
      const row = document.createElement("div");
      row.className = "i";
      row.setAttribute("role", "option");
      row.innerHTML = `<span class="ic"></span><span class="t"><span class="u"></span><span class="s"></span></span><span class="r">${returnGlyph}</span>`;
      const ic = row.querySelector(".ic");
      if (icon) ic.style.backgroundImage = `url("${icon}")`; else ic.classList.add("fb");
      row.querySelector(".u").textContent = name || "(no user name)";
      row.querySelector(".s").textContent = site;
      row.addEventListener("mouseenter", () => select(items.indexOf(row)));
      row.addEventListener("mousedown", (e) => { e.preventDefault(); e.stopPropagation(); fill(name); });
      list.appendChild(row);
      return row;
    });
    select(0);
  };
  const place = (field) => {
    const r = field.getBoundingClientRect();
    host.style.width = `${Math.min(Math.max(r.width, 260), 440)}px`;
    host.style.display = "block";
    const h = list.offsetHeight;
    const below = r.bottom + 6 + h <= innerHeight || r.top - 6 - h < 0;
    host.style.left = `${Math.max(4, Math.min(r.left, innerWidth - host.offsetWidth - 4)) + scrollX}px`;
    host.style.top = `${(below ? r.bottom + 6 : r.top - 6 - h) + scrollY}px`;
  };
  const filtered = () => {
    if (anchor !== userField || !userField?.value) return allNames;
    const q = userField.value.toLowerCase();
    return allNames.filter((n) => n.toLowerCase().startsWith(q));
  };

  const show = async (field) => {
    let reply;
    try { reply = await bridge.postMessage({ type: "accounts" }); } catch { return; }
    const names = Array.isArray(reply) ? reply : reply?.names;
    if (!names || !names.length || document.activeElement !== field) return;
    allNames = names;
    icon = reply?.icon || "";
    ensurePanel();
    pwField = field.type === "password" ? field : field.form?.querySelector('input[type="password"]') || document.querySelector('input[type="password"]');
    userField = pwField ? usernameFor(pwField) : field;
    anchor = field;
    const shown = filtered();
    if (!shown.length) return hide();
    render(shown);
    place(field);
  };

  document.addEventListener("input", (e) => {
    if (!anchor || e.target !== anchor) return;
    const shown = filtered();
    if (!shown.length) { host.style.display = "none"; return; }
    render(shown);
    place(anchor);
  }, true);
  document.addEventListener("focusout", (e) => { if (e.target === anchor) hide(); }, true);
  document.addEventListener("keydown", (e) => {
    if (!isOpen() || e.target !== anchor) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault(); e.stopImmediatePropagation();
      select(sel + (e.key === "ArrowDown" ? 1 : -1));
    } else if (e.key === "Enter" && items[sel]) {
      e.preventDefault(); e.stopImmediatePropagation();
      fill(shownNames[sel]);
    } else if (e.key === "Escape") {
      e.preventDefault(); hide();
    }
  }, true);

  document.addEventListener("focusin", (e) => {
    const el = e.target;
    if (!(el instanceof HTMLInputElement)) return;
    if (el.type === "password" || (el.form && el.form.querySelector('input[type="password"]') && usernameFor(el.form.querySelector('input[type="password"]')) === el)) {
      show(el);
    }
  }, true);
})();
