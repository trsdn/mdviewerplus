/*
 * MDViewer+ Full-edition preview renderer.
 *
 * Physically absent from Lite. Every capability here is lazily imported from
 * the bundle-only module scheme and only after the corresponding construct has
 * actually been found in the sanitized document, so ordinary Markdown never
 * initializes highlight.js, js-yaml, Mermaid, or svg-pan-zoom.
 */
(function () {
  "use strict";

  const NONCE = window.__mdviewerNonce;
  const MODULE_BASE = window.__mdviewerModuleBase;

  const LIMITS = Object.freeze({
    frontmatterMaxBytes: 64 * 1024,
    frontmatterMaxDepth: 8,
    frontmatterMaxEntries: 40,
    frontmatterMaxListItems: 24,
    frontmatterMaxValueLength: 400,
    frontmatterMaxNodes: 2000,
    highlightMaxLength: 200000,
    highlightAutoMaxLength: 20000,
    diagramMaxSourceLength: 50000,
    diagramMaxCount: 40,
    diagramTimeoutMs: 12000,
    diagramConcurrency: 2,
  });

  const AUTO_DETECT_LANGUAGES = Object.freeze([
    "bash", "c", "cpp", "csharp", "css", "diff", "go", "ini", "java",
    "javascript", "json", "kotlin", "less", "lua", "makefile", "markdown",
    "objectivec", "perl", "php", "python", "ruby", "rust", "scss", "shell",
    "sql", "swift", "typescript", "xml", "yaml",
  ]);

  const modules = { highlight: null, yaml: null, mermaid: null, panZoom: null };
  const loading = {};
  window.__mdviewerModuleErrors = {};

  function loadModule(name, relativePath) {
    if (modules[name]) return Promise.resolve(modules[name]);
    if (loading[name]) return loading[name];
    loading[name] = import(`${MODULE_BASE}${relativePath}`)
      .then((module) => {
        modules[name] = module;
        window.__mdviewerLoadedModules[name] = true;
        return module;
      })
      .catch((error) => {
        delete loading[name];
        window.__mdviewerModuleErrors[name] = String(
          error && (error.stack || error.message || error)
        );
        throw error;
      });
    return loading[name];
  }

  window.__mdviewerLoadedModules = {};

  function localError(message) {
    const box = document.createElement("div");
    box.className = "md-inline-error";
    box.setAttribute("role", "alert");
    box.textContent = message;
    return box;
  }

  /* ---------------------------------------------------------- frontmatter */

  const UNSAFE_KEYS = new Set(["__proto__", "constructor", "prototype"]);

  function boundedDepth(value, depth, budget) {
    if (depth > LIMITS.frontmatterMaxDepth) return false;
    budget.nodes += 1;
    if (budget.nodes > LIMITS.frontmatterMaxNodes) return false;
    if (value === null || typeof value !== "object") return true;
    if (budget.seen.has(value)) return false; // alias or cycle
    budget.seen.add(value);

    const entries = Array.isArray(value) ? value : Object.values(value);
    if (!Array.isArray(value)) {
      for (const key of Object.keys(value)) {
        if (UNSAFE_KEYS.has(key)) return false;
      }
    }
    for (const entry of entries) {
      if (!boundedDepth(entry, depth + 1, budget)) return false;
    }
    return true;
  }

  function formatScalar(value) {
    const text = value === null ? "" : String(value);
    return text.length > LIMITS.frontmatterMaxValueLength
      ? `${text.slice(0, LIMITS.frontmatterMaxValueLength)}…`
      : text;
  }

  function renderValue(value) {
    if (Array.isArray(value)) {
      const list = document.createElement("ul");
      list.className = "md-frontmatter-list";
      for (const item of value.slice(0, LIMITS.frontmatterMaxListItems)) {
        const entry = document.createElement("li");
        entry.appendChild(renderValue(item));
        list.appendChild(entry);
      }
      if (value.length > LIMITS.frontmatterMaxListItems) {
        const more = document.createElement("li");
        more.className = "md-frontmatter-more";
        more.textContent = `+${value.length - LIMITS.frontmatterMaxListItems} more`;
        list.appendChild(more);
      }
      return list;
    }

    if (value && typeof value === "object") {
      const list = document.createElement("dl");
      list.className = "md-frontmatter-nested";
      const keys = Object.keys(value).slice(0, LIMITS.frontmatterMaxListItems);
      for (const key of keys) {
        const term = document.createElement("dt");
        term.textContent = formatScalar(key);
        const definition = document.createElement("dd");
        definition.appendChild(renderValue(value[key]));
        list.appendChild(term);
        list.appendChild(definition);
      }
      return list;
    }

    const span = document.createElement("span");
    span.className = "md-frontmatter-value";
    span.textContent = formatScalar(value);
    return span;
  }

  function buildFrontmatterCard(data) {
    const card = document.createElement("details");
    card.className = "md-frontmatter";
    card.open = true;

    const summary = document.createElement("summary");
    summary.className = "md-frontmatter-summary";
    const keys = Object.keys(data);
    const label = document.createElement("span");
    label.textContent = `Metadata (${keys.length} ${keys.length === 1 ? "entry" : "entries"})`;
    summary.appendChild(label);
    if (keys.length > 0) {
      const preview = document.createElement("span");
      preview.className = "md-frontmatter-key-preview";
      preview.textContent = keys
        .slice(0, 3)
        .map((key) => formatScalar(key))
        .join(", ") + (keys.length > 3 ? ", …" : "");
      summary.appendChild(preview);
    }
    card.appendChild(summary);

    const list = document.createElement("dl");
    list.className = "md-frontmatter-entries";
    for (const key of keys.slice(0, LIMITS.frontmatterMaxEntries)) {
      const term = document.createElement("dt");
      term.textContent = formatScalar(key);
      const definition = document.createElement("dd");
      definition.appendChild(renderValue(data[key]));
      list.appendChild(term);
      list.appendChild(definition);
    }
    if (keys.length > LIMITS.frontmatterMaxEntries) {
      const term = document.createElement("dt");
      term.className = "md-frontmatter-more";
      term.textContent = `+${keys.length - LIMITS.frontmatterMaxEntries} more entries`;
      list.appendChild(term);
      list.appendChild(document.createElement("dd"));
    }
    card.appendChild(list);
    return card;
  }

  window.__mdviewerReadFrontmatter = async function (source, body) {
    const yamlSource = String(source ?? "");
    const markdownBody = String(body ?? "");

    if (yamlSource.length > LIMITS.frontmatterMaxBytes) {
      return {
        body: markdownBody,
        card: localError("Frontmatter is too large to display."),
      };
    }
    const yamlLines = yamlSource.split(/\r\n|\r|\n/);
    if (
      yamlLines.length > LIMITS.frontmatterMaxNodes ||
      /(^|[\s,[{])[&*][A-Za-z0-9_-]+/m.test(yamlSource)
    ) {
      return {
        body: markdownBody,
        card: localError(
          "Frontmatter was rejected: anchors, aliases, or excessive collections are not supported."
        ),
      };
    }

    let yaml;
    try {
      yaml = await loadModule("yaml", "js-yaml.esm.min.mjs");
    } catch {
      return {
        body: markdownBody,
        card: localError("Frontmatter support could not be loaded."),
      };
    }

    let data;
    try {
      data = yaml.load(yamlSource, {
        schema: yaml.FAILSAFE_SCHEMA,
        json: false,
        onWarning: null,
      });
    } catch (error) {
      const message = error && error.reason ? error.reason : "invalid YAML";
      return {
        body: markdownBody,
        card: localError(`Frontmatter could not be parsed: ${message}`),
      };
    }

    if (data === null || data === undefined) {
      return { body: markdownBody, card: null };
    }
    if (typeof data !== "object" || Array.isArray(data)) {
      return {
        body: markdownBody,
        card: localError("Frontmatter must be a mapping."),
      };
    }
    if (!boundedDepth(data, 0, { nodes: 0, seen: new WeakSet() })) {
      return {
        body: markdownBody,
        card: localError("Frontmatter was rejected: it is too deep, too large, or self-referential."),
      };
    }

    return { body: markdownBody, card: buildFrontmatterCard(data) };
  };

  /* ----------------------------------------------------------- highlight */

  window.__mdviewerHighlightBlocks = async function (blocks, generation) {
    const candidates = blocks.filter(
      (block) =>
        block.language !== "mermaid" &&
        block.source !== undefined &&
        block.source.length <= LIMITS.highlightMaxLength
    );
    if (candidates.length === 0) return;

    let hljs;
    try {
      hljs = (await loadModule("highlight", "highlight.esm.min.mjs")).default;
    } catch {
      return; // Plain-text fallback: the code stays exactly as written.
    }
    if (generation !== window.mdviewerRenderGeneration()) return;

    const known = new Set(hljs.listLanguages());
    for (const block of candidates) {
      let html = null;
      try {
        const alias = window.__mdviewerPrismAlias(block.language);
        if (block.language && (known.has(block.language) || hljs.getLanguage(block.language))) {
          html = hljs.highlight(block.source, {
            language: block.language,
            ignoreIllegals: true,
          }).value;
        } else if (alias && hljs.getLanguage(alias)) {
          html = hljs.highlight(block.source, {
            language: alias,
            ignoreIllegals: true,
          }).value;
        } else if (
          !block.language &&
          block.source.length <= LIMITS.highlightAutoMaxLength
        ) {
          const detected = hljs.highlightAuto(
            block.source,
            AUTO_DETECT_LANGUAGES.filter((name) => known.has(name))
          );
          html = detected.value;
          if (detected.language) {
            const label = block.pre.parentElement?.parentElement?.querySelector(
              ".md-code-language"
            );
            if (label && label.textContent === "text") label.textContent = detected.language;
          }
        }
      } catch {
        html = null;
      }

      if (html === null) continue;
      if (generation !== window.mdviewerRenderGeneration()) return;
      const fragment = window.__mdviewerSanitizeHighlight(html);
      if (fragment) {
        block.code.classList.add("hljs");
        block.code.replaceChildren(fragment);
      }
    }
  };

  /* --------------------------------------------------------------- mermaid */

  const diagrams = {
    generation: 0,
    pending: [],
    observer: null,
    active: new Set(),
    initialized: false,
    counter: 0,
  };

  function sanitizeDiagramSVG(svgText) {
    // A dedicated SVG policy, entirely separate from the Markdown sanitizer.
    const root = DOMPurify.sanitize(svgText, {
      USE_PROFILES: { svg: true, svgFilters: true },
      ADD_TAGS: ["style"],
      FORBID_TAGS: ["foreignObject", "script", "a", "animate", "set", "handler", "use"],
      FORBID_ATTR: ["href", "xlink:href", "formaction", "action", "target", "ping"],
      ALLOW_DATA_ATTR: false,
      RETURN_DOM_FRAGMENT: true,
    });

    const svg = root.querySelector("svg");
    if (!svg) return null;

    for (const element of svg.querySelectorAll("*")) {
      for (const attribute of Array.from(element.attributes)) {
        const name = attribute.name.toLowerCase();
        if (name.startsWith("on")) {
          element.removeAttribute(attribute.name);
          continue;
        }
        if (/url\s*\(\s*['"]?\s*(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(attribute.value)) {
          element.removeAttribute(attribute.name);
        }
      }
    }

    // Mermaid styles diagrams with an inline <style> element. It is kept, but
    // scrubbed of remote references and re-nonced so the strict style-src
    // policy stays intact instead of being relaxed to 'unsafe-inline'.
    for (const style of svg.querySelectorAll("style")) {
      const css = style.textContent || "";
      if (/@import|url\s*\(\s*['"]?\s*(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(css)) {
        style.textContent = css
          .replace(/@import[^;]*;/gi, "")
          .replace(/url\s*\([^)]*\)/gi, "none");
      }
      style.setAttribute("nonce", NONCE);
    }

    svg.removeAttribute("width");
    svg.setAttribute("class", "md-diagram-svg");
    svg.setAttribute("role", "img");
    return svg;
  }

  async function ensureMermaid(themeCategory) {
    const mermaid = (await loadModule("mermaid", "mermaid/mermaid.esm.min.mjs")).default;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      theme: themeCategory === "dark" ? "dark" : "default",
      fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif',
      deterministicIds: true,
      suppressErrorRendering: true,
    });
    return mermaid;
  }

  function teardownPanZoom(container) {
    const resizeObserver = container.__mdviewerResizeObserver;
    if (resizeObserver) {
      resizeObserver.disconnect();
      container.__mdviewerResizeObserver = null;
    }
    if (container.__mdviewerFitFrame) {
      cancelAnimationFrame(container.__mdviewerFitFrame);
      container.__mdviewerFitFrame = 0;
    }

    const instance = container.__mdviewerPanZoom;
    if (instance && typeof instance.destroy === "function") {
      try {
        instance.destroy();
      } catch {
        /* already detached */
      }
    }
    container.__mdviewerPanZoom = null;

    const controls = container.querySelector(".md-diagram-controls");
    if (controls) controls.remove();
  }

  function teardownActiveDiagrams() {
    for (const container of diagrams.active) teardownPanZoom(container);
    diagrams.active.clear();
  }

  function applyDiagramAspectRatio(stage, svg) {
    const viewBox = svg.viewBox && svg.viewBox.baseVal;
    if (!viewBox || viewBox.width <= 0 || viewBox.height <= 0) return;
    const inset = 48;
    stage.style.setProperty(
      "--md-diagram-aspect-ratio",
      `${viewBox.width + inset} / ${viewBox.height + inset}`
    );
  }

  async function attachPanZoom(container, svg) {
    try {
      const svgPanZoom = (await loadModule("panZoom", "svg-pan-zoom.esm.min.mjs")).default;
      if (!svg.isConnected || svg.closest(".md-diagram") !== container) return;

      svg.setAttribute("width", "100%");
      svg.setAttribute("height", "100%");
      const instance = svgPanZoom(svg, {
        zoomEnabled: true,
        controlIconsEnabled: false,
        fit: true,
        center: true,
        minZoom: 0.2,
        maxZoom: 12,
        dblClickZoomEnabled: false,
        // Wheel panning stays with the page so preview scrolling is unaffected.
        mouseWheelZoomEnabled: false,
      });
      container.__mdviewerPanZoom = instance;

      const controls = document.createElement("div");
      controls.className = "md-diagram-controls";
      controls.setAttribute("role", "group");
      controls.setAttribute("aria-label", "Diagram zoom controls");
      const button = (text, label, action) => {
        const element = document.createElement("button");
        element.type = "button";
        element.className = "md-diagram-button";
        element.textContent = text;
        element.setAttribute("aria-label", label);
        element.addEventListener("click", action);
        return element;
      };
      controls.appendChild(button("−", "Zoom out", () => instance.zoomOut()));
      controls.appendChild(button("+", "Zoom in", () => instance.zoomIn()));
      controls.appendChild(
        button("Fit", "Fit diagram", () => {
          instance.resize();
          instance.fit();
          instance.center();
        })
      );
      container.appendChild(controls);

      const stage = svg.parentElement;
      const fit = () => {
        if (container.__mdviewerPanZoom !== instance || !svg.isConnected) return;
        instance.resize();
        instance.fit();
        instance.center();
      };
      const scheduleFit = () => {
        if (container.__mdviewerFitFrame) return;
        container.__mdviewerFitFrame = requestAnimationFrame(() => {
          container.__mdviewerFitFrame = 0;
          fit();
        });
      };

      stage.setAttribute("tabindex", "0");
      stage.setAttribute("role", "group");
      stage.setAttribute("aria-label", "Diagram: use arrow keys to pan, plus and minus to zoom");
      stage.addEventListener("keydown", (event) => {
        const step = 40;
        switch (event.key) {
          case "ArrowLeft": event.preventDefault(); instance.panBy({ x: step, y: 0 }); break;
          case "ArrowRight": event.preventDefault(); instance.panBy({ x: -step, y: 0 }); break;
          case "ArrowUp": event.preventDefault(); instance.panBy({ x: 0, y: step }); break;
          case "ArrowDown": event.preventDefault(); instance.panBy({ x: 0, y: -step }); break;
          case "+": case "=": event.preventDefault(); instance.zoomIn(); break;
          case "-": event.preventDefault(); instance.zoomOut(); break;
          case "0":
            event.preventDefault();
            instance.resize();
            instance.fit();
            instance.center();
            break;
          default: break;
        }
      });

      scheduleFit();
      if (typeof ResizeObserver === "function") {
        let lastWidth = -1;
        let lastHeight = -1;
        const resizeObserver = new ResizeObserver((entries) => {
          const entry = entries[entries.length - 1];
          if (!entry) return;
          const width = Math.round(entry.contentRect.width * 2) / 2;
          const height = Math.round(entry.contentRect.height * 2) / 2;
          if (width === lastWidth && height === lastHeight) return;
          lastWidth = width;
          lastHeight = height;
          scheduleFit();
        });
        resizeObserver.observe(stage);
        container.__mdviewerResizeObserver = resizeObserver;
      }
    } catch {
      /* Pan and zoom is an enhancement; a static diagram remains usable. */
    }
  }

  function makeDiagramContainer(block) {
    const container = document.createElement("div");
    container.className = "md-diagram";
    container.setAttribute("data-md-diagram", "pending");
    diagrams.active.add(container);
    // The definition is retained so theme changes, retries, and printing can
    // rerender without reparsing the document.
    container.__mdviewerSource = block.code.textContent;

    const stage = document.createElement("div");
    stage.className = "md-diagram-stage";
    container.appendChild(stage);

    const fallback = document.createElement("pre");
    fallback.className = "md-diagram-source";
    const code = document.createElement("code");
    code.className = "language-mermaid";
    code.textContent = container.__mdviewerSource;
    fallback.appendChild(code);
    container.appendChild(fallback);

    block.pre.replaceWith(container);
    return container;
  }

  async function renderDiagram(container, generation, themeCategory) {
    const source = container.__mdviewerSource || "";
    if (source.length > LIMITS.diagramMaxSourceLength) {
      failDiagram(container, "Diagram source is too large to render.");
      return;
    }

    let mermaid;
    try {
      mermaid = await ensureMermaid(themeCategory);
    } catch {
      failDiagram(container, "Diagram support could not be loaded.");
      return;
    }
    if (generation !== diagrams.generation) return;

    diagrams.counter += 1;
    const id = `md-diagram-${generation}-${diagrams.counter}`;

    let svgText;
    try {
      const timeout = new Promise((_, reject) =>
        window.setTimeout(() => reject(new Error("timeout")), LIMITS.diagramTimeoutMs)
      );
      const result = await Promise.race([mermaid.render(id, source), timeout]);
      svgText = result.svg;
    } catch (error) {
      failDiagram(
        container,
        `Diagram could not be rendered: ${(error && error.message) || "parse error"}`
      );
      return;
    }
    if (generation !== diagrams.generation) return;

    const svg = sanitizeDiagramSVG(svgText);
    if (!svg) {
      failDiagram(container, "Diagram output was rejected by the sanitizer.");
      return;
    }

    const stage = container.querySelector(".md-diagram-stage");
    teardownPanZoom(container);
    stage.replaceChildren(svg);
    applyDiagramAspectRatio(stage, svg);
    container.setAttribute("data-md-diagram", "rendered");
    const fallback = container.querySelector(".md-diagram-source");
    if (fallback) fallback.hidden = true;
    const previousError = container.querySelector(".md-inline-error");
    if (previousError) previousError.remove();

    if (!window.__mdviewerInternals.state.printMode) {
      await attachPanZoom(container, svg);
    }
  }

  function failDiagram(container, message) {
    teardownPanZoom(container);
    container.setAttribute("data-md-diagram", "failed");
    const fallback = container.querySelector(".md-diagram-source");
    if (fallback) fallback.hidden = false; // Original source is restored.
    const previous = container.querySelector(".md-inline-error");
    if (previous) previous.remove();
    container.insertBefore(localError(message), container.firstChild);
  }

  function teardownObserver() {
    if (diagrams.observer) {
      diagrams.observer.disconnect();
      diagrams.observer = null;
    }
  }

  async function drain(generation, themeCategory) {
    while (diagrams.pending.length > 0 && generation === diagrams.generation) {
      const batch = diagrams.pending.splice(0, LIMITS.diagramConcurrency);
      await Promise.all(
        batch.map((container) => renderDiagram(container, generation, themeCategory))
      );
    }
  }

  window.__mdviewerRenderDiagrams = function (blocks, generation, printMode) {
    diagrams.generation = generation;
    diagrams.pending = [];
    teardownObserver();
    teardownActiveDiagrams();
    if (blocks.length === 0) return;

    const themeCategory = window.__mdviewerInternals.state.themeCategory;
    const limited = blocks.slice(0, LIMITS.diagramMaxCount);
    const containers = limited.map(makeDiagramContainer);

    if (blocks.length > LIMITS.diagramMaxCount) {
      for (const extra of blocks.slice(LIMITS.diagramMaxCount)) {
        const container = makeDiagramContainer(extra);
        failDiagram(
          container,
          `Only the first ${LIMITS.diagramMaxCount} diagrams are rendered in this document.`
        );
      }
    }

    if (printMode) {
      diagrams.pending = containers.slice();
      diagrams.printJob = drain(generation, themeCategory);
      return;
    }

    // Render near the viewport so a long document with many diagrams does not
    // block typing or the preview debounce.
    if (typeof IntersectionObserver === "function") {
      const observer = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (!entry.isIntersecting) continue;
            observer.unobserve(entry.target);
            if (generation !== diagrams.generation) continue;
            diagrams.pending.push(entry.target);
            drain(generation, themeCategory);
          }
        },
        { rootMargin: "400px 0px" }
      );
      diagrams.observer = observer;
      for (const container of containers) observer.observe(container);
    } else {
      diagrams.pending = containers.slice();
      drain(generation, themeCategory);
    }
  };

  window.__mdviewerFullThemeChanged = function (themeCategory, generation) {
    if (!modules.mermaid) return; // Never initializes Mermaid just to retheme.
    const containers = Array.from(document.querySelectorAll(".md-diagram"));
    if (containers.length === 0) return;
    diagrams.generation = generation;
    for (const container of containers) {
      teardownPanZoom(container);
    }
    diagrams.pending = containers;
    drain(generation, themeCategory);
  };

  window.__mdviewerPreparePrint = async function (generation, deadline) {
    const containers = Array.from(document.querySelectorAll(".md-diagram"));
    const outstanding = containers.filter(
      (container) => container.getAttribute("data-md-diagram") === "pending"
    );
    teardownObserver();
    if (outstanding.length > 0) {
      diagrams.generation = generation;
      diagrams.pending = outstanding;
      await drain(generation, window.__mdviewerInternals.state.themeCategory);
    }
    if (diagrams.printJob) {
      await diagrams.printJob;
      diagrams.printJob = null;
    }
    void deadline;
  };

  window.__mdviewerFullLimits = LIMITS;
})();
