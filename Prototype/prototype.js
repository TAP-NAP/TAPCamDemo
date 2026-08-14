(() => {
  "use strict";

  const byID = (id) => document.getElementById(id);

  const state = {
    flow: "share",
    setup: "untouched",
    setupStatuses: null,
    setupBoundary: null,
    setupGuidance: "",
    setupWarning: false,
    startup: "preparing",
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

  const reviewQuery = new URLSearchParams(window.location.search);
  const requestedFlow = reviewQuery.get("flow");
  if (["share", "setup", "startup"].includes(requestedFlow)) state.flow = requestedFlow;
  const bridgeSource = reviewQuery.get("source");
  const resumeKey = reviewQuery.get("resumeKey");
  const bridgeMode = reviewQuery.get("viewerMode");
  const returnToLifecycle = byID("return-to-lifecycle");
  const viewerBackReference = byID("viewer-back-reference");
  if (bridgeSource === "tap0087" && /^[a-z0-9-]{12,80}$/i.test(resumeKey || "")) {
    returnToLifecycle.href = `startup-lifecycle.html?resumeKey=${encodeURIComponent(resumeKey)}`;
    returnToLifecycle.hidden = false;
    viewerBackReference.hidden = true;
    if (bridgeMode === "raw") {
      document.querySelectorAll(".viewer-toolbar .mode-capsule button").forEach((button) => {
        button.classList.toggle("selected", button.textContent.trim() === "RAW");
      });
    }
  }

  const shareControls = document.querySelector(".share-controls");
  const setupControls = document.querySelector(".setup-controls");
  const startupControls = document.querySelector(".startup-controls");
  const firstInstallSetup = byID("first-install-setup");
  const startupInitialization = byID("startup-initialization");
  const startupEntryBoundary = byID("startup-entry-boundary");
  const shareFlowScreen = byID("share-flow-screen");
  const startupSpinner = byID("startup-spinner");
  const startupCameraCheck = byID("startup-camera-check");
  const startupLibraryCheck = byID("startup-library-check");
  const flowTaskLabel = byID("flow-task-label");
  const flowDescription = byID("flow-description");

  const setupFixtures = Object.freeze({
    untouched: {
      statuses: { network: "idle", camera: "idle", photos: "idle", location: "idle", microphone: "idle" },
      guidance: "请先完成网络、相机与照片图库访问。位置与麦克风为可选项。"
    },
    cameraRequesting: {
      statuses: { network: "idle", camera: "requesting", photos: "idle", location: "idle", microphone: "idle" },
      guidance: "只有点击相机行的“允许”后，iOS 相机权限页才会接管。",
      boundary: "camera"
    },
    networkFailed: {
      statuses: { network: "denied", camera: "granted", photos: "granted", location: "skipped", microphone: "skipped" },
      guidance: "网络访问检查失败。请检查连接，然后在网络行重试。",
      warning: true
    },
    requiredReady: {
      statuses: { network: "granted", camera: "granted", photos: "granted", location: "skipped", microphone: "skipped" },
      guidance: "必要设置已完成。点击继续后进入独立的资源初始化阶段。"
    }
  });

  const setupLabels = Object.freeze({
    network: "网络访问", camera: "相机访问", photos: "照片图库访问", location: "位置访问", microphone: "麦克风访问"
  });

  function copySetupStatuses(statuses) {
    return { ...statuses };
  }

  function resetSetupFixture() {
    const fixture = setupFixtures[state.setup];
    state.setupStatuses = copySetupStatuses(fixture.statuses);
    state.setupBoundary = fixture.boundary || null;
    state.setupGuidance = fixture.guidance;
    state.setupWarning = Boolean(fixture.warning);
  }

  function setupRequiredReady() {
    return ["network", "camera", "photos"].every((key) => state.setupStatuses[key] === "granted");
  }

  function renderSetupRow(key) {
    const row = document.querySelector(`[data-setup-row="${key}"]`);
    const actions = row.querySelector(".setup-actions");
    const status = state.setupStatuses[key];
    if (status === "idle") {
      actions.innerHTML = `<button type="button" data-setup-action="${key}">允许</button>${key === "location" || key === "microphone" ? `<button type="button" data-setup-skip="${key}">跳过</button>` : ""}`;
      return;
    }
    const statusPresentation = {
      granted: ["✓", "setup-status", "已完成"],
      skipped: ["−", "setup-status is-skipped", "已跳过"],
      requesting: ["", "setup-status is-requesting", "正在请求"],
      denied: ["!", "setup-status is-denied", "需要处理"]
    }[status];
    actions.innerHTML = `<span class="${statusPresentation[1]}" role="img" aria-label="${statusPresentation[2]}">${statusPresentation[0]}</span>${status === "denied" && key === "network" ? `<button type="button" data-setup-action="network">重试</button>` : ""}`;
  }

  function renderSetupState() {
    if (!state.setupStatuses) resetSetupFixture();
    Object.keys(setupLabels).forEach(renderSetupRow);
    const requiredReady = setupRequiredReady();
    const guidance = byID("setup-guidance");
    guidance.textContent = state.setupGuidance;
    guidance.classList.toggle("is-warning", state.setupWarning);
    byID("setup-continue").disabled = !requiredReady;
    const boundary = byID("system-boundary-note");
    boundary.hidden = !state.setupBoundary;
    if (state.setupBoundary) {
      byID("system-boundary-copy").textContent = `点击“允许”后，${setupLabels[state.setupBoundary]}才由 ${state.setupBoundary === "network" ? "TAPCam 网络预检" : "iOS 系统权限页"}接管；此原型只记录接管前后的应用状态，不仿制系统界面。`;
    }
    byID("setup-announcement").textContent = state.setupBoundary
      ? `${setupLabels[state.setupBoundary]}由用户点击允许后开始。`
      : state.setupGuidance;
    exposeState();
  }

  const startupFixtures = Object.freeze({
    preparing: {
      title: "资源初始化", subtitle: "请等待…", camera: ["loading", "正在准备首个预览画面"], library: ["loading", "正在建立媒体目录"], spinner: true
    },
    cameraReadyCatalogPending: {
      title: "资源初始化", subtitle: "请等待…", camera: ["ready", "首个预览画面与相机控制已就绪"], library: ["loading", "正在建立媒体目录"], spinner: true
    },
    catalogReadyCameraPending: {
      title: "资源初始化", subtitle: "请等待…", camera: ["loading", "正在准备首个预览画面"], library: ["ready", "首个媒体目录已建立"], spinner: true
    },
    readyHandoff: {
      title: "资源初始化完成", subtitle: "正在进入相机…", camera: ["ready", "首个预览画面与相机控制已就绪"], library: ["ready", "首个媒体目录已建立"], spinner: false, handoff: true
    }
  });

  function setStartupCheck(element, stateName, detail) {
    element.classList.toggle("is-ready", stateName === "ready");
    element.classList.toggle("is-failed", stateName === "failed");
    element.querySelector("small").textContent = detail;
  }

  function renderStartupState() {
    const fixture = startupFixtures[state.startup];
    startupInitialization.hidden = false;
    startupEntryBoundary.hidden = true;
    startupSpinner.hidden = !fixture.spinner;
    byID("startup-title").textContent = fixture.title;
    byID("startup-subtitle").textContent = fixture.subtitle;
    byID("startup-announcement").textContent = `${fixture.title}。${fixture.subtitle}`;
    setStartupCheck(startupCameraCheck, ...fixture.camera);
    setStartupCheck(startupLibraryCheck, ...fixture.library);
    if (fixture.handoff) {
      const expectedFixture = state.startup;
      later(() => {
        if (state.flow !== "startup" || state.startup !== expectedFixture) return;
        startupInitialization.hidden = true;
        startupEntryBoundary.hidden = false;
        byID("startup-announcement").textContent = "资源初始化完成，正在进入相机。";
        exposeState();
      }, 700);
    }
  }

  function renderFlow() {
    const isSetup = state.flow === "setup";
    const isStartup = state.flow === "startup";
    flowTaskLabel.textContent = isSetup ? "TAP-0006 · TAP-0008" : isStartup ? "TAP-0006 · TAP-0009" : "TAP-0006 · TAP-0081";
    flowDescription.textContent = isSetup
      ? "Review the first-install setup page. Entering or foregrounding the page only refreshes status; every permission request and network preflight begins after its own explicit button action."
      : isStartup
        ? "Review the Resource Initialization shown on the first launch after installation, reinstallation, or an app update. It completes before the interactive camera; ordinary repeated launches skip it."
        : "Review the app-owned TAP Share selection and preparation flow. The system activity controller remains a documented boundary.";
    firstInstallSetup.hidden = !isSetup;
    startupInitialization.hidden = !isStartup;
    startupEntryBoundary.hidden = true;
    shareFlowScreen.hidden = isSetup || isStartup;
    setupControls.hidden = !isSetup;
    startupControls.hidden = !isStartup;
    shareControls.hidden = isSetup || isStartup;
    if (isSetup) renderSetupState();
    else if (isStartup) renderStartupState();
    else renderResourceState();
    exposeState();
  }

  const panels = [...document.querySelectorAll("[data-panel]")];
  const shareButton = byID("share-button");
  const popover = byID("share-popover");
  const options = byID("share-options");
  const resourceOverlay = byID("resource-overlay");
  const resolveIntegrityButton = byID("resolve-integrity-button");

  const policy = Object.freeze({
    progressPresentation: "immediate",
    minimumVisibleHold: false,
    payloadReadyBehavior: "closeAppPopover",
    systemActivitySimulation: false
  });
  const fixtureDurations = Object.freeze({ success: 1400, failure: 720 });
  const integrityFixtureDurations = Object.freeze({ auto: 650 });
  const readyResources = new Set(["localReady", "iCloudReady", "privateQueue"]);

  function later(callback, delay) {
    const timer = window.setTimeout(() => {
      state.timers.delete(timer);
      callback();
    }, delay);
    state.timers.add(timer);
  }

  function clearTimers() {
    for (const timer of state.timers) window.clearTimeout(timer);
    state.timers.clear();
  }

  function exposeState() {
    document.documentElement.dataset.prototypeState = state.panel;
    document.documentElement.dataset.prototypeFlow = state.flow;
    document.documentElement.dataset.setupFixture = state.setup;
    document.documentElement.dataset.startupFixture = state.startup;
    document.documentElement.dataset.media = state.media;
    document.documentElement.dataset.resource = state.resource;
    document.documentElement.dataset.credential = state.credential;
    document.documentElement.dataset.integrityFixture = state.integrityFixture;
    document.documentElement.dataset.fixture = state.fixture;
    document.documentElement.dataset.progressVisible = String(state.panel === "preparing");
    document.documentElement.dataset.systemActivityBoundary = state.systemActivityBoundaryReached ? "reached" : "notReached";
    window.__tapSharePrototype = {
      snapshot: () => ({ ...state, timers: state.timers.size, policy }),
      policy
    };
  }

  function showPanel(name) {
    state.panel = name;
    const visiblePanel = name === "preparing" ? "selector" : name;
    popover.hidden = name === "closed";
    shareButton.setAttribute("aria-expanded", String(name !== "closed"));
    for (const panel of panels) panel.hidden = panel.dataset.panel !== visiblePanel;
    shareButton.classList.toggle("is-preparing", name === "preparing");
    resolveIntegrityButton.disabled = name !== "integrityChecking";
    exposeState();
  }

  function setProgress(value) {
    state.progress = Math.max(state.progress, Math.min(1, Math.max(0, value)));
    const progressBar = byID("progress-bar");
    if (progressBar) {
      progressBar.value = state.progress;
    }
    exposeState();
  }

  function isResourceReady() {
    return readyResources.has(state.resource);
  }

  function updateCredentialControls() {
    const retryButton = document.querySelector('[data-credential="retryPending"]');
    const queueOnly = state.resource === "privateQueue";
    retryButton.disabled = !queueOnly;
    byID("credential-scope-note").textContent = queueOnly
      ? "私有签名队列可以产生“待重试”。"
      : "“待重试”仅用于应用私有签名队列。";
    if (!queueOnly && state.credential === "retryPending") {
      state.credential = "verified";
    }
    document.querySelectorAll("[data-credential]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.credential === state.credential));
    });
  }

  function resourceSubtitle() {
    if (state.media === "livePhoto") return "正在下载原始照片与配对视频";
    if (state.media === "video") return "正在下载完整原始视频";
    return "正在下载原始照片";
  }

  function renderResourceState() {
    const loading = state.resource === "iCloudLoading";
    const unavailable = state.resource === "iCloudUnavailable";
    const ready = isResourceReady();
    resourceOverlay.hidden = ready;
    byID("resource-warning-icon").hidden = !unavailable;
    byID("resource-progress-row").hidden = !loading;
    byID("resource-title").textContent = unavailable
      ? "原始资源暂不可用"
      : "正在从 iCloud 下载原始资源";
    byID("resource-subtitle").textContent = unavailable
      ? "连接 iCloud 后重试；认证状态尚未判定"
      : resourceSubtitle();
    shareButton.disabled = !ready;
    shareButton.setAttribute("aria-disabled", String(!ready));
    shareButton.setAttribute("aria-busy", String(loading));
    shareButton.setAttribute("aria-label", loading
      ? "Share unavailable, downloading original resource, 64 percent"
      : unavailable
        ? "Share unavailable, original resource unavailable"
        : "Share");
    byID("resource-share-status").textContent = loading
      ? "正在从 iCloud 下载完整原始资源，分享暂不可用，进度百分之六十四。"
      : unavailable
        ? "完整原始资源暂不可用，分享暂不可用。"
        : "原始资源已就绪，可以分享。";
    if (!ready && state.panel !== "closed") cancelAttempt(true);
    exposeState();
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
    byID("credential-label").textContent = label;
    byID("credential-icon").style.setProperty("--icon", `url(assets/icons/${icon})`);
    byID("credential-icon").style.color = tint;
    byID("credential-label").style.color = tint;
    const preparing = state.panel === "preparing";
    options.replaceChildren(...optionRows().map((option) => {
      const selected = preparing && option.id === state.selectedOption;
      const row = document.createElement("div");
      row.className = `share-option-row${selected ? " is-preparing" : ""}`;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "share-option";
      button.disabled = preparing || Boolean(option.disabled);
      button.dataset.option = option.id;
      button.setAttribute("aria-busy", String(selected));
      const subtitleContent = selected
        ? `<progress id="progress-bar" class="subtitle-progress-track" max="1" value="${state.progress}" aria-label="${option.title}准备进度"></progress>`
        : option.subtitle;
      button.innerHTML = `<img src="assets/icons/${option.icon}" alt=""><span class="share-option-copy"><strong>${option.title}</strong><small>${subtitleContent}</small></span><span class="badge">${option.badge}</span>`;
      if (!button.disabled) button.addEventListener("click", () => prepare(option.id));
      row.append(button);
      return row;
    }));
    byID("media-chip").textContent = state.media === "livePhoto" ? "LIVE" : state.media.toUpperCase();
    if (!preservePanel) showPanel("selector");
  }

  function resolveIntegrity(attempt = state.attempt) {
    if (attempt !== state.attempt || state.panel !== "integrityChecking") return;
    renderSelector();
  }

  function beginIntegrityCheck() {
    if (!isResourceReady()) return;
    cancelAttempt(false);
    const attempt = ++state.attempt;
    showPanel("integrityChecking");
    if (state.integrityFixture === "auto") {
      later(() => resolveIntegrity(attempt), integrityFixtureDurations.auto);
    }
    exposeState();
  }

  function complete(attempt) {
    if (attempt !== state.attempt) return;
    setProgress(1);
    clearTimers();
    state.attempt += 1;
    state.selectedOption = null;
    state.systemActivityBoundaryReached = true;
    showPanel("closed");
  }

  function prepare(option) {
    cancelAttempt(false);
    const attempt = ++state.attempt;
    state.selectedOption = option;
    state.progress = 0;
    state.systemActivityBoundaryReached = false;

    showPanel("preparing");
    renderSelector({ preservePanel: true });
    setProgress(0);

    const duration = fixtureDurations[state.fixture];
    [0.12, 0.32, 0.58, 0.82].forEach((progress, index) => {
      later(() => attempt === state.attempt && state.panel === "preparing" && setProgress(progress), duration * ((index + 1) / 5));
    });
    later(() => {
      if (attempt !== state.attempt) return;
      if (state.fixture === "failure") {
        showPanel("failure");
      } else {
        complete(attempt);
      }
    }, duration);
    exposeState();
  }

  function cancelAttempt(close = true) {
    clearTimers();
    state.attempt += 1;
    state.progress = 0;
    state.selectedOption = null;
    state.systemActivityBoundaryReached = false;
    shareButton.classList.remove("is-preparing");
    if (close) showPanel("closed");
  }

  shareButton.addEventListener("click", () => {
    if (state.panel === "closed") beginIntegrityCheck();
    else cancelAttempt(true);
  });
  document.querySelectorAll("[data-flow]").forEach((button) => button.addEventListener("click", () => {
    clearTimers();
    if (button.dataset.flow !== "share" && state.panel !== "closed") cancelAttempt(true);
    state.flow = button.dataset.flow;
    document.querySelectorAll("[data-flow]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    renderFlow();
  }));
  document.querySelectorAll("[data-startup]").forEach((button) => button.addEventListener("click", () => {
    clearTimers();
    state.startup = button.dataset.startup;
    document.querySelectorAll("[data-startup]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    renderStartupState();
    exposeState();
  }));
  document.querySelectorAll("[data-setup]").forEach((button) => button.addEventListener("click", () => {
    clearTimers();
    state.setup = button.dataset.setup;
    resetSetupFixture();
    document.querySelectorAll("[data-setup]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    renderSetupState();
  }));
  firstInstallSetup.addEventListener("click", (event) => {
    const actionButton = event.target.closest("[data-setup-action]");
    const skipButton = event.target.closest("[data-setup-skip]");
    if (actionButton) {
      const key = actionButton.dataset.setupAction;
      state.setupStatuses[key] = "requesting";
      state.setupBoundary = key;
      state.setupGuidance = `${setupLabels[key]}正在等待${key === "network" ? "预检结果" : "系统授权结果"}。`;
      state.setupWarning = false;
      renderSetupState();
      later(() => {
        if (state.flow !== "setup" || state.setupStatuses[key] !== "requesting") return;
        state.setupStatuses[key] = "granted";
        state.setupBoundary = null;
        state.setupGuidance = setupRequiredReady()
          ? "必要设置已完成。点击继续后进入独立的资源初始化阶段。"
          : `${setupLabels[key]}已完成；其余项目仍等待你的明确操作。`;
        renderSetupState();
      }, 900);
      return;
    }
    if (skipButton) {
      const key = skipButton.dataset.setupSkip;
      state.setupStatuses[key] = "skipped";
      state.setupBoundary = null;
      state.setupGuidance = `${setupLabels[key]}已跳过；这不会触发系统权限页。`;
      state.setupWarning = false;
      renderSetupState();
    }
  });
  byID("setup-continue").addEventListener("click", () => {
    if (!setupRequiredReady()) return;
    state.flow = "startup";
    document.querySelectorAll("[data-flow]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate.dataset.flow === "startup")));
    renderFlow();
  });
  resolveIntegrityButton.addEventListener("click", () => resolveIntegrity());
  byID("failure-cancel").addEventListener("click", () => { cancelAttempt(false); renderSelector(); });
  byID("retry-button").addEventListener("click", () => state.selectedOption && prepare(state.selectedOption));

  document.querySelectorAll("[data-media]").forEach((button) => button.addEventListener("click", () => {
    state.media = button.dataset.media;
    document.querySelectorAll("[data-media]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    renderResourceState();
    if (state.panel !== "closed") beginIntegrityCheck();
    exposeState();
  }));
  document.querySelectorAll("[data-resource]").forEach((button) => button.addEventListener("click", () => {
    state.resource = button.dataset.resource;
    document.querySelectorAll("[data-resource]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    updateCredentialControls();
    if (state.panel !== "closed") cancelAttempt(true);
    renderResourceState();
    exposeState();
  }));
  document.querySelectorAll("[data-credential]").forEach((button) => button.addEventListener("click", () => {
    if (button.disabled) return;
    state.credential = button.dataset.credential;
    document.querySelectorAll("[data-credential]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    if (state.panel !== "closed") beginIntegrityCheck();
    exposeState();
  }));
  document.querySelectorAll("[data-integrity-fixture]").forEach((button) => button.addEventListener("click", () => {
    state.integrityFixture = button.dataset.integrityFixture;
    document.querySelectorAll("[data-integrity-fixture]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    exposeState();
  }));
  document.querySelectorAll("[data-fixture]").forEach((button) => button.addEventListener("click", () => {
    state.fixture = button.dataset.fixture;
    document.querySelectorAll("[data-fixture]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    exposeState();
  }));

  updateCredentialControls();
  document.querySelectorAll("[data-flow]").forEach((candidate) => {
    candidate.setAttribute("aria-pressed", String(candidate.dataset.flow === state.flow));
  });
  renderResourceState();
  renderFlow();
  exposeState();
})();
