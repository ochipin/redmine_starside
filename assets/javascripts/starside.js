(function () {
  function activate(tab) {
    const tablist = tab.closest('[role="tablist"]');
    if (!tablist) return;

    const tabs = [...tablist.querySelectorAll('[role="tab"]')];
    const panels = tabs.map(t =>
      document.getElementById(t.getAttribute("aria-controls"))
    );

    tabs.forEach((t, i) => {
      const selected = t === tab;
      t.setAttribute("aria-selected", selected);
      t.tabIndex = selected ? 0 : -1;
      if (panels[i]) panels[i].hidden = !selected;
    });
  }

  // クリックは document 全体で1回だけ受ける(イベント委譲)
  document.addEventListener("click", function (e) {
    const tab = e.target.closest('[role="tab"]');
    if (tab) activate(tab);
  });

  // キーボード操作も委譲
  document.addEventListener("keydown", function (e) {
    const current = e.target.closest('[role="tab"]');
    if (!current) return;

    const tablist = current.closest('[role="tablist"]');
    const tabs = [...tablist.querySelectorAll('[role="tab"]')];
    let i = tabs.indexOf(current);

    switch (e.key) {
      case "ArrowRight": i = (i + 1) % tabs.length; break;
      case "ArrowLeft":  i = (i - 1 + tabs.length) % tabs.length; break;
      case "Home":       i = 0; break;
      case "End":        i = tabs.length - 1; break;
      case "Enter":
      case " ":
        activate(current);
        return;
      default:
        return;
    }
    e.preventDefault();
    activate(tabs[i]);
    tabs[i].focus();
  });
})();

/* ===========================================================================
 * チェックボックス表記の置換
 *   [ ]        -> 空チェックボックス (☐)
 *   [x][X][*]  -> チェック済み       (☑)
 * Textile が [X] を <a> 化してしまうケースも救済する。
 * プレビュー等の動的更新に MutationObserver で追従する。
 * ------------------------------------------------------------------------ */
(function () {
  "use strict";

  // 置換対象のコンテナ
  const CONTAINER_SELECTOR =
    ".wiki, .preview, .journal .wiki, #preview";

  // 表示に使う文字（&#xFE0E; = 異体字セレクタで絵文字化を抑止しテキスト表示に固定）
  const BOX_EMPTY = "\u2610\uFE0E"; // ☐
  const BOX_CHECK = "\u2611\uFE0E"; // ☑

  // TextNode 走査時にスキップする要素（コード例として書かれた [ ] を保護）
  const SKIP_TAGS = new Set(["PRE", "CODE", "SCRIPT", "STYLE", "TEXTAREA"]);

  // 処理済みコンテナに付けるフラグ。再処理と無限ループを防ぐ。
  const DONE_FLAG = "data-starside-checkbox";

  const EMPTY_RE = /\[ \]/g;
  const CHECK_RE = /\[[xX*]\]/g;

  // --- TextNode 内のプレーンな [ ] / [x] を置換 -----------------------------
  function replaceInTextNodes(root) {
    const walker = document.createTreeWalker(
      root,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode(node) {
          // コード系の親を持つテキストは除外
          for (let p = node.parentNode; p && p !== root; p = p.parentNode) {
            if (p.nodeType === 1 && SKIP_TAGS.has(p.tagName)) {
              return NodeFilter.FILTER_REJECT;
            }
          }
          return /\[ \]|\[[xX*]\]/.test(node.nodeValue)
            ? NodeFilter.FILTER_ACCEPT
            : NodeFilter.FILTER_SKIP;
        },
      }
    );

    const targets = [];
    let n;
    while ((n = walker.nextNode())) targets.push(n);

    targets.forEach((node) => {
      node.nodeValue = node.nodeValue
        .replace(EMPTY_RE, BOX_EMPTY)
        .replace(CHECK_RE, BOX_CHECK);
    });
  }

  // --- Textile に <a> 化された [X] を救済 -----------------------------------
  function rescueLinkedChecks(root) {
    root.querySelectorAll("a").forEach((a) => {
      const t = (a.textContent || "").trim();
      if (t === "X" || t === "x") {
        a.replaceWith(document.createTextNode(BOX_CHECK));
      }
    });
  }

  function process(container) {
    replaceInTextNodes(container);
    rescueLinkedChecks(container);
    container.setAttribute(DONE_FLAG, "1");
  }

  function processAll(scope) {
    (scope || document)
      .querySelectorAll(CONTAINER_SELECTOR)
      .forEach((c) => {
        if (!c.hasAttribute(DONE_FLAG)) process(c);
      });
    // scope 自身が対象コンテナのこともある
    if (
      scope &&
      scope.nodeType === 1 &&
      scope.matches(CONTAINER_SELECTOR) &&
      !scope.hasAttribute(DONE_FLAG)
    ) {
      process(scope);
    }
  }

  function init() {
    processAll(document);

    // プレビュー差し替え等の DOM 変化に追従。
    // 自分の書き換えで再発火しないよう、処理中は監視を止める。
    let scheduled = false;
    const observer = new MutationObserver((mutations) => {
      if (scheduled) return;

      // 影響を受けた範囲だけを拾う
      const roots = new Set();
      for (const m of mutations) {
        m.addedNodes.forEach((node) => {
          if (node.nodeType === 1) roots.add(node);
        });
        // プレビューはコンテナの中身だけ差し替わることが多い
        if (m.target && m.target.nodeType === 1) roots.add(m.target);
      }
      if (roots.size === 0) return;

      scheduled = true;
      observer.disconnect();
      try {
        roots.forEach((r) => {
          // 差し替えられたコンテナは再処理したいのでフラグを一旦外す
          if (r.matches && r.matches(CONTAINER_SELECTOR)) {
            r.removeAttribute(DONE_FLAG);
          }
          processAll(r);
        });
      } finally {
        observer.observe(document.body, { childList: true, subtree: true });
        scheduled = false;
      }
    });

    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
