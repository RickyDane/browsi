// Smart form fill: offers the user's "My Card" (Contacts) on address and contact forms.
// Runs in the isolated .defaultClient world; native classifies the fields (keywords, then the on-device model).
(() => {
  if (window.__browsiFormFill) return;
  window.__browsiFormFill = true;
  const bridge = window.webkit?.messageHandlers?.browsiFormFill;
  if (!bridge) return;

  const TEXT_TYPES = ["", "text", "email", "tel", "number"];
  const visible = (el) => !!(el && el.offsetParent !== null && !el.disabled && !el.readOnly && el.type !== "hidden");
  const fillable = (el) => {
    if (!visible(el)) return false;
    if (el instanceof HTMLSelectElement || el instanceof HTMLTextAreaElement) return true;
    return el instanceof HTMLInputElement && TEXT_TYPES.includes((el.getAttribute("type") || "").toLowerCase());
  };
  // Words that suggest a field is about a person or an address (en, de, fr, es). Keeps the dropdown off search boxes.
  const HINT = /name|mail|phone|tel|mobil|handy|address|adress|addr|street|stra(ss|ß)e|city|town|ort|stadt|zip|postal|plz|post|country|land|state|region|province|company|firma|organi|vorname|nachname|surname|given|family|prenom|prénom|nom|rue|ville|calle|ciudad|direcci|apellido|billing|shipping|rechnung|liefer/i;
  const AC = /^(?:section-\S+ )?(?:(?:shipping|billing) )?(?:home |work |mobile )?(name|given-name|family-name|email|tel|tel-national|organization|organization-title|street-address|address-line[12]|address-level[12]|postal-code|country|country-name)$/;

  // A label's own words, without the text of controls it wraps (a <select>'s options, say).
  const textOf = (node) => {
    const copy = node.cloneNode(true);
    copy.querySelectorAll("input, select, textarea, button, script, style").forEach((n) => n.remove());
    return copy.textContent || "";
  };
  const labelOf = (el) => {
    const parts = [];
    if (el.labels) for (const l of el.labels) parts.push(textOf(l));
    const by = el.getAttribute("aria-labelledby");
    if (by) for (const id of by.split(/\s+/)) { const n = document.getElementById(id); if (n) parts.push(n.textContent || ""); }
    if (el.getAttribute("aria-label")) parts.push(el.getAttribute("aria-label"));
    if (!parts.join("").trim() && !(el instanceof HTMLSelectElement)) {
      // No real label: use short text right before the field in its wrapper.
      let p = el.parentElement;
      for (let i = 0; i < 3 && p; i++, p = p.parentElement) {
        const t = (p.innerText || "").trim();
        if (t && t.length <= 60) { parts.push(t); break; }
        if (t.length > 60) break;
      }
    }
    return parts.join(" ").replace(/\s+/g, " ").trim().slice(0, 100);
  };
  const looksPersonal = (el) => {
    const ac = (el.getAttribute("autocomplete") || "").toLowerCase().trim();
    if (AC.test(ac)) return true;
    if (["email", "tel"].includes((el.getAttribute("type") || "").toLowerCase())) return true;
    return HINT.test([el.name, el.id, el.placeholder, labelOf(el)].join(" "));
  };
  // The group of fields a fill applies to: the form, or the nearest wrapper holding several fields.
  const scopeOf = (el) => {
    if (el.form) return el.form;
    let p = el.parentElement;
    while (p && p !== document.body) {
      if ([...p.querySelectorAll("input, select, textarea")].filter(fillable).length >= 3) return p;
      p = p.parentElement;
    }
    return document.body;
  };
  const fieldsIn = (scope) => [...scope.querySelectorAll("input, select, textarea")].filter(fillable);
  const isLoginForm = (scope) => !!scope.querySelector('input[type="password"]');
  const eligible = (el) => {
    if (!fillable(el) || el instanceof HTMLSelectElement) return null;
    if (el.value && el.value.length > 1) return null;
    const scope = scopeOf(el);
    if (isLoginForm(scope)) return null;
    const fields = fieldsIn(scope);
    if (fields.length < 2 || !looksPersonal(el)) return null;
    if (fields.filter(looksPersonal).length < 2) return null;
    return { scope, fields };
  };

  // ---------- dropdown (same look as the password AutoFill menu) ----------
  let host, row, anchor = null, target = null, open = false;
  const hide = () => { if (host) host.style.display = "none"; open = false; anchor = null; };
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
      .i{display:flex;align-items:center;gap:12px;padding:7px 10px 7px 9px;border-radius:9px;min-height:38px;
         background:#0a64f0;background:color(display-p3 .04 .40 .96);color:#fff}
      .ic{flex:none;width:32px;height:32px;background-size:contain;background-repeat:no-repeat;background-position:center}
      .ic.fb{border-radius:8px;background:linear-gradient(160deg,#8e8e93,#636366)}
      .t{flex:1;min-width:0;display:flex;flex-direction:column;gap:1px}
      .u{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .s{font-size:12px;color:rgba(255,255,255,.82);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .k{flex:none;font-size:11px;opacity:.8}
      @media (prefers-color-scheme: dark){
        .p{background:rgba(40,40,44,.74);color:rgba(255,255,255,.92);
           box-shadow:0 0 0 .5px rgba(0,0,0,.6),inset 0 0 0 .5px rgba(255,255,255,.14),0 10px 32px rgba(0,0,0,.45)}
      }
    </style><div class="p" role="listbox" aria-label="Contact AutoFill">
      <div class="i" role="option" aria-selected="true"><span class="ic"></span>
        <span class="t"><span class="u"></span><span class="s"></span></span><span class="k">↩</span></div></div>`;
    row = shadow.querySelector(".i");
    row.addEventListener("mousedown", (e) => { e.preventDefault(); e.stopPropagation(); fill(); });
    document.documentElement.appendChild(host);
    document.addEventListener("mousedown", (e) => { if (e.target !== host) hide(); }, true);
    addEventListener("resize", hide);
  };
  const place = (field) => {
    const r = field.getBoundingClientRect();
    host.style.width = `${Math.min(Math.max(r.width, 260), 440)}px`;
    host.style.display = "block";
    const h = host.offsetHeight;
    const below = r.bottom + 6 + h <= innerHeight || r.top - 6 - h < 0;
    host.style.left = `${Math.max(4, Math.min(r.left, innerWidth - host.offsetWidth - 4)) + scrollX}px`;
    host.style.top = `${(below ? r.bottom + 6 : r.top - 6 - h) + scrollY}px`;
  };

  let card = null, cardAt = 0;
  const show = async (el, found) => {
    if (!card || Date.now() - cardAt > 60000) {
      try { card = await bridge.postMessage({ type: "card" }); } catch { card = null; }
      cardAt = Date.now();
    }
    if (!card || document.activeElement !== el) return;
    ensurePanel();
    const ic = row.querySelector(".ic");
    if (card.icon) ic.style.backgroundImage = `url("${card.icon}")`; else ic.classList.add("fb");
    row.querySelector(".u").textContent = card.label || "My Card";
    row.querySelector(".s").textContent = card.detail || "";
    anchor = el; target = found; open = true;
    place(el);
  };

  // ---------- filling ----------
  const describe = (el, i) => ({
    i,
    tag: el.tagName.toLowerCase(),
    type: (el.getAttribute("type") || "").toLowerCase(),
    ac: el.getAttribute("autocomplete") || "",
    name: el.name || "",
    id: el.id || "",
    label: labelOf(el),
    ph: el.placeholder || "",
    opts: el instanceof HTMLSelectElement ? [...el.options].slice(0, 40).map((o) => (o.text || o.value).trim()) : undefined,
  });
  const norm = (s) => (s || "").toString().trim().toLowerCase();
  const nativeSetter = (el) => Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value")?.set;
  const setValue = (el, values) => {
    let v = values[0];
    if (el instanceof HTMLSelectElement) {
      const opts = [...el.options];
      const want = values.map(norm);
      const hit = opts.find((o) => want.includes(norm(o.value)) || want.includes(norm(o.text)))
        || opts.find((o) => want.some((w) => w.length > 3 && norm(o.text).startsWith(w)));
      if (!hit) return false;
      v = hit.value;
    } else if (el.maxLength > 0 && v.length > el.maxLength) {
      return false;
    }
    (nativeSetter(el) || ((x) => { el.value = x; })).call(el, v);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  };
  const tint = (el) => {
    const prev = el.style.backgroundColor;
    el.style.transition = "background-color .3s";
    el.style.backgroundColor = "rgba(250, 236, 150, .55)";
    const clear = () => { el.style.backgroundColor = prev; el.removeEventListener("input", clear, true); };
    el.addEventListener("input", clear, true);
    setTimeout(clear, 2500);
  };

  let filling = false;
  const fill = async () => {
    const found = target, start = anchor;
    hide();
    if (!found) return;
    const fields = found.fields.filter((el) => el === start || !el.value || el instanceof HTMLSelectElement);
    let reply;
    try {
      reply = await bridge.postMessage({ type: "fill", title: document.title, fields: fields.map(describe) });
    } catch { return; }
    if (!reply?.fills?.length) return;
    filling = true;
    for (const f of reply.fills) {
      const el = fields[f.i];
      if (!el || !Array.isArray(f.v) || !f.v.length) continue;
      // Don't overwrite something the user typed meanwhile, or a select they already changed.
      if (el !== start && el.value && !(el instanceof HTMLSelectElement && el.selectedIndex <= 0)) continue;
      if (setValue(el, f.v)) tint(el);
    }
    filling = false;
  };

  document.addEventListener("focusin", (e) => {
    const el = e.target;
    if (filling) return;
    const found = eligible(el);
    if (found) show(el, found); else if (open && el !== anchor) hide();
  }, true);
  document.addEventListener("input", (e) => { if (open && e.target === anchor) hide(); }, true);
  document.addEventListener("focusout", (e) => { if (e.target === anchor) hide(); }, true);
  document.addEventListener("keydown", (e) => {
    if (!open || e.target !== anchor) return;
    if (e.key === "Enter") {
      e.preventDefault(); e.stopImmediatePropagation(); fill();
    } else if (e.key === "Escape") {
      e.preventDefault(); hide();
    }
  }, true);
})();
