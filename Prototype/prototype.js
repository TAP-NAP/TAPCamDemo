(() => {
  "use strict";

  const byID = (id) => document.getElementById(id);

  const state = {
    flow: "share",
    startup: "preparing",
    media: "photo",
    resource: "localReady",
    credential: "verified",
    integrityFixture: "auto",
    fixture: "slow",
    panel: "closed",
    progress: 0,
    selectedOption: null,
    attempt: 0,
    attemptStartedAt: 0,
    timers: new Set(),
    progressWasVisible: false,
    progressVisibleAt: 0
  };

  const shareControls = document.querySelector(".share-controls");
  const startupControls = document.querySelector(".startup-controls");
  const startupInitialization = byID("startup-initialization");
  const startupEntryBoundary = byID("startup-entry-boundary");
  const shareFlowScreen = byID("share-flow-screen");
  const startupSpinner = byID("startup-spinner");
  const startupCameraCheck = byID("startup-camera-check");
  const startupLibraryCheck = byID("startup-library-check");
  const flowTaskLabel = byID("flow-task-label");
  const flowDescription = byID("flow-description");

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
    const isStartup = state.flow === "startup";
    flowTaskLabel.textContent = isStartup ? "TAP-0006 · TAP-0009" : "TAP-0006 · TAP-0081";
    flowDescription.textContent = isStartup
      ? "Review the Resource Initialization shown on the first launch after installation, reinstallation, or an app update. It completes before the interactive camera; ordinary repeated launches skip it."
      : "Review the app-owned TAP Share selection and preparation flow. The system activity controller remains a documented boundary.";
    startupInitialization.hidden = !isStartup;
    startupEntryBoundary.hidden = true;
    shareFlowScreen.hidden = isStartup;
    startupControls.hidden = !isStartup;
    shareControls.hidden = isStartup;
    if (isStartup) renderStartupState();
    else renderResourceState();
    exposeState();
  }

  const panels = [...document.querySelectorAll("[data-panel]")];
  const shareButton = byID("share-button");
  const popover = byID("share-popover");
  const options = byID("share-options");
  const progressBar = byID("progress-bar");
  const progressLabel = byID("progress-label");
  const resourceOverlay = byID("resource-overlay");
  const resolveIntegrityButton = byID("resolve-integrity-button");

  const policy = Object.freeze({ revealDelayMs: 50, minimumVisibleMs: 400 });
  const fixtureDurations = Object.freeze({ fast: 35, threshold: 120, slow: 1400, failure: 720 });
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
    document.documentElement.dataset.startupFixture = state.startup;
    document.documentElement.dataset.media = state.media;
    document.documentElement.dataset.resource = state.resource;
    document.documentElement.dataset.credential = state.credential;
    document.documentElement.dataset.integrityFixture = state.integrityFixture;
    document.documentElement.dataset.fixture = state.fixture;
    document.documentElement.dataset.progressVisible = String(state.progressWasVisible);
    window.__tapSharePrototype = {
      snapshot: () => ({ ...state, timers: state.timers.size, policy }),
      policy
    };
  }

  function showPanel(name) {
    state.panel = name;
    popover.hidden = name === "closed";
    shareButton.setAttribute("aria-expanded", String(name !== "closed"));
    for (const panel of panels) panel.hidden = panel.dataset.panel !== name;
    shareButton.classList.toggle("is-preparing", name === "preparing");
    resolveIntegrityButton.disabled = name !== "integrityChecking";
    if (name === "boundary" && state.attemptStartedAt > 0) {
      document.documentElement.dataset.boundaryElapsedMs = String(Math.round(performance.now() - state.attemptStartedAt));
    }
    exposeState();
  }

  function setProgress(value) {
    state.progress = Math.max(state.progress, Math.min(1, Math.max(0, value)));
    progressBar.value = state.progress;
    progressLabel.value = `${Math.round(state.progress * 100)}%`;
    progressLabel.textContent = progressLabel.value;
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

  function renderSelector() {
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
    options.replaceChildren(...optionRows().map((option) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "share-option";
      button.disabled = Boolean(option.disabled);
      button.dataset.option = option.id;
      button.innerHTML = `<img src="assets/icons/${option.icon}" alt=""><span><strong>${option.title}</strong><small>${option.subtitle}</small></span><span class="badge">${option.badge}</span>`;
      if (!button.disabled) button.addEventListener("click", () => prepare(option.id));
      return button;
    }));
    byID("media-chip").textContent = state.media === "livePhoto" ? "LIVE" : state.media.toUpperCase();
    showPanel("selector");
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
    if (state.progressWasVisible) {
      setProgress(1);
      const elapsed = performance.now() - state.progressVisibleAt;
      later(() => attempt === state.attempt && showPanel("boundary"), Math.max(0, policy.minimumVisibleMs - elapsed));
    } else {
      showPanel("boundary");
    }
  }

  function prepare(option) {
    cancelAttempt(false);
    const attempt = ++state.attempt;
    state.attemptStartedAt = performance.now();
    document.documentElement.dataset.progressRevealElapsedMs = "";
    document.documentElement.dataset.boundaryElapsedMs = "";
    state.selectedOption = option;
    state.progress = 0;
    state.progressWasVisible = false;
    progressBar.value = 0;
    progressLabel.value = "0%";
    progressLabel.textContent = "0%";
    const packageOption = option === "tapnapPackage" || option === "videoPackage";
    byID("preparing-title").textContent = packageOption ? "正在准备 TAPNAP 包" : state.media === "video" ? "正在准备视频" : "正在准备图片";
    byID("preparing-subtitle").textContent = packageOption ? "正在打包完整验证资料" : "正在复制所选原始媒体";

    later(() => {
      if (attempt !== state.attempt || state.fixture === "fast") return;
      state.progressWasVisible = true;
      state.progressVisibleAt = performance.now();
      document.documentElement.dataset.progressRevealElapsedMs = String(Math.round(state.progressVisibleAt - state.attemptStartedAt));
      showPanel("preparing");
      setProgress(.08);
    }, policy.revealDelayMs);

    const duration = fixtureDurations[state.fixture];
    if (state.fixture !== "fast") {
      [0.24, 0.49, 0.71, 0.9].forEach((progress, index) => {
        later(() => attempt === state.attempt && state.panel === "preparing" && setProgress(progress), duration * ((index + 1) / 5));
      });
    }
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
    state.progressWasVisible = false;
    state.selectedOption = null;
    shareButton.classList.remove("is-preparing");
    if (close) showPanel("closed");
  }

  shareButton.addEventListener("click", () => {
    if (state.panel === "closed") beginIntegrityCheck();
    else cancelAttempt(true);
  });
  document.querySelectorAll("[data-flow]").forEach((button) => button.addEventListener("click", () => {
    clearTimers();
    if (button.dataset.flow === "startup" && state.panel !== "closed") cancelAttempt(true);
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
  resolveIntegrityButton.addEventListener("click", () => resolveIntegrity());
  byID("cancel-button").addEventListener("click", () => { cancelAttempt(false); renderSelector(); });
  byID("failure-cancel").addEventListener("click", () => { cancelAttempt(false); renderSelector(); });
  byID("retry-button").addEventListener("click", () => state.selectedOption && prepare(state.selectedOption));
  byID("return-button").addEventListener("click", () => { cancelAttempt(false); renderSelector(); });

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
  renderResourceState();
  renderFlow();
  exposeState();
})();
