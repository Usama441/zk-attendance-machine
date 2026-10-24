// ZK Attendance — UI motion & helpers (GSAP)
(() => {
  const root = document.documentElement;
  const gsap = window.gsap;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const animate = !!gsap && !reduce;

  const ZK = (window.ZK = {});

  // ---------- Count-up numbers ----------
  const fmt = n => Math.round(n).toLocaleString();
  ZK.countTo = (el, value) => {
    if (!el) return;
    const target = Number(value);
    if (!Number.isFinite(target)) { el.textContent = value; return; }
    const from = Number(el.dataset.count ?? String(el.textContent).replace(/[^\d.-]/g, "")) || 0;
    el.dataset.count = target;
    if (!animate) { el.textContent = fmt(target); return; }
    const obj = { v: from };
    gsap.to(obj, { v: target, duration: 1.2, ease: "power3.out", onUpdate: () => (el.textContent = fmt(obj.v)) });
    if (from !== target) gsap.fromTo(el, { color: "#3b5bdb" }, { color: "#0f172a", duration: 1.4, ease: "power2.out", clearProps: "color" });
  };

  // Swap text with a small fade/slide.
  ZK.swapText = (el, text) => {
    if (!el || el.textContent === text) return;
    if (!animate) { el.textContent = text; return; }
    gsap.to(el, {
      y: -6, opacity: 0, duration: .18, ease: "power1.in",
      onComplete: () => { el.textContent = text; gsap.fromTo(el, { y: 6, opacity: 0 }, { y: 0, opacity: 1, duration: .3, ease: "power2.out" }); }
    });
  };

  // ---------- Status lines ----------
  ZK.status = (el, text, kind = "") => {
    if (!el) return;
    el.className = el.className.replace(/\b(ok|err|pending)\b/g, "").trim() + (kind ? " " + kind : "");
    el.textContent = text;
    if (animate && text) gsap.fromTo(el, { opacity: 0, y: 4 }, { opacity: 1, y: 0, duration: .3, ease: "power2.out" });
  };

  // ---------- Buttons ----------
  ZK.loading = (btn, on) => {
    if (!btn) return;
    btn.disabled = on;
    btn.classList.toggle("loading", on);
  };

  document.addEventListener("pointerdown", e => {
    const btn = e.target.closest(".btn");
    if (!btn || !animate || btn.disabled) return;
    const r = btn.getBoundingClientRect();
    const size = Math.max(r.width, r.height) * 2;
    const dot = document.createElement("span");
    dot.className = "ripple";
    Object.assign(dot.style, { width: size + "px", height: size + "px", left: e.clientX - r.left - size / 2 + "px", top: e.clientY - r.top - size / 2 + "px" });
    btn.appendChild(dot);
    gsap.fromTo(dot, { scale: 0, opacity: .5 }, { scale: 1, opacity: 0, duration: .6, ease: "power2.out", onComplete: () => dot.remove() });
  });

  // ---------- Toasts ----------
  const toastIcons = { ok: "i-check", err: "i-alert" };
  const dismiss = t => {
    if (!t || t.dataset.leaving) return;
    t.dataset.leaving = "1";
    if (!animate) return t.remove();
    gsap.to(t, { x: 40, opacity: 0, height: 0, paddingTop: 0, paddingBottom: 0, marginTop: -10, duration: .35, ease: "power2.in", onComplete: () => t.remove() });
  };
  const wireToast = t => {
    t.querySelector(".toast-close")?.addEventListener("click", () => dismiss(t));
    if (animate) gsap.from(t, { x: 60, opacity: 0, duration: .55, ease: "back.out(1.6)", delay: .25 });
    setTimeout(() => dismiss(t), t.classList.contains("err") ? 10000 : 6000);
  };
  ZK.toast = (message, kind = "ok") => {
    const box = document.getElementById("toasts");
    if (!box) return;
    const t = document.createElement("div");
    t.className = "toast " + kind;
    t.setAttribute("role", kind === "err" ? "alert" : "status");
    t.innerHTML = `<svg class="ic"><use href="#${toastIcons[kind] || "i-check"}"/></svg><span></span><button type="button" class="toast-close" aria-label="Dismiss"><svg class="ic"><use href="#i-x"/></svg></button>`;
    t.querySelector("span").textContent = message;
    box.appendChild(t);
    wireToast(t);
  };

  // Reveal a freshly inserted element (e.g. a cloned form row).
  ZK.pop = el => { if (animate && el) gsap.from(el, { opacity: 0, y: -8, scale: .98, duration: .35, ease: "power2.out", clearProps: "all" }); };
  ZK.drop = (el, done) => {
    if (!animate) return done();
    gsap.to(el, { opacity: 0, x: 20, duration: .25, ease: "power1.in", onComplete: done });
  };

  // ---------- Nav indicator ----------
  function initNav() {
    const nav = document.querySelector(".nav");
    const ind = nav?.querySelector(".nav-indicator");
    if (!nav || !ind || !gsap) return;
    const active = nav.querySelector("a.active");
    const place = (a, instant) => {
      if (!a) return gsap.to(ind, { opacity: 0, duration: .2 });
      const props = { x: a.offsetLeft, width: a.offsetWidth, opacity: 1 };
      instant || reduce ? gsap.set(ind, props) : gsap.to(ind, { ...props, duration: .45, ease: "power3.out" });
    };
    place(active, true);
    nav.classList.add("ready");
    nav.querySelectorAll("a").forEach(a => a.addEventListener("mouseenter", () => place(a)));
    nav.addEventListener("mouseleave", () => place(active));
    window.addEventListener("resize", () => place(active, true));
  }

  // ---------- Correct-time popovers ----------
  function initPopovers() {
    const boxes = document.querySelectorAll("details.correct-box");
    boxes.forEach(d => {
      d.addEventListener("toggle", () => {
        if (!d.open) return;
        boxes.forEach(o => o !== d && (o.open = false));
        const panel = d.querySelector(".correct-form");
        if (animate && panel) gsap.fromTo(panel, { opacity: 0, y: -6, scale: .97, transformOrigin: "top right" }, { opacity: 1, y: 0, scale: 1, duration: .28, ease: "power2.out" });
        d.querySelector("input[type=time]")?.focus();
      });
    });
    document.addEventListener("click", e => {
      boxes.forEach(d => { if (d.open && !d.contains(e.target)) d.open = false; });
    });
    document.addEventListener("keydown", e => { if (e.key === "Escape") boxes.forEach(d => (d.open = false)); });
  }

  // ---------- Data tables (markup: app/views/shared/_data_table.html.erb) ----------
  // Search, filter pills, sortable headers and pagination, all in the browser. Rows are
  // only hidden, never removed, so form fields on other pages are still submitted.
  const store = {
    get: k => { try { return localStorage.getItem(k); } catch { return null; } },
    set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* storage blocked */ } }
  };
  const numeric = v => {
    const t = String(v).trim().replace(/^Rs\s*/i, "").replace(/,/g, "");
    return t !== "" && /^-?\d+(\.\d+)?$/.test(t) ? parseFloat(t) : null;
  };
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

  function setupDataTable(box) {
    const body = box.querySelector(".dt-body");
    if (!body || body.querySelector(".dt-empty")) return;
    const grouped = box.dataset.grouped === "true";
    const perKey = "dt-per:" + location.pathname + "#" + box.id;
    const st = { q: "", filter: "", page: 1, per: Number(store.get(perKey)) || Number(box.dataset.perPage) || 0, col: -1, dir: 1 };
    const perSelect = box.querySelector(".dt-per");
    if (perSelect && st.per) {
      if (![...perSelect.options].some(o => Number(o.value) === st.per)) st.per = Number(box.dataset.perPage);
      perSelect.value = String(st.per);
    }

    // A unit is one row, or (grouped) a row plus the data-cont rows that follow it.
    const units = () => {
      const list = [];
      [...body.rows].forEach(tr => {
        if (grouped && tr.hasAttribute("data-cont") && list.length) list[list.length - 1].push(tr);
        else list.push([tr]);
      });
      return list;
    };
    const text = u => u.map(tr => tr.dataset.search || tr.textContent).join(" ").toLowerCase().replace(/\s+/g, " ");
    const matchesFilter = (u, f) => !f || u.some(tr => (tr.dataset.filter || "").split(/\s+/).includes(f));
    const sortValue = u => {
      const cell = u[0].cells[st.col];
      if (!cell) return "";
      if (cell.dataset.sort !== undefined) return numeric(cell.dataset.sort) ?? cell.dataset.sort;
      const t = cell.textContent.trim();
      return numeric(t) ?? t;
    };

    const info = box.querySelector(".dt-info");
    const pager = box.querySelector(".dt-pager");
    const nomatch = box.querySelector(".dt-nomatch");
    const pills = [...box.querySelectorAll(".dt-filter")];
    st.filter = box.querySelector(".dt-filter.on")?.dataset.value || "";
    const param = box.dataset.filterParam;
    const rememberFilter = () => {
      if (!param) return;
      const value = st.filter || "all";
      const url = new URL(location.href);
      url.searchParams.set(param, value);
      history.replaceState(null, "", url);
      box.querySelectorAll(`input[type=hidden][name="${param}"]`).forEach(i => (i.value = value));
    };

    function render() {
      let all = units();
      if (st.col >= 0) {
        all = all.map((u, i) => [u, sortValue(u), i]).sort((a, b) => {
          const [x, y] = [a[1], b[1]];
          const c = typeof x === "number" && typeof y === "number" ? x - y : collator.compare(String(x), String(y));
          return (c || a[2] - b[2]) * st.dir;
        }).map(e => e[0]);
        all.forEach(u => u.forEach(tr => body.appendChild(tr)));
      }

      const q = st.q.trim().toLowerCase();
      const searched = q ? all.filter(u => text(u).includes(q)) : all;
      pills.forEach(p => {
        const n = p.querySelector(".dt-filter-n");
        if (n) n.textContent = searched.filter(u => matchesFilter(u, p.dataset.value)).length;
      });
      const shown = searched.filter(u => matchesFilter(u, st.filter));

      const pages = st.per ? Math.max(1, Math.ceil(shown.length / st.per)) : 1;
      st.page = Math.min(Math.max(1, st.page), pages);
      const start = st.per ? (st.page - 1) * st.per : 0;
      const end = st.per ? start + st.per : shown.length;
      const visible = new Set(shown.slice(start, end));
      all.forEach(u => u.forEach(tr => { tr.hidden = !visible.has(u); }));
      if (nomatch) nomatch.hidden = shown.length > 0;

      if (info) {
        const total = all.length;
        info.textContent = shown.length
          ? `Showing ${start + 1}–${Math.min(end, shown.length)} of ${shown.length}` + (shown.length < total ? ` (filtered from ${total})` : "")
          : `No matches (out of ${total})`;
      }
      if (pager) renderPager(pages);
    }

    function renderPager(pages) {
      pager.innerHTML = "";
      pager.hidden = pages <= 1;
      if (pages <= 1) return;
      const btn = (label, page, opts = {}) => {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "dt-page" + (opts.on ? " on" : "") + (opts.icon ? " dt-step" : "");
        b.disabled = !!opts.disabled;
        if (opts.on) b.setAttribute("aria-current", "page");
        b.setAttribute("aria-label", opts.aria || `Page ${page}`);
        b.innerHTML = opts.icon ? `<svg class="ic"><use href="#${opts.icon}"/></svg>` : label;
        b.addEventListener("click", () => { st.page = page; render(); const w = box.querySelector(".table-wrap"); if (w) w.scrollTop = 0; box.scrollIntoView({ block: "nearest", behavior: "smooth" }); });
        pager.appendChild(b);
      };
      btn("", st.page - 1, { icon: "i-chev-l", disabled: st.page === 1, aria: "Previous page" });
      const nums = new Set([1, pages, st.page - 1, st.page, st.page + 1].filter(n => n >= 1 && n <= pages));
      let prev = 0;
      [...nums].sort((a, b) => a - b).forEach(n => {
        if (n - prev > 1) pager.insertAdjacentHTML("beforeend", '<span class="dt-gap">…</span>');
        btn(String(n), n, { on: n === st.page });
        prev = n;
      });
      btn("", st.page + 1, { icon: "i-chev-r", disabled: st.page === pages, aria: "Next page" });
    }

    const qInput = box.querySelector(".dt-q");
    let timer;
    qInput?.addEventListener("input", () => { clearTimeout(timer); timer = setTimeout(() => { st.q = qInput.value; st.page = 1; render(); }, 120); });
    qInput?.addEventListener("keydown", e => {
      if (e.key === "Enter") e.preventDefault(); // tables can sit inside a form
      if (e.key === "Escape" && qInput.value) { qInput.value = ""; st.q = ""; st.page = 1; render(); }
    });

    pills.forEach(p => p.addEventListener("click", () => {
      pills.forEach(o => { o.classList.toggle("on", o === p); o.setAttribute("aria-pressed", o === p); });
      st.filter = p.dataset.value; st.page = 1; rememberFilter(); render();
    }));

    perSelect?.addEventListener("change", () => { st.per = Number(perSelect.value); store.set(perKey, st.per); st.page = 1; render(); });

    box.querySelector(".dt-clear")?.addEventListener("click", () => {
      if (qInput) qInput.value = "";
      st.q = ""; st.filter = pills[0]?.dataset.value || ""; st.page = 1;
      pills.forEach((o, i) => { o.classList.toggle("on", i === 0); o.setAttribute("aria-pressed", i === 0); });
      rememberFilter();
      render();
    });

    const ths = [...box.querySelectorAll("thead th")];
    ths.forEach((th, i) => th.querySelector(".dt-sort-btn")?.addEventListener("click", () => {
      st.dir = st.col === i ? -st.dir : 1;
      st.col = i;
      ths.forEach(o => o.hasAttribute("aria-sort") && o.setAttribute("aria-sort", "none"));
      th.setAttribute("aria-sort", st.dir === 1 ? "ascending" : "descending");
      render();
    }));

    box.dtRefresh = render; // call after changing rows (e.g. a rename or status change)
    render();
  }

  // Keep sticky table headers just below the sticky top bar (its height changes when it wraps).
  function initStickyHeaders() {
    const bar = document.querySelector(".topbar");
    const barHeight = () => (bar ? Math.ceil(bar.getBoundingClientRect().height) : 0);
    const setTop = () => root.style.setProperty("--sticky-top", barHeight() + "px");
    setTop();
    if (bar && window.ResizeObserver) new ResizeObserver(setTop).observe(bar);
    else window.addEventListener("resize", setTop);

    // Add a soft shadow to a header while it is stuck — under the top bar when the page
    // scrolls, or at the top of its own box when the table scrolls inside it (phones).
    const heads = [...document.querySelectorAll("table.dt-table thead")];
    if (!heads.length) return;
    let ticking = false;
    const update = () => {
      ticking = false;
      const top = barHeight();
      heads.forEach(h => {
        const wrap = h.closest(".table-wrap");
        const innerScroll = wrap && getComputedStyle(wrap).overflowY !== "visible";
        let stuck;
        if (innerScroll) stuck = wrap.scrollTop > 0;
        else {
          const t = h.closest("table").getBoundingClientRect();
          stuck = t.top < top && t.bottom > top + h.offsetHeight;
        }
        h.querySelectorAll("th").forEach(th => th.classList.toggle("stuck", stuck));
      });
    };
    const schedule = () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } };
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    heads.forEach(h => h.closest(".table-wrap")?.addEventListener("scroll", schedule, { passive: true }));
    update();
  }

  ZK.refreshTable = el => el?.closest("[data-dt]")?.dtRefresh?.();

  function initDataTables() {
    document.querySelectorAll("[data-dt]").forEach(setupDataTable);
    // "/" jumps to the first table search box, like many admin tools.
    document.addEventListener("keydown", e => {
      if (e.key !== "/" || e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.target.closest("input, textarea, select, [contenteditable]")) return;
      const q = document.querySelector(".dt-q");
      if (q) { e.preventDefault(); q.focus(); }
    });
  }

  // ---------- Page entrance ----------
  function entrance() {
    document.querySelectorAll(".toast").forEach(wireToast);
    document.querySelectorAll("[data-count]").forEach(el => {
      const v = el.dataset.count;
      el.dataset.count = 0;
      el.textContent = "0";
      ZK.countTo(el, v);
    });
    if (!animate) return;

    const tl = gsap.timeline({ defaults: { ease: "power3.out" } });
    if (document.querySelector(".topbar")) tl.from(".topbar", { y: -20, opacity: 0, duration: .5 });
    const reveals = gsap.utils.toArray("[data-reveal]");
    if (reveals.length) {
      gsap.set(reveals, { opacity: 0, y: 18 });
      tl.to(reveals, { opacity: 1, y: 0, duration: .7, stagger: .08, clearProps: "opacity,transform" }, "-=.25");
    }

    gsap.utils.toArray("[data-stagger]").forEach(group => {
      const kids = group.matches("tbody") ? group.querySelectorAll("tr") : group.children;
      if (kids.length) gsap.from(kids, { opacity: 0, y: 8, duration: .45, stagger: Math.min(.04, .6 / kids.length), delay: .35, ease: "power2.out", clearProps: "opacity,transform" });
    });

    // Login hero
    if (document.querySelector(".auth-hero")) {
      gsap.to(".auth-hero .b1", { x: -60, y: 40, duration: 9, repeat: -1, yoyo: true, ease: "sine.inOut" });
      gsap.to(".auth-hero .b2", { x: 70, y: -30, duration: 11, repeat: -1, yoyo: true, ease: "sine.inOut" });
      gsap.to(".auth-hero .b3", { x: -40, y: -50, scale: 1.2, duration: 8, repeat: -1, yoyo: true, ease: "sine.inOut" });
      gsap.timeline({ repeat: -1, repeatDelay: 1.2, delay: 1 })
        .set(".scan-line", { top: "18%", opacity: 0 })
        .to(".scan-line", { opacity: 1, duration: .2 })
        .to(".scan-line", { top: "80%", duration: 1.3, ease: "sine.inOut" })
        .to(".scan-line", { top: "18%", duration: 1.3, ease: "sine.inOut" })
        .to(".scan-line", { opacity: 0, duration: .2 })
        .fromTo(".scanner", { boxShadow: "0 0 0 0 rgba(99,230,190,.5)" }, { boxShadow: "0 0 0 18px rgba(99,230,190,0)", duration: .8 }, "<");
    }
  }

  function boot() {
    initNav();
    initPopovers();
    initDataTables();
    initStickyHeaders();
    entrance();
    root.classList.remove("js-anim");
  }

  if (!gsap) root.classList.remove("js-anim");
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", boot) : boot();
})();
