const REVISION = "TAP-0081-r3-candidate";

const POLICY = Object.freeze({
  progressPresentation: "immediate",
  minimumVisibleHold: false,
  payloadReadyBehavior: "closeAppPopover",
  systemActivitySimulation: false
});

const FIXTURE_DURATIONS = Object.freeze({ success: 1400, failure: 720 });
const INTEGRITY_FIXTURE_DURATIONS = Object.freeze({ auto: 650 });
const READY_RESOURCES = new Set(["localReady", "iCloudReady", "privateQueue"]);

const SELECTORS = Object.freeze({
  popover: "[data-tap-share-popover], #share-popover",
  panel: "[data-tap-share-panel], [data-panel]",
  options: "[data-tap-share-options], #share-options",
  credentialIcon: "[data-tap-share-credential-icon], #credential-icon",
  credentialLabel: "[data-tap-share-credential-label], #credential-label",
  mediaChip: "[data-tap-share-media-chip], #media-chip",
  resourceOverlay: "[data-tap-share-resource-overlay], #resource-overlay",
  resourceWarningIcon: "[data-tap-share-resource-warning-icon], #resource-warning-icon",
  resourceTitle: "[data-tap-share-resource-title], #resource-title",
  resourceSubtitle: "[data-tap-share-resource-subtitle], #resource-subtitle",
  resourceProgressRow: "[data-tap-share-resource-progress-row], #resource-progress-row",
  resourceProgress: "[data-tap-share-resource-progress], #resource-progress",
  resourceProgressLabel: "[data-tap-share-resource-progress-label], #resource-progress-label",
  resourceShareStatus: "[data-tap-share-resource-status], #resource-share-status",
  resolveIntegrity: "[data-tap-share-action='resolve-integrity'], #resolve-integrity-button",
  failureCancel: "[data-tap-share-action='failure-cancel'], #failure-cancel",
  retry: "[data-tap-share-action='retry'], #retry-button",
  credentialScopeNote: "[data-tap-share-credential-scope-note], #credential-scope-note",
  mediaControl: "[data-tap-share-media], [data-media]",
  resourceControl: "[data-tap-share-resource], [data-resource]",
  credentialControl: "[data-tap-share-credential], [data-credential]",
  integrityFixtureControl: "[data-tap-share-integrity-fixture], [data-integrity-fixture]",
  preparationFixtureControl: "[data-tap-share-preparation-fixture], [data-fixture]"
});

const activeMounts = new WeakMap();

function requireNode(root, selector, label) {
  const node = root.querySelector(selector);
  if (!node) throw new Error(`TAP Share host is missing ${label} (${selector})`);
  return node;
}

function hookValue(node, names) {
  for (const name of names) {
    const value = node.dataset[name];
    if (value) return value;
  }
  return null;
}

function panelName(panel) {
  return hookValue(panel, ["tapSharePanel", "panel"]);
}

function assertMountArgument(value, name) {
  if (!value || typeof value.querySelector !== "function" || typeof value.addEventListener !== "function") {
    throw new TypeError(`mountTapShareSlice requires a DOM ${name}`);
  }
}

/**
 * Mounts the owner-approved TAP-0081-r3 local Share interaction into an existing
 * host. The host owns its surrounding Viewer and any cross-slice presentation;
 * this controller owns only the local Share state below.
 *
 * @param {{
 *   root: Element,
 *   trigger: HTMLElement,
 *   onStateChange?: (snapshot: Readonly<object>, meta: Readonly<{reason: string}>) => void
 * }} options
 * @returns {Readonly<{
 *   open: () => Readonly<object>,
 *   close: () => Readonly<object>,
 *   destroy: () => Readonly<object>,
 *   snapshot: () => Readonly<object>
 * }>}
 */
export function mountTapShareSlice({ root, trigger, onStateChange } = {}) {
  assertMountArgument(root, "root");
  if (!trigger || typeof trigger.addEventListener !== "function" || typeof trigger.setAttribute !== "function") {
    throw new TypeError("mountTapShareSlice requires a DOM trigger");
  }
  if (onStateChange != null && typeof onStateChange !== "function") {
    throw new TypeError("onStateChange must be a function when provided");
  }
  if (activeMounts.has(root)) {
    throw new Error("TAP Share is already mounted in this root");
  }

  const popover = requireNode(root, SELECTORS.popover, "Share popover");
  const ownerDocument = root.ownerDocument;
  const timerHost = ownerDocument?.defaultView ?? globalThis;
  const panels = [...root.querySelectorAll(SELECTORS.panel)];
  const options = requireNode(root, SELECTORS.options, "Share options container");
  const credentialIcon = requireNode(root, SELECTORS.credentialIcon, "credential icon");
  const credentialLabel = requireNode(root, SELECTORS.credentialLabel, "credential label");
  const mediaChip = requireNode(root, SELECTORS.mediaChip, "media chip");
  const resourceOverlay = requireNode(root, SELECTORS.resourceOverlay, "resource overlay");
  const resourceWarningIcon = requireNode(root, SELECTORS.resourceWarningIcon, "resource warning icon");
  const resourceTitle = requireNode(root, SELECTORS.resourceTitle, "resource title");
  const resourceSubtitle = requireNode(root, SELECTORS.resourceSubtitle, "resource subtitle");
  const resourceProgressRow = requireNode(root, SELECTORS.resourceProgressRow, "resource progress row");
  const resourceProgress = requireNode(root, SELECTORS.resourceProgress, "resource progress");
  const resourceProgressLabel = requireNode(root, SELECTORS.resourceProgressLabel, "resource progress label");
  const resourceShareStatus = requireNode(root, SELECTORS.resourceShareStatus, "resource Share status");
  const resolveIntegrityButton = root.querySelector(SELECTORS.resolveIntegrity);
  const failureCancelButton = requireNode(root, SELECTORS.failureCancel, "failure cancel action");
  const retryButton = requireNode(root, SELECTORS.retry, "retry action");
  const credentialScopeNote = root.querySelector(SELECTORS.credentialScopeNote);

  for (const requiredPanel of ["integrityChecking", "selector", "failure"]) {
    if (!panels.some((panel) => panelName(panel) === requiredPanel)) {
      throw new Error(`TAP Share host is missing the ${requiredPanel} panel`);
    }
  }

  const state = {
    media: "photo",
    resource: "localReady",
    credential: "verified",
    integrityFixture: "auto",
    fixture: "success",
    panel: "closed",
    progress: 0,
    selectedOption: null,
    attempt: 0,
    timers: new Set(),
    systemActivityBoundaryReached: false
  };

  const listenerCleanups = [];
  let destroyed = false;

  function snapshot() {
    return Object.freeze({
      revision: REVISION,
      media: state.media,
      resource: state.resource,
      credential: state.credential,
      integrityFixture: state.integrityFixture,
      fixture: state.fixture,
      panel: state.panel,
      progress: state.progress,
      selectedOption: state.selectedOption,
      attempt: state.attempt,
      timers: state.timers.size,
      systemActivityBoundaryReached: state.systemActivityBoundaryReached,
      destroyed,
      policy: POLICY
    });
  }

  function publish(reason) {
    root.dataset.tapShareState = state.panel;
    root.dataset.tapShareMedia = state.media;
    root.dataset.tapShareResource = state.resource;
    root.dataset.tapShareCredential = state.credential;
    root.dataset.tapShareIntegrityFixture = state.integrityFixture;
    root.dataset.tapSharePreparationFixture = state.fixture;
    root.dataset.tapShareProgressVisible = String(state.panel === "preparing");
    root.dataset.tapShareSystemBoundary = state.systemActivityBoundaryReached ? "reached" : "notReached";
    root.dataset.tapShareDestroyed = String(destroyed);
    if (onStateChange) onStateChange(snapshot(), Object.freeze({ reason }));
  }

  function ensureActive() {
    if (destroyed) throw new Error("TAP Share mount has been destroyed");
  }

  function later(callback, delay) {
    const timer = timerHost.setTimeout(() => {
      state.timers.delete(timer);
      if (!destroyed) callback();
    }, delay);
    state.timers.add(timer);
  }

  function clearTimers() {
    for (const timer of state.timers) timerHost.clearTimeout(timer);
    state.timers.clear();
  }

  function showPanel(name, reason = `panel.${name}`) {
    state.panel = name;
    const visiblePanel = name === "preparing" ? "selector" : name;
    popover.hidden = name === "closed";
    trigger.setAttribute("aria-expanded", String(name !== "closed"));
    for (const panel of panels) panel.hidden = panelName(panel) !== visiblePanel;
    trigger.classList.toggle("is-preparing", name === "preparing");
    if (resolveIntegrityButton) resolveIntegrityButton.disabled = name !== "integrityChecking";
    publish(reason);
  }

  function setProgress(value) {
    state.progress = Math.max(state.progress, Math.min(1, Math.max(0, value)));
    const progressBar = root.querySelector("[data-tap-share-progress], #progress-bar");
    if (progressBar) progressBar.value = state.progress;
    publish("preparation.progress");
  }

  function isResourceReady() {
    return READY_RESOURCES.has(state.resource);
  }

  function updatePressed(selector, valueNames, selectedValue) {
    root.querySelectorAll(selector).forEach((button) => {
      button.setAttribute("aria-pressed", String(hookValue(button, valueNames) === selectedValue));
    });
  }

  function updateCredentialControls() {
    const credentialControls = [...root.querySelectorAll(SELECTORS.credentialControl)];
    const retryPendingButton = credentialControls.find((button) => (
      hookValue(button, ["tapShareCredential", "credential"]) === "retryPending"
    ));
    const queueOnly = state.resource === "privateQueue";
    if (retryPendingButton) retryPendingButton.disabled = !queueOnly;
    if (credentialScopeNote) {
      credentialScopeNote.textContent = queueOnly
        ? "私有签名队列可以产生“待重试”。"
        : "“待重试”仅用于应用私有签名队列。";
    }
    if (!queueOnly && state.credential === "retryPending") state.credential = "verified";
    updatePressed(SELECTORS.credentialControl, ["tapShareCredential", "credential"], state.credential);
  }

  function resourceSubtitleCopy() {
    if (state.media === "livePhoto") return "正在下载原始照片与配对视频";
    if (state.media === "video") return "正在下载完整原始视频";
    return "正在下载原始照片";
  }

  function cancelAttempt(close = true, reason = "share.cancelled") {
    clearTimers();
    state.attempt += 1;
    state.progress = 0;
    state.selectedOption = null;
    state.systemActivityBoundaryReached = false;
    trigger.classList.remove("is-preparing");
    if (close) showPanel("closed", reason);
  }

  function renderResourceState(reason = "resource.rendered") {
    const loading = state.resource === "iCloudLoading";
    const unavailable = state.resource === "iCloudUnavailable";
    const ready = isResourceReady();
    resourceOverlay.hidden = ready;
    resourceWarningIcon.hidden = !unavailable;
    resourceProgressRow.hidden = !loading;
    resourceProgress.max = 1;
    resourceProgress.value = 0.64;
    resourceProgressLabel.textContent = "64%";
    resourceTitle.textContent = unavailable
      ? "原始资源暂不可用"
      : "正在从 iCloud 下载原始资源";
    resourceSubtitle.textContent = unavailable
      ? "连接 iCloud 后重试；认证状态尚未判定"
      : resourceSubtitleCopy();
    if ("disabled" in trigger) trigger.disabled = !ready;
    trigger.setAttribute("aria-disabled", String(!ready));
    trigger.setAttribute("aria-busy", String(loading));
    trigger.setAttribute("aria-label", loading
      ? "Share unavailable, downloading original resource, 64 percent"
      : unavailable
        ? "Share unavailable, original resource unavailable"
        : "Share");
    resourceShareStatus.textContent = loading
      ? "正在从 iCloud 下载完整原始资源，分享暂不可用，进度百分之六十四。"
      : unavailable
        ? "完整原始资源暂不可用，分享暂不可用。"
        : "原始资源已就绪，可以分享。";
    if (!ready && state.panel !== "closed") cancelAttempt(true, "resource.unavailable");
    publish(reason);
  }

  function optionRows() {
    const isVideo = state.media === "video";
    const verified = state.credential === "verified";
    const failed = state.credential === "failed";
    const retryPending = state.credential === "retryPending";
    const ordinaryWarning = failed
      ? "无法保证可验证性"
      : retryPending
        ? "签名待重试，无法保证可验证性"
        : "";
    const primary = isVideo
      ? { id: "video", icon: "video-camera.svg", title: "分享视频", subtitle: ordinaryWarning || "分享原始 TAP Video", badge: "" }
      : { id: "tapnapPackage", icon: "package.svg", title: "TAPNAP 包", subtitle: verified ? "完整资料，可供验证" : failed ? "本地完整性检查未通过" : "签名尚未完成", badge: "推荐", disabled: !verified };
    const secondary = isVideo
      ? { id: "videoPackage", icon: "package.svg", title: "TAPNAP 包", subtitle: "视频传输外壳尚未实现", badge: "即将推出", disabled: true }
      : { id: "image", icon: "images.svg", title: "分享图片", subtitle: ordinaryWarning ? `${ordinaryWarning}；可能损失元数据` : "可能损失元数据", badge: "" };
    return [
      ...(isVideo ? [secondary, primary] : [primary, secondary]),
      { id: "sticker", icon: "smiley.svg", title: "3D 表情", subtitle: "点云轨迹与 GIF 尚未实现", badge: "即将推出", disabled: true },
      { id: "link", icon: "link.svg", title: "分享链接", subtitle: "会员功能尚未实现", badge: "会员 · 即将推出", disabled: true }
    ];
  }

  function renderSelector({ preservePanel = false } = {}) {
    const credentialMap = {
      verified: ["已验证", "check-circle.svg", "var(--green)"],
      retryPending: ["待重试", "arrows-clockwise.svg", "var(--orange)"],
      failed: ["失败", "x-circle.svg", "var(--red)"]
    };
    const [label, icon, tint] = credentialMap[state.credential];
    credentialLabel.textContent = label;
    credentialIcon.style.setProperty("--icon", `url(assets/icons/${icon})`);
    credentialIcon.style.color = tint;
    credentialLabel.style.color = tint;
    const preparing = state.panel === "preparing";
    options.replaceChildren(...optionRows().map((option) => {
      const selected = preparing && option.id === state.selectedOption;
      const row = ownerDocument.createElement("div");
      row.className = `share-option-row${selected ? " is-preparing" : ""}`;
      const button = ownerDocument.createElement("button");
      button.type = "button";
      button.className = "share-option";
      button.disabled = preparing || Boolean(option.disabled);
      button.dataset.option = option.id;
      button.setAttribute("aria-busy", String(selected));
      const subtitleContent = selected
        ? `<progress id="progress-bar" data-tap-share-progress class="subtitle-progress-track" max="1" value="${state.progress}" aria-label="${option.title}准备进度"></progress>`
        : option.subtitle;
      button.innerHTML = `<img src="assets/icons/${option.icon}" alt=""><span class="share-option-copy"><strong>${option.title}</strong><small>${subtitleContent}</small></span><span class="badge">${option.badge}</span>`;
      row.append(button);
      return row;
    }));
    mediaChip.textContent = state.media === "livePhoto" ? "LIVE" : state.media.toUpperCase();
    if (!preservePanel) showPanel("selector", "integrity.resolved");
  }

  function resolveIntegrity(attempt = state.attempt) {
    if (destroyed || attempt !== state.attempt || state.panel !== "integrityChecking") return;
    renderSelector();
  }

  function beginIntegrityCheck() {
    ensureActive();
    if (!isResourceReady()) return snapshot();
    cancelAttempt(false);
    const attempt = ++state.attempt;
    showPanel("integrityChecking", "integrity.started");
    if (state.integrityFixture === "auto") {
      later(() => resolveIntegrity(attempt), INTEGRITY_FIXTURE_DURATIONS.auto);
    }
    return snapshot();
  }

  function complete(attempt) {
    if (destroyed || attempt !== state.attempt) return;
    setProgress(1);
    clearTimers();
    state.attempt += 1;
    state.selectedOption = null;
    state.systemActivityBoundaryReached = true;
    showPanel("closed", "payload.ready.systemBoundaryReached");
  }

  function prepare(option) {
    ensureActive();
    cancelAttempt(false);
    const attempt = ++state.attempt;
    state.selectedOption = option;
    state.progress = 0;
    state.systemActivityBoundaryReached = false;

    showPanel("preparing", "preparation.started");
    renderSelector({ preservePanel: true });
    setProgress(0);

    const duration = FIXTURE_DURATIONS[state.fixture];
    [0.12, 0.32, 0.58, 0.82].forEach((progress, index) => {
      later(() => attempt === state.attempt && state.panel === "preparing" && setProgress(progress), duration * ((index + 1) / 5));
    });
    later(() => {
      if (attempt !== state.attempt) return;
      if (state.fixture === "failure") showPanel("failure", "preparation.failed");
      else complete(attempt);
    }, duration);
    return snapshot();
  }

  function bind(node, type, listener) {
    node.addEventListener(type, listener);
    listenerCleanups.push(() => node.removeEventListener(type, listener));
  }

  bind(trigger, "click", (event) => {
    event.preventDefault();
    if (destroyed || ("disabled" in trigger && trigger.disabled)) return;
    if (state.panel === "closed") beginIntegrityCheck();
    else cancelAttempt(true);
  });
  bind(options, "click", (event) => {
    const button = event.target.closest("[data-option]");
    if (!button || !options.contains(button) || button.disabled) return;
    prepare(button.dataset.option);
  });

  if (resolveIntegrityButton) bind(resolveIntegrityButton, "click", () => resolveIntegrity());
  bind(failureCancelButton, "click", () => {
    cancelAttempt(false);
    renderSelector();
  });
  bind(retryButton, "click", () => state.selectedOption && prepare(state.selectedOption));

  root.querySelectorAll(SELECTORS.mediaControl).forEach((button) => bind(button, "click", () => {
    const value = hookValue(button, ["tapShareMedia", "media"]);
    if (!value) return;
    state.media = value;
    updatePressed(SELECTORS.mediaControl, ["tapShareMedia", "media"], state.media);
    renderResourceState("media.changed");
    if (state.panel !== "closed") beginIntegrityCheck();
  }));

  root.querySelectorAll(SELECTORS.resourceControl).forEach((button) => bind(button, "click", () => {
    const value = hookValue(button, ["tapShareResource", "resource"]);
    if (!value) return;
    state.resource = value;
    updatePressed(SELECTORS.resourceControl, ["tapShareResource", "resource"], state.resource);
    updateCredentialControls();
    if (state.panel !== "closed") cancelAttempt(true);
    renderResourceState("resource.changed");
  }));

  root.querySelectorAll(SELECTORS.credentialControl).forEach((button) => bind(button, "click", () => {
    if (button.disabled) return;
    const value = hookValue(button, ["tapShareCredential", "credential"]);
    if (!value) return;
    state.credential = value;
    updatePressed(SELECTORS.credentialControl, ["tapShareCredential", "credential"], state.credential);
    if (state.panel !== "closed") beginIntegrityCheck();
    else publish("credential.changed");
  }));

  root.querySelectorAll(SELECTORS.integrityFixtureControl).forEach((button) => bind(button, "click", () => {
    const value = hookValue(button, ["tapShareIntegrityFixture", "integrityFixture"]);
    if (!value) return;
    state.integrityFixture = value;
    updatePressed(SELECTORS.integrityFixtureControl, ["tapShareIntegrityFixture", "integrityFixture"], state.integrityFixture);
    publish("integrityFixture.changed");
  }));

  root.querySelectorAll(SELECTORS.preparationFixtureControl).forEach((button) => bind(button, "click", () => {
    const value = hookValue(button, ["tapSharePreparationFixture", "fixture"]);
    if (!value) return;
    state.fixture = value;
    updatePressed(SELECTORS.preparationFixtureControl, ["tapSharePreparationFixture", "fixture"], state.fixture);
    publish("preparationFixture.changed");
  }));

  function close() {
    if (destroyed) return snapshot();
    cancelAttempt(true, "share.closed");
    return snapshot();
  }

  function destroy() {
    if (destroyed) return snapshot();
    clearTimers();
    state.attempt += 1;
    state.progress = 0;
    state.selectedOption = null;
    state.panel = "closed";
    popover.hidden = true;
    trigger.setAttribute("aria-expanded", "false");
    trigger.classList.remove("is-preparing");
    for (const cleanup of listenerCleanups.splice(0)) cleanup();
    destroyed = true;
    activeMounts.delete(root);
    publish("destroyed");
    return snapshot();
  }

  updatePressed(SELECTORS.mediaControl, ["tapShareMedia", "media"], state.media);
  updatePressed(SELECTORS.resourceControl, ["tapShareResource", "resource"], state.resource);
  updatePressed(SELECTORS.integrityFixtureControl, ["tapShareIntegrityFixture", "integrityFixture"], state.integrityFixture);
  updatePressed(SELECTORS.preparationFixtureControl, ["tapSharePreparationFixture", "fixture"], state.fixture);
  updateCredentialControls();
  showPanel("closed", "mounted");
  renderResourceState("mounted");

  const api = Object.freeze({
    open: beginIntegrityCheck,
    close,
    destroy,
    snapshot
  });
  activeMounts.set(root, api);
  return api;
}
