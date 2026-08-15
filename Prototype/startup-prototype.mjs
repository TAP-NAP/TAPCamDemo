import {
  REVISION,
  buildWorkloadInspectionJourney,
  canReduce,
  chooseRoute,
  createState,
  fix0809DispositionRegistry,
  fix0809OutcomeRegistry,
  initializationIdentityMatches,
  lifecycleTimingLaneRecordIDs,
  lifecycleTruthRegistry,
  machineRegistry,
  nextEvent,
  photosUsable,
  publicSnapshot,
  reduce,
  reviewStateRegistry,
  resolveWorkloadDifferenceTraceBinding,
  scenarioFixtures,
  setupRequiredReady,
  timelineRegistry,
  workloadDifferenceRegistry,
  workloadInspectionReached,
  workloadRegistry
} from "./startup-model.mjs";
import { mountTapShareSlice } from "./tap-share-slice.mjs";

const byID = (id) => document.getElementById(id);
const clone = (value) => JSON.parse(JSON.stringify(value));
const lifecycleTimingLaneRecordIDSet = new Set(lifecycleTimingLaneRecordIDs);

function fix0809DispositionFor(record) {
  return fix0809DispositionRegistry[record?.fix0809Disposition] || null;
}

function fix0809OutcomeFor(record) {
  return fix0809OutcomeRegistry[record?.fix0809Outcome] || null;
}

function reviewStateFor(record) {
  return reviewStateRegistry[record?.reviewState] || null;
}

function makeFix0809OutcomeBadge(record) {
  const outcome = fix0809OutcomeFor(record);
  if (!outcome) return null;
  const badge = document.createElement("span");
  badge.className = "fix0809-outcome";
  badge.dataset.fix0809Outcome = record.fix0809Outcome;
  badge.textContent = outcome.visibleLabel;
  return badge;
}

function makeFollowUpTaskBadge(record) {
  const reviewState = reviewStateFor(record);
  if (!reviewState || !record.followUpTaskIDs?.length) return null;
  const badge = document.createElement("span");
  badge.className = "follow-up-tasks";
  badge.dataset.reviewState = record.reviewState;
  badge.textContent = `${reviewState.taskLabel} ${record.followUpTaskIDs.join(" · ")}`;
  return badge;
}

function lifecycleProjectionAnchor(truth) {
  const reviewState = reviewStateFor(truth);
  return reviewState?.projectionMode === "mergeIntoTarget"
    ? truth.targetBinding.anchor
    : truth.actual.anchor;
}

const pageLabels = Object.freeze({
  dormant: "Dormant",
  systemLaunchScreen: "iOS Launch Screen",
  firstAppFrame: "First App Frame",
  firstInstallSetup: "First-Install Setup",
  requiredPermissionCheck: "Required Permission Check",
  resourceInitialization: "Resource Initialization",
  viewfinder: "Viewfinder",
  library: "TAP Library",
  photoViewer: "Photo Viewer"
});

const eventLabels = Object.freeze({
  ACTIVATION_REQUESTED: "Activation requested",
  APP_FIRST_FRAME_COMMITTED: "App-owned first frame committed",
  INITIAL_ROUTE_COMMITTED: "Initial route committed",
  SETUP_ATTESTATION_TAPPED: "Network row · start App Attest",
  SETUP_ATTESTATION_RETRY_TAPPED: "Network row · explicit App Attest retry",
  SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING: "Initial App Attest · bounded automatic retry wait",
  SETUP_ATTESTATION_TIMED_OUT: "Initial App Attest · explicit retry required",
  SETUP_ATTESTATION_COMPLETED: "Initial App Attest ready",
  NETWORK_BECAME_AVAILABLE: "Network became available",
  SETUP_PERMISSION_TAPPED: "Explicit permission action",
  SETUP_PERMISSION_RECOVERY_TAPPED: "Open Settings for denied Setup permission",
  SYSTEM_PERMISSION_RETURNED: "Returned from permission system boundary",
  SETUP_OPTIONAL_SKIPPED: "Optional permission skipped",
  SETUP_CONTINUE_TAPPED: "Setup receipt committed",
  PERMISSION_RECOVERY_TAPPED: "Required permission recovery requested",
  PERMISSIONS_RECHECKED: "Required permissions rechecked",
  CAMERA_DISCOVERY_STARTED: "Camera capability discovery started",
  CAMERA_SESSION_CONFIGURED: "Capture graph configured",
  CAMERA_PREVIEW_PRESENTED: "First real preview presented",
  CAMERA_INTERACTION_READY: "Viewfinder interaction ready",
  LIBRARY_CATALOG_STARTED: "Library catalog refresh started",
  LIBRARY_CATALOG_PUBLISHED: "First usable Library catalog published",
  DEFERRED_WORK_RELEASED: "Deferred work released",
  LIBRARY_OPENED: "TAP Library opened",
  LIBRARY_BACK_TAPPED: "Returned to Viewfinder",
  THUMBNAIL_BATCH_STARTED: "Visible thumbnails started",
  THUMBNAIL_BATCH_PUBLISHED: "Visible thumbnail batch published",
  PHOTO_OPENED: "Photo Viewer opened",
  VIEWER_DISPLAY_READY: "Bounded photo rendition ready",
  VIEWER_BACK_TAPPED: "Returned to TAP Library",
  SCENARIO_TERMINATED: "Scenario terminal reached",
  MEASUREMENT_PROFILE_CHANGED: "Measurement profile changed",
  SCENARIO_SELECTED: "Scenario selected"
});

const statusLabels = Object.freeze({
  dormant: "Dormant",
  eligible: "Eligible",
  scheduled: "Scheduled",
  waitingPrerequisite: "Waiting prerequisite",
  waitingSystem: "Waiting system",
  waitingNetwork: "Waiting network",
  running: "Running",
  succeeded: "Ready",
  failedRetryable: "Retry required",
  failedTerminal: "Terminal failure",
  cancelled: "Cancelled",
  stale: "Stale",
  skipped: "Deferred child task"
});

const alignmentLabels = Object.freeze({
  aligned: "Current = target",
  partial: "Partial alignment",
  gap: "Current gap",
  deferred: "Child task deferred"
});

const permissionLabels = Object.freeze({
  camera: "相机访问",
  photos: "照片图库访问",
  location: "位置访问",
  microphone: "麦克风访问"
});

const installationLabels = Object.freeze({
  freshInstallation: "Fresh Installation",
  inPlaceAppUpdate: "In-place App Update",
  developmentReplacementInstall: "Development Replacement Install",
  deleteAndReinstall: "Delete-and-Reinstall",
  offloadAndReinstall: "Offload-and-Reinstall",
  sameDeviceBackupRestore: "Same-Device Backup Restore",
  crossDeviceMigrationRestore: "Cross-Device Migration Restore",
  localStateInconsistency: "Local State Inconsistency",
  unchangedInstallation: "Unchanged Installation"
});

const activationLabels = Object.freeze({
  processLaunch: "Foreground Process Launch",
  foregroundResume: "Foreground Resume",
  settingsReturn: "Settings Return"
});

const reviewSurfaceCatalog = Object.freeze({
  systemLaunchScreen: {
    title: "Launch Screen",
    owner: "iOS · system-owned static boundary",
    summary: "只呈现静态 LaunchLogo / LaunchBackground。它不运行初始化、不显示进度，也不拥有消失时机。",
    operations: "选择启动场景并观察 t0 → t1；Foreground Resume / Settings Return 不会出现 Launch Screen。",
    relatedMachines: ["activation", "routeDecision"]
  },
  firstInstallSetup: {
    title: "First-Install Setup",
    owner: "TAPCam Startup · App Attest + permissions",
    summary: "Network 的明确动作完成首次 App Attest；Camera 与 Photos 同为必需，Location 与 Microphone 可跳过。",
    operations: "每个操作只驱动对应行；页面出现、前台恢复与 Continue 都不会代替明确动作。",
    relatedMachines: ["routeDecision", "firstInstallSetup", "appAttestCredential"]
  },
  requiredPermissionCheck: {
    title: "Required Permission Check",
    owner: "TAPCam Startup Router · Camera / Photos",
    summary: "只处理 Camera 或 Photos 的不可用状态。Network、Location 与 Microphone 不进入此页。",
    operations: "根据 notDetermined / denied / restricted 显示 Allow、Open Settings 或稳定受限状态；返回后重新读取事实。",
    relatedMachines: ["routeDecision", "requiredPermissionCheck"]
  },
  resourceInitialization: {
    title: "Resource Initialization",
    owner: "TAPCam Camera + TAP Library readiness",
    summary: "真实首个预览、安全交互、必需触觉与首个可用 Library catalog 共同控制 I marker 的原子提交。",
    operations: "按 Camera-first 或 Catalog-first 的合法 reducer 顺序推进；没有 Retry、Failed 或降级进入。",
    relatedMachines: ["routeDecision", "resourceInitialization", "cameraReadiness", "libraryCatalog"]
  },
  viewfinder: {
    title: "Viewfinder",
    owner: "TAPCam Camera · current-main source geometry",
    summary: "两行 top chrome、圆角内缩 preview、FOV chips 与独立 bottom controls 映射当前 SwiftUI 结构；只有真实预览与主交互安全后才成为 Interactive Viewfinder。",
    operations: "当前切片只开放 TAP Library 入口；Flash、Live、PRO、Settings、Shutter、Switch 与模式控制保持 TAP-0088 deferred。",
    relatedMachines: ["activation", "cameraReadiness", "appAttestCredential", "pendingCaptureRecovery", "viewfinderControls"]
  },
  library: {
    title: "TAP Library",
    owner: "TAP Library · catalog + visible thumbnails",
    summary: "先发布身份/顺序 catalog，再按可见单元加载缩略图；空 catalog 也是成功状态。",
    operations: "推进 catalog 与可见缩略图、打开照片，或返回 Viewfinder；离开时拒绝 stale publication。",
    relatedMachines: ["libraryCatalog", "thumbnailPipeline", "pendingCaptureRecovery"]
  },
  photoViewer: {
    title: "Photo Viewer",
    owner: "TAPCam Viewer",
    summary: "稳定 Viewer chrome 先出现，再完成 bounded rendition。2D/3D 保持 TAP-0089 deferred；TAP-0081 Share 作为同页、独立持有的 presentation 显示。",
    operations: "完成显示、返回 Library，或打开同页 TAP-0081 Share；Share 本地状态不会写入 TAP-0087 event、timing 或 workload。",
    relatedMachines: ["viewerLoading", "viewerAnalysis"]
  }
});

const surfaceFixturePlans = Object.freeze({
  firstInstallSetup: "freshInstall",
  requiredPermissionCheck: "updateWithRevokedPhotos",
  resourceInitialization: "inPlaceUpdate",
  viewfinder: "ordinaryProcessLaunch",
  library: "ordinaryProcessLaunch",
  photoViewer: "ordinaryProcessLaunch"
});

const setupOperationLabels = Object.freeze({
  attestation: "Network / App Attest",
  camera: "Camera",
  photos: "Photos",
  location: "Location",
  microphone: "Microphone"
});

function makeInitialReviewEntry() {
  const fallback = createState("freshInstall");
  return {
    state: fallback,
    history: [clone(fallback)],
    focusSeq: null,
    workloadFilter: "truth",
    eventViewMode: "timing",
    autoTransition: true
  };
}

const initialReviewEntry = makeInitialReviewEntry();
let state = initialReviewEntry.state;
let playbackHistory = initialReviewEntry.history;
let focusSeq = initialReviewEntry.focusSeq;
let workloadFilter = initialReviewEntry.workloadFilter;
let eventViewMode = initialReviewEntry.eventViewMode;
let selectedMachineId = null;
let selectedMachineFocusSeq = null;
let selectedWorkloadId = null;
let launchTransitionTimer = null;
let tapShareSlice = null;

function clearLaunchTransition() {
  if (launchTransitionTimer != null) {
    window.clearTimeout(launchTransitionTimer);
    launchTransitionTimer = null;
  }
}

function focusedTrace() {
  if (focusSeq == null) return state.log.at(-1) || null;
  return state.log.find((entry) => entry.seq === focusSeq) || state.log.at(-1) || null;
}

function dismissTapSharePresentation({ restoreFocus = false } = {}) {
  if (!tapShareSlice || tapShareSlice.snapshot().panel === "closed") return false;
  tapShareSlice.close();
  if (restoreFocus) document.querySelector("[data-existing-share-boundary]")?.focus();
  return true;
}

function currentReviewSurface() {
  if (state.phone.page === "firstAppFrame") return "systemLaunchScreen";
  return Object.hasOwn(reviewSurfaceCatalog, state.phone.page) ? state.phone.page : null;
}

function dispatch(event, { announce = true } = {}) {
  dismissTapSharePresentation();
  if (event.type !== "MEASUREMENT_PROFILE_CHANGED") clearLaunchTransition();
  state = reduce(state, event);
  playbackHistory.push(clone(state));
  focusSeq = state.log.at(-1)?.seq ?? null;
  selectedWorkloadId = null;
  renderAll();
  if (announce) {
    byID("prototype-announcement").textContent = `${eventLabels[event.type] || event.type}。当前页面 ${pageLabels[state.phone.page] || state.phone.page}。`;
  }
  return snapshot();
}

function reset(scenarioId = state.scenarioId) {
  dismissTapSharePresentation();
  clearLaunchTransition();
  const base = createState(scenarioId);
  const selection = { type: "SCENARIO_SELECTED", scenarioId };
  state = reduce(base, selection);
  playbackHistory = [clone(base), clone(state)];
  focusSeq = state.log.at(-1)?.seq ?? null;
  selectedMachineId = null;
  selectedMachineFocusSeq = null;
  selectedWorkloadId = null;
  renderAll();
  return snapshot();
}

function snapshot() {
  return {
    ...publicSnapshot(state),
    focusedTrace: clone(focusedTrace()),
    workloadFilter,
    eventViewMode,
    currentSurface: currentReviewSurface(),
    currentPhonePage: state.phone.page,
    selectedMachineId,
    selectedWorkloadId,
    canStepBack: playbackHistory.length > 1,
    autoLaunchTransition: byID("auto-transition-toggle")?.checked ?? true
  };
}

function stepBack() {
  dismissTapSharePresentation();
  clearLaunchTransition();
  if (playbackHistory.length <= 1) return snapshot();
  playbackHistory.pop();
  state = clone(playbackHistory.at(-1));
  focusSeq = state.log.at(-1)?.seq ?? null;
  selectedWorkloadId = null;
  renderAll();
  byID("prototype-announcement").textContent = `已返回上一个事件。当前页面 ${pageLabels[state.phone.page] || state.phone.page}。`;
  return snapshot();
}

function scheduleStartupTransitionIfNeeded() {
  if (state.milestones.t0 == null || state.milestones.t2 != null) return;
  if (!byID("auto-transition-toggle").checked) return;
  const event = state.milestones.t1 == null
    ? { type: "APP_FIRST_FRAME_COMMITTED" }
    : { type: "INITIAL_ROUTE_COMMITTED" };
  const delay = event.type === "APP_FIRST_FRAME_COMMITTED"
    ? (state.facts.activation.kind === "processLaunch" ? 980 : 260)
    : 320;
  launchTransitionTimer = window.setTimeout(() => {
    launchTransitionTimer = null;
    if (state.milestones.t2 == null) {
      dispatch(event);
      scheduleStartupTransitionIfNeeded();
    }
  }, delay);
}

function startScenario() {
  if (state.milestones.t0 != null) return;
  dispatch({ type: "ACTIVATION_REQUESTED" });
  scheduleStartupTransitionIfNeeded();
}

function advance() {
  const event = nextEvent(state);
  if (!event || !canReduce(state, event)) return snapshot();
  dispatch(event);
  if (["ACTIVATION_REQUESTED", "APP_FIRST_FRAME_COMMITTED"].includes(event.type)) scheduleStartupTransitionIfNeeded();
  return snapshot();
}

function reviewSurfaceReached(surfaceId) {
  switch (surfaceId) {
    case "systemLaunchScreen":
      return state.milestones.t0 != null;
    case "firstInstallSetup":
    case "requiredPermissionCheck":
    case "resourceInitialization":
      return state.phone.page === surfaceId;
    case "viewfinder":
      return state.phone.page === "viewfinder" && state.phone.stage === "interactive" && state.milestones.t4 != null;
    case "library":
      return state.phone.page === "library" && state.journey.catalogPublished && (
        state.facts.library.itemCount === 0 || state.journey.thumbnailsPublished
      );
    case "photoViewer":
      return state.phone.page === "photoViewer" && state.phone.stage === "photoReady";
    default:
      return false;
  }
}

function openSurface(surfaceId) {
  if (!Object.hasOwn(reviewSurfaceCatalog, surfaceId)) throw new Error(`Unknown review surface: ${surfaceId}`);
  const scenarioId = surfaceId === "systemLaunchScreen"
    ? state.scenarioId
    : surfaceFixturePlans[surfaceId];
  reset(scenarioId);

  let steps = 0;
  while (!reviewSurfaceReached(surfaceId) && steps < 64) {
    const event = nextEvent(state);
    if (!event || !canReduce(state, event)) break;
    dispatch(event, { announce: false });
    steps += 1;
  }

  const reached = reviewSurfaceReached(surfaceId);
  const requested = reviewSurfaceCatalog[surfaceId].title;
  if (surfaceId === "systemLaunchScreen" && state.facts.activation.kind !== "processLaunch") {
    byID("prototype-announcement").textContent = `${activationLabels[state.facts.activation.kind]} 没有 Launch Screen；已停在该场景 t0 的安全返回页面。`;
  } else {
    byID("prototype-announcement").textContent = reached
      ? `已通过 reducer journal 打开 ${requested} 审阅状态。`
      : `当前合法事件路径无法到达 ${requested}；已停在 ${pageLabels[state.phone.page] || state.phone.page}。`;
  }
  return snapshot();
}

function projectedRoute() {
  return state.route.page ? state.route : chooseRoute(state.facts);
}

function renderScenarioControls() {
  const scenarioSelect = byID("scenario-select");
  if (!scenarioSelect.options.length) {
    for (const fixture of Object.values(scenarioFixtures)) {
      const option = document.createElement("option");
      option.value = fixture.id;
      option.textContent = fixture.label;
      scenarioSelect.append(option);
    }
  }
  scenarioSelect.value = state.scenarioId;
  byID("scenario-summary").textContent = state.facts.summary;

  const route = projectedRoute();
  const routeResult = byID("route-result");
  routeResult.textContent = `${state.route.page ? "Committed" : "Projected"} · ${pageLabels[route.page] || route.page}`;
  routeResult.classList.toggle("is-committed", Boolean(state.route.page));

  const facts = [
    ["Installation", installationLabels[state.facts.installationContext] || state.facts.installationContext],
    ["Activation", activationLabels[state.facts.activation.kind] || state.facts.activation.kind],
    ["Setup receipt", `${state.facts.setupReceipt.state} / ${state.facts.setupReceipt.credentialBinding}`],
    ["Camera · Photos", `${state.facts.permissions.camera} · ${state.facts.permissions.photos}`],
    ["Init marker", initializationIdentityMatches(state.facts.initialization.storedIdentity, state.facts.initialization.targetIdentity) ? "current" : "absent / stale"],
    ["Initial App Attest", `${state.facts.attestation.bootstrap} · ${state.facts.attestation.network}`],
    ["Library scale", `${state.facts.library.itemCount} items · ${state.facts.library.thumbnails}`]
  ];
  byID("route-facts").replaceChildren(...facts.flatMap(([term, value]) => {
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = term;
    dd.textContent = value;
    return [dt, dd];
  }));

  document.querySelectorAll("[data-measurement-build]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.measurementBuild === state.facts.measurement.build));
  });
  byID("debugger-toggle").checked = state.facts.measurement.debuggerAttached;

  const activateButton = byID("activate-button");
  const previousButton = byID("previous-button");
  const nextButton = byID("next-button");
  previousButton.disabled = playbackHistory.length <= 1;
  activateButton.hidden = state.milestones.t0 != null;
  nextButton.hidden = false;
  const event = nextEvent(state);
  nextButton.disabled = state.milestones.t0 == null || !event || !canReduce(state, event);
  nextButton.textContent = "下一个事件";
  byID("next-event-label").textContent = event
    ? `Next · ${eventLabels[event.type] || event.type}`
    : "当前脚本没有下一事件；可重置、切换场景或使用手机内的核心导航。";
}

function requirementStatus(key) {
  if (key === "attestation") return state.facts.attestation.bootstrap;
  return state.facts.permissions[key];
}

function statusIndicator(status) {
  const indicator = document.createElement("span");
  indicator.className = "setup-state";
  if (["ready", "authorized", "limited"].includes(status)) {
    indicator.classList.add("is-complete");
    indicator.setAttribute("aria-label", "完成");
  } else if (["running", "automaticRetryWaiting", "requesting"].includes(status)) {
    indicator.classList.add("is-requesting");
    indicator.setAttribute("aria-label", "进行中");
  } else if (status === "timedOutAwaitingExplicitRetry" || status === "denied") {
    indicator.classList.add("is-failed");
    indicator.setAttribute("aria-label", "需要处理");
    const icon = document.createElement("img");
    icon.src = "assets/icons/warning-circle.svg";
    icon.alt = "";
    indicator.append(icon);
  } else if (status === "skipped") {
    indicator.classList.add("is-skipped");
    indicator.textContent = "跳";
    indicator.setAttribute("aria-label", "已跳过");
  }
  return indicator;
}

function makeSetupButton(label, action, permission = null) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.dataset.phoneAction = action;
  if (permission) button.dataset.permission = permission;
  return button;
}

function prototypeEventForControl(control) {
  if (!control) return null;
  const action = control.dataset.phoneAction;
  const permission = control.dataset.permission;
  if (action === "setup-attestation") {
    const bootstrap = state.facts.attestation.bootstrap;
    if (bootstrap === "idle") return { type: "SETUP_ATTESTATION_TAPPED" };
    if (bootstrap === "timedOutAwaitingExplicitRetry" && state.facts.attestation.network === "offline") {
      return { type: "NETWORK_BECAME_AVAILABLE" };
    }
    if (bootstrap === "timedOutAwaitingExplicitRetry") return { type: "SETUP_ATTESTATION_RETRY_TAPPED" };
    return null;
  }
  if (action === "setup-permission") return { type: "SETUP_PERMISSION_TAPPED", permission };
  if (action === "setup-permission-recovery") {
    return { type: "SETUP_PERMISSION_RECOVERY_TAPPED", permission, currentStatus: state.facts.permissions[permission] };
  }
  if (action === "setup-skip") return { type: "SETUP_OPTIONAL_SKIPPED", permission };
  if (action === "setup-continue") return { type: "SETUP_CONTINUE_TAPPED" };
  if (action === "permission-recovery") {
    return { type: "PERMISSION_RECOVERY_TAPPED", permission, currentStatus: state.facts.permissions[permission] };
  }
  return null;
}

function renderSetup() {
  const defaultDetails = {
    camera: "用于拍摄带有深度数据的照片。",
    photos: "用于保存和读取照片。",
    location: "用于将拍摄地点写入照片元数据。",
    microphone: "用于实况照片和视频录音。"
  };
  const requiredStatuses = {
    attestation: state.facts.attestation.bootstrap,
    camera: state.facts.permissions.camera,
    photos: state.facts.permissions.photos,
    location: state.facts.permissions.location,
    microphone: state.facts.permissions.microphone
  };

  for (const [key, status] of Object.entries(requiredStatuses)) {
    const row = document.querySelector(`[data-requirement="${key}"]`);
    const actions = row.querySelector(".setup-actions");
    actions.replaceChildren();
    const detail = row.querySelector("small");
    if (key !== "attestation") {
      detail.textContent = status === "restricted"
        ? "访问受系统策略限制；TAPCam 不承诺可在设置中恢复。"
        : status === "denied"
          ? "访问已拒绝；可前往系统设置后返回检查。"
          : defaultDetails[key];
    }
    if (["ready", "authorized", "limited", "skipped"].includes(status)) {
      actions.append(statusIndicator(status));
    } else if (["running", "automaticRetryWaiting", "requesting"].includes(status)) {
      actions.append(statusIndicator(status));
    } else if (key === "attestation") {
      if (status === "timedOutAwaitingExplicitRetry" && state.facts.attestation.network === "offline") {
        actions.append(makeSetupButton("网络恢复", "setup-attestation"));
      } else {
        actions.append(makeSetupButton(status === "timedOutAwaitingExplicitRetry" ? "重试" : "允许", "setup-attestation"));
      }
      if (status === "timedOutAwaitingExplicitRetry") actions.prepend(statusIndicator(status));
    } else if (status === "restricted") {
      const restricted = makeSetupButton("受系统限制", "setup-permission-restricted", key);
      restricted.disabled = true;
      actions.append(restricted);
    } else if (status === "denied") {
      actions.append(statusIndicator(status));
      actions.append(makeSetupButton("前往设置", "setup-permission-recovery", key));
    } else {
      actions.append(makeSetupButton("允许", "setup-permission", key));
      if (["location", "microphone"].includes(key)) actions.append(makeSetupButton("跳过", "setup-skip", key));
    }
  }

  const ready = setupRequiredReady(state);
  byID("setup-continue").disabled = !ready;
  const bootstrap = state.facts.attestation.bootstrap;
  const guidance = byID("setup-guidance");
  guidance.classList.toggle("is-warning", bootstrap === "timedOutAwaitingExplicitRetry");
  if (bootstrap === "timedOutAwaitingExplicitRetry") {
    guidance.textContent = state.facts.attestation.network === "offline"
      ? "首次 App Attest 尚未完成。网络恢复后仍需在本行明确重试。"
      : "首次 App Attest 尚未完成；点击网络行重试。";
  } else if (ready) {
    guidance.textContent = "App Attest、相机与照片图库已完成。可继续进入资源初始化。";
  } else {
    guidance.textContent = "请先完成 App Attest、相机与照片图库访问。位置与麦克风为可选项。";
  }

  const latest = state.log.at(-1)?.event;
  const boundary = byID("system-boundary");
  if (["SETUP_PERMISSION_TAPPED", "SETUP_PERMISSION_RECOVERY_TAPPED", "SETUP_ATTESTATION_TAPPED", "SETUP_ATTESTATION_RETRY_TAPPED"].includes(latest?.type)) {
    boundary.hidden = false;
    if (latest.type === "SETUP_PERMISSION_TAPPED") {
      byID("system-boundary-title").textContent = "系统边界";
      byID("system-boundary-copy").textContent = `${permissionLabels[latest.permission]}由 iOS 系统界面接管；此原型只记录返回后的状态。`;
    } else if (latest.type === "SETUP_PERMISSION_RECOVERY_TAPPED") {
      byID("system-boundary-title").textContent = "设置边界";
      byID("system-boundary-copy").textContent = `${permissionLabels[latest.permission]}已拒绝；TAPCam 打开系统设置，并在返回后被动刷新该行状态。`;
    } else {
      byID("system-boundary-title").textContent = "首次凭据流程";
      byID("system-boundary-copy").textContent = "网络行启动首次 App Attest 注册/验证；它不是系统权限页，也不能由通用连通性探测代替。";
    }
  } else {
    boundary.hidden = true;
  }

  document.querySelectorAll('[data-phone-page="firstInstallSetup"] [data-phone-action]').forEach((control) => {
    const event = prototypeEventForControl(control);
    control.disabled = !event || !canReduce(state, event);
  });
}

function renderPermissionCheck() {
  for (const permission of ["camera", "photos"]) {
    const row = document.querySelector(`[data-permission-check="${permission}"]`);
    const button = row.querySelector("button");
    const status = state.facts.permissions[permission];
    const ready = permission === "photos" ? photosUsable(status) : status === "authorized";
    row.classList.toggle("is-ready", ready);
    row.classList.toggle("is-restricted", status === "restricted");
    const detail = row.querySelector("small");
    detail.textContent = status === "restricted"
      ? "访问受系统策略限制；TAPCam 不承诺可在设置中恢复。"
      : permission === "camera" ? "拍摄和取景需要相机访问。" : "保存与浏览需要授权或 Limited Access。";
    button.disabled = ready || status === "restricted";
    button.textContent = ready
      ? (status === "limited" ? "Limited" : "已允许")
      : status === "notDetermined" ? "允许" : status === "restricted" ? "受系统限制" : "前往设置";
  }
}

function renderReadiness() {
  const cameraReady = state.machines.cameraReadiness === "interactive";
  const catalogReady = state.machines.libraryCatalog === "published";
  const cameraRow = document.querySelector('[data-readiness="camera"]');
  const libraryRow = document.querySelector('[data-readiness="library"]');
  cameraRow.classList.toggle("is-ready", cameraReady);
  libraryRow.classList.toggle("is-ready", catalogReady);
  cameraRow.querySelector("small").textContent = cameraReady ? "首个真实预览与相机交互已就绪" : "正在准备首个真实预览与交互";
  libraryRow.querySelector("small").textContent = catalogReady ? "首个可用媒体目录已发布" : "正在发布首个可用媒体目录";
}

function libraryItems() {
  const count = Math.max(0, Math.min(35, state.facts.library.itemCount));
  const positions = ["50% 44%", "48% 63%", "50% 27%", "57% 74%", "43% 55%"];
  return Array.from({ length: count }, (_, index) => ({
    id: `fixture-photo-${String(index + 1).padStart(2, "0")}`,
    src: index % 4 === 0 || index % 4 === 3
      ? "assets/media/rainy-street-viewer-fixture.png"
      : "assets/media/viewfinder-camera-fixture.png",
    position: positions[index % positions.length]
  }));
}

function renderLibrary() {
  const catalogReady = state.journey.catalogPublished;
  byID("library-loading").hidden = catalogReady;
  const isEmpty = catalogReady && state.facts.library.itemCount === 0;
  byID("library-empty").hidden = !isEmpty;
  const grid = byID("library-grid");
  grid.hidden = !catalogReady || isEmpty;
  if (!catalogReady || isEmpty) {
    grid.replaceChildren();
    return;
  }
  const thumbnailsReady = state.journey.thumbnailsPublished;
  grid.replaceChildren(...libraryItems().map((item) => {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.phoneAction = "open-photo";
    button.dataset.assetId = item.id;
    button.classList.toggle("is-loading", !thumbnailsReady);
    button.disabled = !thumbnailsReady;
    button.setAttribute("aria-label", thumbnailsReady ? `打开照片 ${item.id}` : `照片 ${item.id} 缩略图加载中`);
    const image = document.createElement("img");
    image.src = item.src;
    image.alt = "";
    image.style.objectPosition = item.position;
    button.append(image);
    return button;
  }));
}

function renderPhone() {
  const trace = focusedTrace();
  document.querySelectorAll("[data-phone-page]").forEach((page) => {
    page.hidden = page.dataset.phonePage !== state.phone.page;
  });
  const phoneSurface = byID("phone-surface");
  if (trace?.effects.page === state.phone.page) phoneSurface.dataset.highlightSeq = String(trace.seq);
  else phoneSurface.removeAttribute("data-highlight-seq");

  const ownerBadge = byID("phone-owner-badge");
  const isSystem = state.phone.page === "systemLaunchScreen";
  ownerBadge.textContent = isSystem ? "iOS system-owned reference" : "App-owned";
  ownerBadge.classList.toggle("is-system", isSystem);
  byID("phone-page-label").textContent = pageLabels[state.phone.page] || state.phone.page;
  byID("phone-stage-label").textContent = state.phone.stage;
  byID("system-reference-note").textContent = isSystem
    ? "Exact LaunchLogo + LaunchBackground reference · iOS owns dismissal · not timing evidence"
    : "393 × 852 review viewport · not device evidence";

  renderSetup();
  renderPermissionCheck();
  renderReadiness();
  renderLibrary();

  const preview = document.querySelector(".camera-preview");
  const interactive = state.phone.stage === "interactive";
  preview.style.filter = state.phone.page === "viewfinder" && !["previewReady", "interactive"].includes(state.phone.stage) ? "brightness(.42) blur(2px)" : "none";
  document.querySelector('[data-phone-action="open-library"]').disabled = !interactive || state.milestones.t4 == null;
  byID("viewer-loading").hidden = state.phone.stage === "photoReady";
}

function businessProfileForCurrentPage() {
  if (state.phone.page === "dormant") {
    return {
      title: "等待 UI",
      owner: "Reviewer workbench",
      summary: "从左侧 UI 目录选择页面；workbench 会重置到指定 fixture，并只用合法 reducer event 推进。",
      operations: "尚未启动场景。",
      relatedMachines: ["activation", "routeDecision"]
    };
  }
  if (state.phone.page === "firstAppFrame") {
    return {
      title: "First App Frame",
      owner: "TAPCam · minimal route frame",
      summary: "iOS Launch Screen 已结束；这里仅完成轻量 app-owned 首帧和事实读取，尚未执行可扩展重操作。",
      operations: "下一事件只提交事实决定的初始路由。",
      relatedMachines: ["activation", "routeDecision"]
    };
  }
  return reviewSurfaceCatalog[state.phone.page] || {
    title: pageLabels[state.phone.page] || state.phone.page,
    owner: "Reviewer context",
    summary: "当前页面尚未登记独立业务摘要。",
    operations: "只允许 reducer 暴露的下一事件。",
    relatedMachines: []
  };
}

function renderSurfaceCatalog() {
  const current = currentReviewSurface();
  document.querySelectorAll("[data-review-surface]").forEach((button) => {
    const isCurrent = button.dataset.reviewSurface === current;
    button.classList.toggle("is-current", isCurrent);
    button.setAttribute("aria-pressed", String(isCurrent));
    if (isCurrent) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });

  const showLaunchContext = ["dormant", "systemLaunchScreen", "firstAppFrame"].includes(state.phone.page);
  document.querySelectorAll(".launch-context-card").forEach((section) => {
    section.hidden = !showLaunchContext;
  });
}

function makeReviewerOperation(label, action, { primary = false } = {}) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = primary ? "primary-action" : "secondary-action";
  button.textContent = label;
  button.addEventListener("click", action);
  return button;
}

function phoneControlIsAvailable(control) {
  if (!control || control.disabled || control.closest("[hidden]")) return false;
  const prototypeEvent = prototypeEventForControl(control);
  return prototypeEvent == null || canReduce(state, prototypeEvent);
}

function renderSurfaceOperations() {
  const profile = businessProfileForCurrentPage();
  byID("surface-operation-title").textContent = `${profile.title} 操作`;
  byID("surface-operation-state").textContent = `${state.phone.stage} · seq ${state.seq}`;
  byID("surface-operation-summary").textContent = profile.operations;

  const actions = [];
  const add = (label, action, options) => actions.push(makeReviewerOperation(label, action, options));

  if (state.phone.page === "firstInstallSetup") {
    document.querySelectorAll('[data-phone-page="firstInstallSetup"] [data-phone-action]').forEach((control) => {
      if (!phoneControlIsAvailable(control)) return;
      const requirement = control.closest("[data-requirement]")?.dataset.requirement;
      const prefix = setupOperationLabels[requirement] || "Setup";
      add(`${prefix} · ${control.textContent.trim()}`, () => control.click());
    });
  } else if (state.phone.page === "requiredPermissionCheck") {
    document.querySelectorAll('[data-phone-page="requiredPermissionCheck"] [data-phone-action="permission-recovery"]').forEach((control) => {
      if (!phoneControlIsAvailable(control)) return;
      const permission = control.dataset.permission;
      add(`${permissionLabels[permission]} · ${control.textContent.trim()}`, () => control.click());
    });
  } else if (state.phone.page === "viewfinder") {
    const openLibrary = document.querySelector('[data-phone-page="viewfinder"] [data-phone-action="open-library"]');
    if (phoneControlIsAvailable(openLibrary)) add("打开 TAP Library", () => openLibrary.click());
  } else if (state.phone.page === "library") {
    const libraryBack = document.querySelector('[data-phone-page="library"] [data-phone-action="library-back"]');
    const firstPhoto = document.querySelector('[data-phone-page="library"] [data-phone-action="open-photo"]:not(:disabled)');
    if (phoneControlIsAvailable(firstPhoto)) add("打开首张照片", () => firstPhoto.click(), { primary: true });
    if (phoneControlIsAvailable(libraryBack)) add("返回 Viewfinder", () => libraryBack.click());
  } else if (state.phone.page === "photoViewer") {
    const shareBoundary = document.querySelector("[data-existing-share-boundary]");
    const viewerBack = document.querySelector('[data-phone-page="photoViewer"] [data-phone-action="viewer-back"]');
    if (shareBoundary) add("Share · 已批准 TAP-0081 边界", () => shareBoundary.click(), { primary: true });
    if (phoneControlIsAvailable(viewerBack)) add("返回 TAP Library", () => viewerBack.click());
  }

  byID("surface-operation-actions").replaceChildren(...actions);
}

function renderSurfaceBusiness() {
  const profile = businessProfileForCurrentPage();
  byID("surface-business-owner").textContent = profile.owner;
  byID("surface-business-title").textContent = profile.title;
  byID("surface-business-summary").textContent = profile.summary;
  byID("surface-business-machines").replaceChildren(...profile.relatedMachines.map((machineId) => {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.businessMachine = machineId;
    button.textContent = machineRegistry[machineId]?.label || machineId;
    button.setAttribute("aria-pressed", String(machineId === selectedMachineId));
    return button;
  }));
}

function renderTapShareInspector(shareSnapshot = tapShareSlice?.snapshot()) {
  const panel = byID("tap-share-local-inspector");
  const isViewer = state.phone.page === "photoViewer";
  panel.hidden = !isViewer;
  if (!isViewer || !shareSnapshot) return;
  byID("surface-operation-state").textContent = `${state.phone.stage} · TAP-0081 ${shareSnapshot.panel}`;
  byID("tap-share-local-state").textContent = shareSnapshot.systemActivityBoundaryReached
    ? `${shareSnapshot.panel} · system boundary reached`
    : shareSnapshot.panel;
  panel.querySelectorAll("[data-tap-share-node]").forEach((node) => {
    const nodeName = node.dataset.tapShareNode;
    node.classList.toggle("is-current", nodeName === shareSnapshot.panel || (
      nodeName === "closed" && shareSnapshot.systemActivityBoundaryReached
    ));
  });
  byID("tap-share-local-effect").textContent = shareSnapshot.systemActivityBoundaryReached
    ? "Payload 已准备完成；app-owned popover 已关闭。仅记录 system activity boundary，Viewer V1、seq、focus 与 workload 全部不变。"
    : "Viewer V1 与 seq 保持不变；所有节点由 TAP-0081 local controller 驱动，不进入 TAP-0087 reducer。";
}

function highlightSequence(element, trace, matches) {
  element.classList.toggle("is-highlighted", Boolean(trace && matches));
  if (trace && matches) element.dataset.highlightSeq = String(trace.seq);
  else element.removeAttribute("data-highlight-seq");
}

function renderTimeline() {
  const trace = focusedTrace();
  const timeline = byID("timeline");
  timeline.replaceChildren(...timelineRegistry.map((item) => {
    const li = document.createElement("li");
    const reached = state.milestones[item.id] != null;
    li.classList.toggle("is-reached", reached);
    highlightSequence(li, trace, trace?.effects.milestones.includes(item.id));
    const label = document.createElement("strong");
    const name = document.createElement("span");
    label.className = "timeline-anchor";
    label.dataset.lifecycleAnchorId = item.id;
    label.textContent = item.id;
    name.textContent = item.label;
    li.append(label, name);
    li.title = `${item.label} · ${item.interval}`;
    return li;
  }));
  byID("current-interval").textContent = state.currentInterval || "尚未启动";
  const reachedItems = timelineRegistry.filter((item) => state.milestones[item.id] != null);
  const current = reachedItems.at(-1) || null;
  const [allowed, forbidden] = byID("interval-detail").querySelectorAll("small");
  allowed.textContent = current?.allowed || "等待里程碑";
  forbidden.textContent = current?.forbidden || "等待里程碑";
  renderJourneySpans(trace);
}

function journeySpanSelection(trace) {
  const setupNode = state.machines.firstInstallSetup;
  const permissionNode = state.machines.requiredPermissionCheck;
  const cameraNode = state.machines.cameraReadiness;
  const setupActionFocused = ["SETUP_ATTESTATION_TAPPED", "SETUP_ATTESTATION_RETRY_TAPPED", "SETUP_PERMISSION_TAPPED", "SETUP_OPTIONAL_SKIPPED"].includes(trace?.event.type);
  const permissionActionFocused = trace?.event.type === "PERMISSION_RECOVERY_TAPPED";
  const setup = setupActionFocused ? "S1"
    : setupNode === "completed" ? "S4"
    : setupNode === "requiredReady" ? "S3"
      : ["attestationRunning", "automaticRetryWaiting", "timedOutAwaitingExplicitRetry", "waitingSystem"].includes(setupNode) ? "S2"
        : ["awaitingExplicitActions", "credentialRecovery"].includes(setupNode) ? "S0" : "—";
  const permission = permissionActionFocused ? "P1"
    : permissionNode === "resolved" || permissionNode === "rechecking" ? "P3"
    : ["awaitingAllow", "awaitingSettings"].includes(permissionNode) ? "P2"
      : ["inspecting", "restricted"].includes(permissionNode) ? "P0" : "—";
  const initializationCurrent = initializationIdentityMatches(
    state.facts.initialization.storedIdentity,
    state.facts.initialization.targetIdentity
  );
  const camera = state.machines.resourceInitialization === "markerCommitted" || state.route.reason === "initializationComplete" ? "C4"
    : cameraNode === "interactive" && (state.machines.libraryCatalog === "published" || initializationCurrent) ? "C3"
      : ["interactive", "previewReady"].includes(cameraNode) ? "C2"
        : cameraNode === "configuring" ? "C1"
          : ["discovering", "configuring"].includes(cameraNode) || ["resourceInitialization", "viewfinder"].includes(state.phone.page) ? "C0" : "—";
  const library = state.journey.thumbnailsPublished ? "L2"
    : state.phone.page === "library" && state.journey.catalogPublished ? "L1"
      : state.phone.page === "library" ? "L0" : "—";
  const viewer = state.journey.viewerReturned ? "V2"
    : state.phone.page === "photoViewer" && state.phone.stage === "photoReady" ? "V1"
      : state.phone.page === "photoViewer" ? "V0" : "—";
  return { setup, permission, camera, library, viewer };
}

function renderJourneySpans(trace) {
  const values = journeySpanSelection(trace);
  const definitions = [
    ["setup", "Setup", "firstInstallSetup", "firstInstallSetup"],
    ["permission", "Permission", "requiredPermissionCheck", "requiredPermissionCheck"],
    ["camera", "Camera / RI", "cameraReadiness", "resourceInitialization"],
    ["library", "Library", "libraryCatalog", "library"],
    ["viewer", "Viewer", "viewerLoading", "photoViewer"]
  ];
  byID("journey-spans").replaceChildren(...definitions.map(([key, label, machine, page]) => {
    const card = document.createElement("span");
    card.className = "journey-span";
    const value = values[key];
    card.classList.toggle("is-current", value !== "—");
    const highlighted = Boolean(trace && (trace.effects.machines.includes(machine) || trace.effects.page === page));
    highlightSequence(card, trace, highlighted);
    const strong = document.createElement("strong");
    const small = document.createElement("small");
    strong.textContent = value;
    small.textContent = label;
    card.append(strong, small);
    return card;
  }));
}

function renderMachines() {
  const trace = focusedTrace();
  const profile = businessProfileForCurrentPage();
  const focusKey = trace?.seq ?? `page:${state.phone.page}:${state.seq}`;
  const defaultMachine = trace?.effects.machines.find((machineId) => machineRegistry[machineId])
    || profile.relatedMachines.find((machineId) => machineRegistry[machineId])
    || Object.keys(machineRegistry)[0];
  if (!machineRegistry[selectedMachineId] || selectedMachineFocusSeq !== focusKey) {
    selectedMachineId = defaultMachine;
    selectedMachineFocusSeq = focusKey;
  }

  const select = byID("machine-flow-select");
  select.replaceChildren(...Object.entries(machineRegistry).map(([machineId, registry]) => {
    const option = document.createElement("option");
    option.value = machineId;
    option.textContent = registry.label;
    return option;
  }));
  select.value = selectedMachineId;

  const registry = machineRegistry[selectedMachineId];
  const currentNode = state.machines[selectedMachineId];
  byID("machine-flow-title").textContent = `Target · ${registry.label} · ${currentNode}`;

  const journalEdges = state.log.flatMap((entry) => entry.effects.edges
    .filter((edge) => edge.machineId === selectedMachineId)
    .map((edge) => ({ ...edge, seq: entry.seq })));
  const focusedEdges = new Set((trace?.effects.edges || [])
    .filter((edge) => edge.machineId === selectedMachineId)
    .map((edge) => `${edge.from}\u0000${edge.to}`));
  const track = document.createElement("div");
  track.className = "machine-flow-track";

  const appendNode = (node, modifiers = []) => {
    const element = document.createElement("span");
    element.className = "machine-flow-node";
    element.dataset.machineNode = node;
    element.textContent = node;
    modifiers.forEach((modifier) => element.classList.add(modifier));
    track.append(element);
    return element;
  };
  const appendGap = () => {
    const gap = document.createElement("span");
    gap.className = "machine-flow-gap";
    gap.textContent = "…";
    gap.setAttribute("aria-label", "journal 中没有声明这两个节点之间的边");
    track.append(gap);
  };

  let lastNode = null;
  for (const edge of journalEdges) {
    const isFocused = edge.seq === trace?.seq && focusedEdges.has(`${edge.from}\u0000${edge.to}`);
    if (lastNode !== edge.from) {
      if (lastNode != null) appendGap();
      appendNode(edge.from, isFocused ? ["is-focused-from"] : []);
    } else if (isFocused) {
      track.lastElementChild?.classList.add("is-focused-from");
    }

    const arrow = document.createElement("button");
    arrow.type = "button";
    arrow.className = "machine-flow-arrow";
    arrow.dataset.focusSeq = String(edge.seq);
    arrow.textContent = "→";
    arrow.title = `seq ${edge.seq} · ${edge.from} → ${edge.to}`;
    arrow.classList.toggle("is-focused", isFocused);
    if (isFocused) arrow.dataset.highlightSeq = String(edge.seq);
    track.append(arrow);
    appendNode(edge.to, isFocused ? ["is-focused-to"] : []);
    lastNode = edge.to;
  }

  if (lastNode == null) {
    appendNode(currentNode);
  } else if (lastNode !== currentNode) {
    appendGap();
    appendNode(currentNode);
  }
  const currentMatches = [...track.querySelectorAll("[data-machine-node]")]
    .filter((node) => node.dataset.machineNode === currentNode);
  currentMatches.at(-1)?.classList.add("is-current");

  const visited = new Set(journalEdges.flatMap((edge) => [edge.from, edge.to]));
  visited.add(currentNode);
  const unvisited = registry.nodes.filter((node) => !visited.has(node));
  const legend = document.createElement("div");
  legend.className = "machine-flow-legend";
  if (unvisited.length) {
    const label = document.createElement("small");
    label.textContent = "本次 journal 尚未经过";
    legend.append(label, ...unvisited.map((node) => {
      const chip = document.createElement("span");
      chip.className = "machine-flow-node is-unvisited";
      chip.textContent = node;
      return chip;
    }));
  }

  const diagram = byID("machine-flow-diagram");
  diagram.replaceChildren(track, legend);
  highlightSequence(diagram, trace, Boolean(trace?.effects.machines.includes(selectedMachineId)));
  const focusedNode = diagram.querySelector(".is-focused-to") || diagram.querySelector(".machine-flow-node.is-current");
  if (focusedNode) {
    diagram.scrollLeft = Math.max(0, focusedNode.offsetLeft - diagram.clientWidth + focusedNode.offsetWidth + 12);
  }
}

function compactEffectValue(value) {
  if (value == null) return "∅";
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

function renderTraceEffects() {
  const trace = focusedTrace();
  byID("focused-event-label").textContent = trace ? (eventLabels[trace.event.type] || trace.event.type) : "尚未选择事件";
  const edges = trace?.effects.edges || [];
  const markers = trace?.effects.markers || [];
  const edgeList = byID("edge-effect-list");
  const markerList = byID("marker-effect-list");
  edgeList.replaceChildren(...(edges.length ? edges.map((edge) => {
    const chip = document.createElement("span");
    chip.className = "is-highlighted";
    chip.dataset.highlightSeq = String(trace.seq);
    chip.textContent = `${edge.machineId}: ${edge.from} → ${edge.to}`;
    return chip;
  }) : [Object.assign(document.createElement("span"), { textContent: "—" })]));
  markerList.replaceChildren(...(markers.length ? markers.map((marker) => {
    const chip = document.createElement("span");
    chip.className = "is-highlighted";
    chip.dataset.highlightSeq = String(trace.seq);
    chip.textContent = `${marker.id}: ${compactEffectValue(marker.from)} → ${compactEffectValue(marker.to)}`;
    return chip;
  }) : [Object.assign(document.createElement("span"), { textContent: "—" })]));

  const setupReceipt = state.facts.setupReceipt;
  const initialization = state.facts.initialization;
  const rows = [
    ["Setup receipt", `${setupReceipt.state} · binding ${setupReceipt.credentialBinding}`],
    ["Initialization marker", initializationIdentityMatches(initialization.storedIdentity, initialization.targetIdentity) ? "current" : "absent / stale"]
  ];
  byID("marker-snapshot").replaceChildren(...rows.flatMap(([term, value]) => {
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = term;
    dd.textContent = value;
    return [dt, dd];
  }));
}

function statusClass(status) {
  if (["running", "waitingSystem", "waitingNetwork"].includes(status)) return "is-running";
  if (status === "succeeded") return "is-succeeded";
  if (status === "stale") return "is-conflict";
  if (["failedRetryable", "failedTerminal"].includes(status)) return "is-failed";
  return "";
}

function workloadIsRelevant(id, registry) {
  if (workloadFilter === "all") return true;
  const status = state.workloads[id];
  return status !== "dormant" || registry.pages.includes(state.phone.page);
}

function renderLifecycleTruthCards() {
  return lifecycleTruthRegistry
    .filter((truth) => !truth.mismatch || lifecycleTimingLaneRecordIDSet.has(truth.id))
    .map((truth) => {
      const reviewState = reviewStateFor(truth);
      const targetMerged = reviewState?.projectionMode === "mergeIntoTarget";
      const activeDifference = truth.activeDifference && reviewState?.activeDifference;
      const card = document.createElement("article");
      card.className = "workload-card lifecycle-truth-card";
      card.classList.toggle("is-lifecycle-follow-up", targetMerged);
      card.classList.toggle("is-lifecycle-mismatch", activeDifference);
      card.classList.toggle("is-lifecycle-aligned", !truth.mismatch);
      card.dataset.lifecycleTruthId = truth.id;
      card.dataset.lifecycleTargetAnchor = truth.targetBinding.anchor;
      if (truth.mismatch) {
        card.dataset.fix0809Disposition = truth.fix0809Disposition;
        card.dataset.fix0809Outcome = truth.fix0809Outcome;
        card.dataset.reviewState = truth.reviewState;
      }
      if (activeDifference && reviewState.renderConnector) {
        card.dataset.lifecycleDifferenceId = truth.id;
        card.dataset.lifecycleActualAnchor = truth.actual.anchor;
      }
      const tasks = `${reviewState?.taskLabel || "关联任务"} ${truth.followUpTaskIDs.join(" · ")}`;
      card.setAttribute(
        "aria-label",
        targetMerged
          ? `${truth.label}。${reviewState.accessibleLabel}。Candidate/Target 阶段 ${truth.targetBinding.anchor} ${truth.target.phase}。${tasks}。`
          : `${truth.label}。仍有位置差异。${reviewState ? `${reviewState.accessibleLabel}。` : ""}Actual 阶段 ${truth.actual.anchor} ${truth.actual.phase}。Target 阶段 ${truth.target.anchor} ${truth.target.phase}。${tasks}。`
      );

      const title = document.createElement("span");
      title.className = "workload-title";
      const strong = document.createElement("strong");
      const meta = document.createElement("small");
      strong.textContent = truth.label;
      meta.textContent = targetMerged ? "Candidate / Target" : "Baseline Actual / Target";
      title.append(strong, meta);

      const badge = document.createElement("span");
      badge.className = `lifecycle-truth-verdict ${targetMerged ? "is-follow-up" : activeDifference ? "is-mismatch" : "is-aligned"}`;
      badge.textContent = reviewState?.visibleLabel || (truth.mismatch ? "仍有位置差异" : "一致");
      const outcomeBadge = truth.mismatch ? makeFix0809OutcomeBadge(truth) : null;
      const taskBadge = truth.mismatch ? makeFollowUpTaskBadge(truth) : null;
      card.append(title, badge);
      if (outcomeBadge) card.append(outcomeBadge);

      if (targetMerged) {
        const phase = document.createElement("div");
        phase.className = "lifecycle-target-follow-up-phase";
        const phaseLabel = document.createElement("em");
        const anchor = document.createElement("strong");
        const detail = document.createElement("small");
        phaseLabel.textContent = "Candidate / Target";
        anchor.textContent = truth.targetBinding.anchor;
        detail.textContent = truth.target.phase;
        phase.append(phaseLabel, anchor, detail);
        card.append(phase);
        if (taskBadge) card.append(taskBadge);
        card.title = `${truth.target.summary}\n目标：${truth.target.evidence}`;
        return card;
      }

      const phase = document.createElement("div");
      phase.className = "lifecycle-truth-phase";
      phase.innerHTML = `<span><em>Actual</em><strong></strong><small></small></span><i aria-hidden="true">→</i><span><em>Target</em><strong></strong><small></small></span>`;
      const phaseColumns = phase.querySelectorAll("span");
      phaseColumns[0].querySelector("strong").textContent = truth.actual.anchor;
      phaseColumns[0].querySelector("small").textContent = truth.actual.phase;
      phaseColumns[1].querySelector("strong").textContent = truth.target.anchor;
      phaseColumns[1].querySelector("small").textContent = truth.target.phase;

      const detail = document.createElement("div");
      detail.className = "lifecycle-truth-detail";
      detail.innerHTML = `<span><strong>Current main · Actual</strong><small></small></span><span><strong>Prototype · Target</strong><small></small></span>`;
      const detailColumns = detail.querySelectorAll("small");
      detailColumns[0].textContent = truth.actual.summary;
      detailColumns[1].textContent = truth.target.summary;
      const evidence = document.createElement("small");
      evidence.className = "lifecycle-truth-evidence";
      evidence.textContent = `代码：${truth.actual.evidence} · 目标：${truth.target.evidence}`;
      card.append(phase, detail, evidence);
      if (taskBadge) card.append(taskBadge);
      return card;
    });
}

function updateTimelineDifferenceAnchors() {
  const activeDifferenceAnchors = workloadFilter === "truth"
    ? new Set(lifecycleTruthRegistry
      .filter((truth) => (
        truth.mismatch
        && lifecycleTimingLaneRecordIDSet.has(truth.id)
        && truth.activeDifference
        && reviewStateFor(truth)?.renderConnector
      ))
      .map((truth) => truth.actual.anchor))
    : new Set();
  const followUpAnchors = workloadFilter === "truth"
    ? new Set(lifecycleTruthRegistry
      .filter((truth) => (
        truth.mismatch
        && lifecycleTimingLaneRecordIDSet.has(truth.id)
        && reviewStateFor(truth)?.projectionMode === "mergeIntoTarget"
      ))
      .map((truth) => truth.targetBinding.anchor))
    : new Set();
  document.querySelectorAll("[data-lifecycle-anchor-id]").forEach((anchor) => {
    anchor.classList.toggle("has-lifecycle-difference", activeDifferenceAnchors.has(anchor.dataset.lifecycleAnchorId));
    anchor.classList.toggle("has-lifecycle-follow-up", followUpAnchors.has(anchor.dataset.lifecycleAnchorId));
  });
}

function renderWorkloads() {
  const trace = focusedTrace();
  document.documentElement.dataset.workloadFilter = workloadFilter;
  document.querySelectorAll("[data-workload-filter]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.workloadFilter === workloadFilter));
  });
  const list = byID("workload-list");
  if (workloadFilter === "truth") {
    list.replaceChildren(...renderLifecycleTruthCards());
    const lifecycleRecords = lifecycleTruthRegistry.filter((truth) => lifecycleTimingLaneRecordIDSet.has(truth.id));
    const activeDifferenceCount = lifecycleRecords.filter((truth) => truth.activeDifference).length;
    const followUpCount = lifecycleRecords.length - activeDifferenceCount;
    byID("workload-inspector-summary").textContent = `${followUpCount} 个目标位置待回归 · ${activeDifferenceCount} 个仍有位置差异 · Workload 见 Timing`;
    updateTimelineDifferenceAnchors();
    scheduleLifecycleDifferenceConnectors();
    return;
  }
  const entries = Object.entries(workloadRegistry).filter(([id, registry]) => workloadIsRelevant(id, registry));
  byID("workload-inspector-summary").textContent = workloadFilter === "all" ? "全部 workload" : "当前 surface workload";
  list.replaceChildren(...entries.map(([id, registry]) => {
    const status = state.workloads[id];
    const card = document.createElement("button");
    card.type = "button";
    card.className = "workload-card";
    card.dataset.workloadId = id;
    card.setAttribute("aria-pressed", String(selectedWorkloadId === id));
    card.setAttribute("aria-label", `${registry.label}，${statusLabels[status] || status}，跳转到对应 UI 与生命周期审阅时刻`);
    highlightSequence(card, trace, selectedWorkloadId === id || trace?.effects.workloads.includes(id));
    const title = document.createElement("span");
    title.className = "workload-title";
    const strong = document.createElement("strong");
    const meta = document.createElement("small");
    strong.textContent = registry.label;
    meta.textContent = `${registry.family} · ${alignmentLabels[registry.alignment] || registry.alignment}`;
    title.append(strong, meta);
    const badge = document.createElement("span");
    badge.className = `workload-status ${statusClass(status)}`;
    badge.textContent = statusLabels[status] || status;
    const detail = document.createElement("span");
    detail.className = "workload-detail";
    detail.innerHTML = `<span><strong>Current main · observed</strong><small></small></span><span><strong>TAP-0087 · target</strong><small></small></span><span><strong>Current effects</strong><small></small></span><span><strong>Source evidence</strong><small></small></span>`;
    const values = [
      `${registry.observed.earliest} · ${registry.observed.trigger} · ${registry.observed.owner}`,
      `${registry.target.earliest} · ${registry.target.trigger} · ${registry.target.owner}`,
      `blocks: ${registry.observed.blocks}; network: ${registry.observed.network}`,
      registry.observed.evidence
    ];
    detail.querySelectorAll("small").forEach((element, index) => { element.textContent = values[index]; });
    card.append(title, badge, detail);
    return card;
  }));
  updateTimelineDifferenceAnchors();
  scheduleLifecycleDifferenceConnectors();
}

let lifecycleConnectorFrame = null;

function renderLifecycleDifferenceConnectors() {
  lifecycleConnectorFrame = null;
  const svg = byID("lifecycle-difference-connectors");
  const inspector = document.querySelector(".inspector-panel");
  const list = byID("workload-list");
  svg.replaceChildren();
  if (workloadFilter !== "truth") {
    svg.dataset.visibleConnectorCount = "0";
    return;
  }

  const inspectorRect = inspector.getBoundingClientRect();
  const listRect = list.getBoundingClientRect();
  svg.setAttribute("viewBox", `0 0 ${inspectorRect.width} ${inspectorRect.height}`);
  svg.setAttribute("width", String(inspectorRect.width));
  svg.setAttribute("height", String(inspectorRect.height));

  const namespace = "http://www.w3.org/2000/svg";
  const cards = [...list.querySelectorAll("[data-lifecycle-difference-id]")];
  let visibleConnectorCount = 0;
  cards.forEach((card) => {
    const cardRect = card.getBoundingClientRect();
    const visibleTop = Math.max(cardRect.top, listRect.top, inspectorRect.top);
    const visibleBottom = Math.min(cardRect.bottom, listRect.bottom, inspectorRect.bottom);
    const anchor = document.querySelector(`[data-lifecycle-anchor-id="${card.dataset.lifecycleActualAnchor}"]`);
    if (!anchor || visibleBottom <= visibleTop) {
      card.classList.remove("has-visible-connector");
      return;
    }

    const anchorRect = anchor.getBoundingClientRect();
    const path = document.createElementNS(namespace, "path");
    const cardMidY = (visibleTop + visibleBottom) / 2 - inspectorRect.top;
    const isBesideTimeline = cardRect.left > anchorRect.right + 20;
    let pathData;
    if (isBesideTimeline) {
      const startX = anchorRect.right - inspectorRect.left;
      const startY = anchorRect.top + anchorRect.height / 2 - inspectorRect.top;
      const endX = cardRect.left - inspectorRect.left;
      const endY = cardMidY;
      const controlX = startX + Math.max(24, (endX - startX) * 0.5);
      pathData = `M ${startX} ${startY} C ${controlX} ${startY}, ${controlX} ${endY}, ${endX} ${endY}`;
    } else {
      const startX = anchorRect.left + anchorRect.width / 2 - inspectorRect.left;
      const startY = anchorRect.bottom - inspectorRect.top;
      const endX = Math.min(Math.max(startX, cardRect.left - inspectorRect.left + 18), cardRect.right - inspectorRect.left - 18);
      const endY = visibleTop - inspectorRect.top;
      const controlY = startY + Math.max(20, (endY - startY) * 0.5);
      pathData = `M ${startX} ${startY} C ${startX} ${controlY}, ${endX} ${controlY}, ${endX} ${endY}`;
    }
    path.setAttribute("d", pathData);
    path.dataset.connectorId = card.dataset.lifecycleDifferenceId;
    path.dataset.sourceTruthId = card.dataset.lifecycleTruthId;
    path.dataset.targetAnchorId = card.dataset.lifecycleActualAnchor;
    path.classList.add("lifecycle-difference-connector");
    svg.append(path);
    card.classList.add("has-visible-connector");
    visibleConnectorCount += 1;
  });
  svg.dataset.visibleConnectorCount = String(visibleConnectorCount);
}

function scheduleLifecycleDifferenceConnectors() {
  if (lifecycleConnectorFrame != null) window.cancelAnimationFrame(lifecycleConnectorFrame);
  lifecycleConnectorFrame = window.requestAnimationFrame(renderLifecycleDifferenceConnectors);
}

function workloadInspectionHistoryIndex(workloadId) {
  for (let index = playbackHistory.length - 1; index >= 0; index -= 1) {
    if (workloadInspectionReached(playbackHistory[index], workloadId)) return index;
  }
  return -1;
}

function focusWorkload(workloadId) {
  const registry = workloadRegistry[workloadId];
  if (!registry || !machineRegistry[registry.machineId]) return snapshot();
  dismissTapSharePresentation();
  clearLaunchTransition();

  const historyIndex = workloadInspectionHistoryIndex(workloadId);
  const usedCanonicalFixture = historyIndex < 0;
  if (usedCanonicalFixture) {
    const journey = buildWorkloadInspectionJourney(workloadId);
    playbackHistory = journey.history.map(clone);
    state = clone(journey.state);
  } else {
    playbackHistory = playbackHistory.slice(0, historyIndex + 1).map(clone);
    state = clone(playbackHistory.at(-1));
  }

  const trace = state.log.at(-1) || null;
  selectedWorkloadId = workloadId;
  selectedMachineId = registry.machineId;
  focusSeq = trace?.seq ?? null;
  selectedMachineFocusSeq = focusSeq ?? `page:${state.phone.page}:${state.seq}`;
  renderAll();
  const status = statusLabels[state.workloads[workloadId]] || state.workloads[workloadId];
  byID("prototype-announcement").textContent = usedCanonicalFixture
    ? `已通过注册的 ${scenarioFixtures[state.scenarioId].label} reducer journal 打开 ${registry.label} 的 ${status} 审阅快照；UI、手机预览与 inspector 已同步。`
    : `已恢复 ${registry.label} 的真实 ${status} reducer 快照，seq ${trace.seq}；UI、手机预览与 inspector 已同步。`;
  return snapshot();
}

function renderEventLog() {
  const trace = focusedTrace();
  byID("trace-sequence").textContent = trace ? `seq ${trace.seq}` : "seq 0";
  const log = byID("event-log");
  log.replaceChildren(...[...state.log].reverse().map((entry) => {
    const li = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.focusSeq = String(entry.seq);
    button.setAttribute("aria-current", String(trace?.seq === entry.seq));
    if (trace?.seq === entry.seq) button.dataset.highlightSeq = String(entry.seq);
    const seq = document.createElement("span");
    const label = document.createElement("strong");
    const page = document.createElement("small");
    seq.className = "seq";
    seq.textContent = `#${entry.seq}`;
    label.textContent = eventLabels[entry.event.type] || entry.event.type;
    page.textContent = pageLabels[entry.pageAfter] || entry.pageAfter;
    button.append(seq, label, page);
    li.append(button);
    return li;
  }));
}

function stateSnapshotAtSequence(seq) {
  return [...playbackHistory].reverse().find((candidate) => candidate.seq === seq) || null;
}

function timingColumns() {
  let interval = "pre-t0";
  return [...state.log].sort((left, right) => left.seq - right.seq).map((entry) => {
    const reached = entry.effects.milestones || [];
    if (reached.length) {
      const milestone = reached.at(-1);
      interval = timelineRegistry.find((item) => item.id === milestone)?.interval || interval;
    }
    return {
      entry,
      interval,
      milestones: reached,
      milestone: reached.join(" + ") || null,
      stateAfter: stateSnapshotAtSequence(entry.seq)
    };
  });
}

function makeCausalEvent(text, seq, { primary = false } = {}) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = primary ? "causal-event causal-event-primary" : "causal-event causal-effect";
  button.dataset.focusSeq = String(seq);
  button.textContent = text;
  button.setAttribute("aria-current", String(focusedTrace()?.seq === seq));
  if (focusedTrace()?.seq === seq) button.dataset.highlightSeq = String(seq);
  return button;
}

function makeTimingLane(label, laneId, columns, renderColumn) {
  const lane = document.createElement("div");
  lane.className = "timing-lane";
  lane.dataset.timingLane = laneId;
  const laneLabel = document.createElement("strong");
  laneLabel.className = "timing-lane-label";
  laneLabel.textContent = label;
  lane.append(laneLabel);
  for (const column of columns) {
    const cell = document.createElement("div");
    cell.className = "timing-interval-column";
    cell.dataset.interval = column.interval;
    cell.dataset.causalSeq = String(column.entry.seq);
    cell.classList.toggle("is-focused", focusedTrace()?.seq === column.entry.seq);
    const content = renderColumn(column);
    if (Array.isArray(content)) cell.append(...content);
    else if (content) cell.append(content);
    lane.append(cell);
  }
  return lane;
}

function makeTimingLifecycleReviewCard(truth) {
  const reviewState = reviewStateFor(truth);
  const targetMerged = reviewState?.projectionMode === "mergeIntoTarget";
  const card = document.createElement("article");
  card.className = targetMerged ? "timing-lifecycle-follow-up" : "timing-lifecycle-difference";
  card.dataset.lifecycleTruthId = truth.id;
  card.dataset.timingTargetAnchor = truth.targetBinding.anchor;
  card.dataset.fix0809Disposition = truth.fix0809Disposition;
  card.dataset.fix0809Outcome = truth.fix0809Outcome;
  card.dataset.reviewState = truth.reviewState;
  if (truth.activeDifference && reviewState?.renderConnector) {
    card.dataset.timingDifferenceId = truth.id;
    card.dataset.timingActualAnchor = truth.actual.anchor;
  }
  const tasks = `${reviewState?.taskLabel || "关联任务"} ${truth.followUpTaskIDs.join(" · ")}`;
  card.setAttribute(
    "aria-label",
    targetMerged
      ? `${truth.label}。${reviewState.accessibleLabel}。Candidate/Target 阶段 ${truth.targetBinding.anchor} ${truth.target.phase}。${tasks}。`
      : `${truth.label}。仍有位置差异。${reviewState ? `${reviewState.accessibleLabel}。` : ""}Actual 阶段 ${truth.actual.anchor} ${truth.actual.phase}；Target 阶段 ${truth.target.anchor} ${truth.target.phase}。${tasks}。`
  );
  const label = document.createElement("strong");
  const phase = document.createElement("small");
  label.textContent = truth.label;
  phase.textContent = targetMerged
    ? `Candidate / Target · ${truth.targetBinding.anchor} · ${truth.target.phase}`
    : `Actual ${truth.actual.anchor} → Target ${truth.target.anchor}`;
  const outcomeBadge = makeFix0809OutcomeBadge(truth);
  const taskBadge = makeFollowUpTaskBadge(truth);
  card.append(label);
  if (outcomeBadge) card.append(outcomeBadge);
  card.append(phase);
  if (taskBadge) card.append(taskBadge);
  card.title = targetMerged ? truth.target.summary : `${truth.actual.summary}\n→ ${truth.target.summary}`;
  return card;
}

const workloadDifferenceLabels = Object.freeze({
  startsTooEarly: "开始过早",
  startsTooLate: "开始过晚",
  wrongTriggerWindow: "触发窗口不一致",
  readyPublishedTooEarly: "Ready 发布过早",
  readyEligibilityTooEarly: "Ready 条件过早",
  missingDeferredReleaseGuard: "缺少 t5 guard",
  wrongCompletionMeaning: "完成含义不一致",
  missingReadyDependency: "缺少 Ready 前置"
});

const timingDOMID = (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, "-");
const timingWorkloadEffectKey = (seq, workloadId, effectIndex) => `${seq}:${workloadId}:${effectIndex}`;
const timingWorkloadEffectDOMID = (seq, workloadId, effectIndex) => (
  `timing-workload-effect-${seq}-${timingDOMID(workloadId)}-${effectIndex + 1}`
);

function buildTimingWorkloadDifferenceProjection(columns) {
  const actualBySequence = new Map();
  const targetByEffect = new Map();

  for (const difference of workloadDifferenceRegistry) {
    if (!difference.mismatch) continue;
    const reviewState = reviewStateFor(difference);
    if (!reviewState) continue;
    const resolved = resolveWorkloadDifferenceTraceBinding(difference, state.scenarioId, columns);
    if (!resolved.applicable) continue;
    if (reviewState.renderActualCard && !resolved.visible) continue;
    const { actualColumn, visibilityColumn, targetColumn } = resolved;
    const targetBinding = difference.traceBinding.targetEffect;
    const targetEffectIndex = targetColumn
      ? (targetColumn.entry.effects.workloads || []).findIndex((workloadId) => workloadId === targetBinding.workloadID)
      : -1;
    const targetEffectReached = targetColumn != null && targetEffectIndex >= 0;
    const targetAnchorReached = columns.some(({ milestones }) => milestones?.includes(difference.target.anchor));
    const projection = {
      difference,
      actualColumn,
      visibilityColumn,
      targetColumn: targetEffectReached ? targetColumn : null,
      targetEffectIndex,
      targetAnchorReached,
      reviewState
    };

    if (reviewState.renderActualCard) {
      const actuals = actualBySequence.get(visibilityColumn.entry.seq) || [];
      actuals.push(projection);
      actualBySequence.set(visibilityColumn.entry.seq, actuals);
    }
    if (targetEffectReached) {
      targetByEffect.set(
        timingWorkloadEffectKey(targetColumn.entry.seq, targetBinding.workloadID, targetEffectIndex),
        projection
      );
    }
  }

  return { actualBySequence, targetByEffect };
}

function makeTimingWorkloadActual(projection) {
  const {
    difference,
    actualColumn,
    visibilityColumn,
    targetColumn,
    targetEffectIndex,
    targetAnchorReached,
    reviewState
  } = projection;
  const targetEffectReached = targetColumn != null;
  const kindLabel = workloadDifferenceLabels[difference.differenceKind] || difference.differenceKind;
  const outcome = fix0809OutcomeFor(difference);
  const actual = document.createElement("button");
  actual.type = "button";
  actual.id = `timing-workload-actual-${timingDOMID(difference.id)}`;
  actual.className = "timing-workload-actual";
  actual.dataset.workloadDifferenceActualId = difference.id;
  actual.dataset.differenceType = difference.differenceType;
  actual.dataset.actualWorkloadId = difference.actual.workloadID;
  actual.dataset.targetWorkloadId = difference.target.workloadID;
  actual.dataset.actualAnchor = difference.actual.anchor;
  actual.dataset.targetAnchor = difference.target.anchor;
  actual.dataset.targetEffectReached = String(targetEffectReached);
  actual.dataset.targetAnchorReached = String(targetAnchorReached);
  actual.dataset.lifecycleTruthIds = difference.lifecycleTruthIDs.join(" ");
  actual.dataset.scopePath = difference.scope.path;
  actual.dataset.fix0809Disposition = difference.fix0809Disposition;
  actual.dataset.fix0809Outcome = difference.fix0809Outcome;
  actual.dataset.reviewState = difference.reviewState;
  actual.dataset.scenarioGroupId = difference.traceBinding.scenarioGroupID;
  actual.dataset.actualVisibleSeq = String(visibilityColumn.entry.seq);
  actual.dataset.actualAnchorReached = String(actualColumn != null);
  actual.dataset.actualAnchorSeq = actualColumn ? String(actualColumn.entry.seq) : "";
  actual.dataset.focusSeq = String(visibilityColumn.entry.seq);
  actual.setAttribute("aria-current", String(focusedTrace()?.seq === visibilityColumn.entry.seq));
  if (targetEffectReached) {
    actual.dataset.targetElementId = timingWorkloadEffectDOMID(
      targetColumn.entry.seq,
      difference.traceBinding.targetEffect.workloadID,
      targetEffectIndex
    );
  }
  actual.setAttribute(
    "aria-label",
    `${difference.actual.label}。仍有位置差异。${reviewState.accessibleLabel}。${outcome ? `${outcome.accessibleLabel}。` : ""}差异：${kindLabel}；检查点：${difference.checkpoint}。真实来源范围：${difference.scope.path}；真实触发：${difference.scope.trigger}。审阅投影点：事件 #${visibilityColumn.entry.seq} ${eventLabels[visibilityColumn.entry.event.type] || visibilityColumn.entry.event.type}；该点只控制差异何时显示，不代表真实 workload 在此执行。Actual 阶段：${difference.actual.anchor}，${difference.actual.phase}。对应 Target Workload：${difference.target.label}；既有 Target effect ${targetEffectReached ? "已出现" : "尚未出现"}。目标生命周期：${difference.target.anchor} ${targetAnchorReached ? "已到达" : "尚未到达"}，${difference.target.phase}。${reviewState.taskLabel} ${difference.followUpTaskIDs.join("、")}。按下后聚焦该 reviewer visibility/upstream 投影事件；生命周期归属仍是 ${difference.actual.anchor}。`
  );

  const verdict = document.createElement("em");
  verdict.textContent = "Actual · 仍有位置差异";
  const outcomeBadge = makeFix0809OutcomeBadge(difference);
  const taskBadge = makeFollowUpTaskBadge(difference);
  const label = document.createElement("strong");
  label.textContent = difference.actual.label;
  const kind = document.createElement("small");
  kind.className = "timing-workload-difference-kind";
  kind.textContent = `${kindLabel} · ${difference.checkpoint}`;
  const sourceScope = document.createElement("small");
  sourceScope.className = "timing-workload-source-scope";
  sourceScope.textContent = `真实触发 · ${difference.scope.path} · ${difference.scope.trigger}`;
  const projectionScope = document.createElement("small");
  projectionScope.className = "timing-workload-projection-scope";
  projectionScope.textContent = `审阅投影 · after #${visibilityColumn.entry.seq} ${eventLabels[visibilityColumn.entry.event.type] || visibilityColumn.entry.event.type} · 非实际执行点`;
  const phase = document.createElement("small");
  phase.textContent = `${difference.actual.anchor} · ${difference.actual.phase}`;
  const targetStatus = document.createElement("span");
  targetStatus.className = "timing-workload-target-status";
  targetStatus.textContent = `对应原型 Workload · ${difference.target.label} · 既有 trace effect ${targetEffectReached ? "已出现" : "尚未出现"}`;
  const targetPhase = document.createElement("small");
  targetPhase.className = "timing-workload-target-phase";
  targetPhase.textContent = `目标生命周期 · ${difference.target.anchor} ${targetAnchorReached ? "已到达" : "尚未到达"} · ${difference.target.phase}`;
  actual.append(verdict);
  if (outcomeBadge) actual.append(outcomeBadge);
  actual.append(label, kind, sourceScope, projectionScope, phase, targetStatus, targetPhase);
  if (taskBadge) actual.append(taskBadge);
  actual.title = `实际：${difference.actual.summary}\n目标：${difference.target.summary}\n代码：${difference.actual.evidence}\n契约：${difference.target.evidence}`;
  return actual;
}

function makeTimingWorkloadTraceEffect(workloadId, effectIndex, entry, stateAfter, targetProjection = null) {
  const registry = workloadRegistry[workloadId];
  const status = stateAfter?.workloads?.[workloadId];
  const statusLabel = status ? statusLabels[status] || status : null;
  const button = makeCausalEvent(
    `${registry?.label || workloadId}${statusLabel ? ` · ${statusLabel}` : ""}`,
    entry.seq
  );
  button.id = timingWorkloadEffectDOMID(entry.seq, workloadId, effectIndex);
  button.classList.add("timing-workload-trace-effect");
  button.dataset.workloadId = workloadId;
  button.dataset.workloadEffectIndex = String(effectIndex);
  button.title = `原型 reducer trace · ${registry?.family || "work"}`;
  button.setAttribute(
    "aria-label",
    `原型 reducer workload：${registry?.label || workloadId}${statusLabel ? `，状态 ${statusLabel}` : ""}。事件 #${entry.seq} ${eventLabels[entry.event.type] || entry.event.type}。按下后聚焦该 reducer 事件。`
  );
  if (targetProjection) {
    const { difference, reviewState } = targetProjection;
    const disposition = fix0809DispositionFor(difference);
    button.dataset.targetAnchor = difference.target.anchor;
    button.dataset.fix0809Disposition = difference.fix0809Disposition;
    button.dataset.reviewState = difference.reviewState;
    const targetBadge = document.createElement("span");
    targetBadge.className = "timing-workload-target-badge";
    const taskBadge = makeFollowUpTaskBadge(difference);
    if (reviewState.decorateTarget) {
      button.classList.add("is-workload-follow-up-target");
      button.dataset.workloadFollowUpTargetId = difference.id;
      button.dataset.fix0809Outcome = difference.fix0809Outcome;
      targetBadge.textContent = `Candidate / Target Workload · ${difference.target.anchor}`;
      const outcomeBadge = makeFix0809OutcomeBadge(difference);
      button.append(targetBadge);
      if (outcomeBadge) button.append(outcomeBadge);
      if (taskBadge) button.append(taskBadge);
      button.title = `${reviewState.visibleLabel} · Candidate 已在目标生命周期 ${difference.target.anchor} · ${button.title}`;
      button.setAttribute(
        "aria-label",
        `Candidate 已在既有 Target Workload effect。${reviewState.accessibleLabel}。目标生命周期 ${difference.target.anchor} ${targetProjection.targetAnchorReached ? "已到达" : "尚未到达"}。${reviewState.taskLabel} ${difference.followUpTaskIDs.join("、")}。原型 reducer workload：${registry?.label || workloadId}${statusLabel ? `，状态 ${statusLabel}` : ""}。事件 #${entry.seq} ${eventLabels[entry.event.type] || entry.event.type}。按下后聚焦该 reducer 事件。`
      );
    } else if (reviewState.activeDifference) {
      button.classList.add("is-workload-difference-target");
      button.dataset.workloadDifferenceTargetId = difference.id;
      if (reviewState.renderActualCard) {
        button.dataset.actualAnnotationId = `timing-workload-actual-${timingDOMID(difference.id)}`;
      }
      targetBadge.textContent = `Prototype Target · ${difference.target.anchor}`;
      button.append(targetBadge);
      if (taskBadge) button.append(taskBadge);
      button.title = `${disposition ? `${disposition.visibleLabel} · ` : ""}既有 Target Workload effect · 目标生命周期 ${difference.target.anchor} ${targetProjection.targetAnchorReached ? "已到达" : "尚未到达"} · ${button.title}`;
      button.setAttribute(
        "aria-label",
        `既有 Prototype Target Workload effect。${reviewState.accessibleLabel}。${disposition ? `${disposition.accessibleLabel}。` : ""}对应目标生命周期 ${difference.target.anchor} ${targetProjection.targetAnchorReached ? "已到达" : "尚未到达"}。${reviewState.taskLabel} ${difference.followUpTaskIDs.join("、")}。原型 reducer workload：${registry?.label || workloadId}${statusLabel ? `，状态 ${statusLabel}` : ""}。事件 #${entry.seq} ${eventLabels[entry.event.type] || entry.event.type}。按下后聚焦该 reducer 事件。`
      );
    }
  }
  return button;
}

let timingDifferenceConnectorFrame = null;

function renderTimingDifferenceConnectors() {
  timingDifferenceConnectorFrame = null;
  const timingView = byID("timing-event-view");
  const grid = timingView.querySelector(".timing-axis-grid");
  const svg = timingView.querySelector(".timing-difference-connectors");
  if (!grid || !svg || timingView.hidden) return;

  const gridRect = grid.getBoundingClientRect();
  svg.replaceChildren();
  svg.setAttribute("viewBox", `0 0 ${grid.scrollWidth} ${grid.scrollHeight}`);
  svg.setAttribute("width", String(grid.scrollWidth));
  svg.setAttribute("height", String(grid.scrollHeight));
  const namespace = "http://www.w3.org/2000/svg";
  const lifecycleCards = [...grid.querySelectorAll("[data-timing-difference-id]")];
  lifecycleCards.forEach((card) => {
    const anchorID = card.dataset.timingActualAnchor;
    const anchor = grid.querySelector(`[data-timing-lifecycle-anchor-id="${anchorID}"]`);
    if (!anchor) return;
    const peers = lifecycleCards.filter((candidate) => candidate.dataset.timingActualAnchor === anchorID);
    const peerIndex = peers.indexOf(card);
    const anchorRect = anchor.getBoundingClientRect();
    const cardRect = card.getBoundingClientRect();
    const startX = anchorRect.left + anchorRect.width / 2 - gridRect.left + (peerIndex - (peers.length - 1) / 2) * 2;
    const startY = anchorRect.bottom - gridRect.top;
    const railX = cardRect.left - gridRect.left - 4 - peerIndex * 2.2;
    const endX = cardRect.left - gridRect.left;
    const endY = cardRect.top + Math.min(12, cardRect.height / 2) - gridRect.top;
    const path = document.createElementNS(namespace, "path");
    path.setAttribute("d", `M ${startX} ${startY} C ${startX} ${startY + 6}, ${railX} ${startY + 6}, ${railX} ${startY + 12} L ${railX} ${endY} L ${endX} ${endY}`);
    path.dataset.timingConnectorId = card.dataset.timingDifferenceId;
    path.dataset.targetAnchorId = anchorID;
    path.classList.add("timing-difference-connector");
    svg.append(path);
  });
  let workloadConnectorCount = 0;
  const actualCards = [...grid.querySelectorAll("[data-workload-difference-actual-id]")];
  actualCards.forEach((actual) => {
    const targetID = actual.dataset.targetElementId;
    const target = targetID ? byID(targetID) : null;
    if (!target || !grid.contains(target)) return;

    const actualRect = actual.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    const sameColumn = actual.closest(".timing-interval-column") === target.closest(".timing-interval-column");
    let pathData;
    if (sameColumn) {
      const startX = actualRect.left + actualRect.width / 2 - gridRect.left;
      const startY = actualRect.bottom - gridRect.top;
      const endX = targetRect.left + targetRect.width / 2 - gridRect.left;
      const endY = targetRect.top - gridRect.top;
      const bend = Math.max(7, Math.abs(endY - startY) / 2);
      pathData = `M ${startX} ${startY} C ${startX} ${startY + bend}, ${endX} ${endY - bend}, ${endX} ${endY}`;
    } else {
      const targetIsRight = targetRect.left >= actualRect.left;
      const startX = (targetIsRight ? actualRect.right : actualRect.left) - gridRect.left;
      const startY = actualRect.top + actualRect.height / 2 - gridRect.top;
      const endX = (targetIsRight ? targetRect.left : targetRect.right) - gridRect.left;
      const endY = targetRect.top + targetRect.height / 2 - gridRect.top;
      const bend = Math.max(18, Math.abs(endX - startX) * 0.42);
      pathData = targetIsRight
        ? `M ${startX} ${startY} C ${startX + bend} ${startY}, ${endX - bend} ${endY}, ${endX} ${endY}`
        : `M ${startX} ${startY} C ${startX - bend} ${startY}, ${endX + bend} ${endY}, ${endX} ${endY}`;
    }

    const path = document.createElementNS(namespace, "path");
    path.setAttribute("d", pathData);
    path.dataset.workloadDifferenceConnectorId = actual.dataset.workloadDifferenceActualId;
    path.dataset.actualElementId = actual.id;
    path.dataset.targetElementId = target.id;
    path.classList.add("timing-workload-difference-connector");
    svg.append(path);
    workloadConnectorCount += 1;
  });
  svg.dataset.workloadConnectorCount = String(workloadConnectorCount);
  svg.dataset.connectorCount = String(svg.childElementCount);
}

function scheduleTimingDifferenceConnectors() {
  if (timingDifferenceConnectorFrame != null) window.cancelAnimationFrame(timingDifferenceConnectorFrame);
  timingDifferenceConnectorFrame = window.requestAnimationFrame(renderTimingDifferenceConnectors);
}

function renderTimingEventView() {
  const columns = timingColumns();
  const grid = document.createElement("div");
  grid.className = "timing-axis-grid";
  grid.style.setProperty("--timing-event-count", String(Math.max(1, columns.length)));

  if (!columns.length) {
    const empty = document.createElement("p");
    empty.className = "supporting-copy";
    empty.textContent = "尚无 reducer trace；选择 UI 或启动场景后，将按 timing 与因果泳道显示。";
    grid.append(empty);
    byID("timing-event-view").replaceChildren(grid);
    scheduleTimingDifferenceConnectors();
    return;
  }

  grid.append(makeTimingLane("Timing", "timing", columns, ({ entry, interval, milestone, milestones }) => {
    const button = makeCausalEvent(milestone || interval, entry.seq);
    button.classList.add("timing-axis-event");
    const detail = document.createElement("small");
    detail.textContent = milestone ? interval : `#${entry.seq}`;
    button.append(detail);
    milestones.forEach((milestoneID) => {
      const anchor = document.createElement("span");
      anchor.className = "timing-milestone-anchor";
      anchor.dataset.timingLifecycleAnchorId = milestoneID;
      anchor.textContent = milestoneID;
      anchor.classList.toggle(
        "has-lifecycle-difference",
        lifecycleTruthRegistry.some((truth) => (
          truth.mismatch
          && lifecycleTimingLaneRecordIDSet.has(truth.id)
          && truth.activeDifference
          && reviewStateFor(truth)?.renderConnector
          && truth.actual.anchor === milestoneID
        ))
      );
      anchor.classList.toggle(
        "has-lifecycle-follow-up",
        lifecycleTruthRegistry.some((truth) => (
          truth.mismatch
          && lifecycleTimingLaneRecordIDSet.has(truth.id)
          && reviewStateFor(truth)?.projectionMode === "mergeIntoTarget"
          && truth.targetBinding.anchor === milestoneID
        ))
      );
      button.append(anchor);
    });
    return button;
  }));

  grid.append(makeTimingLane("08/09 生命周期", "difference", columns, ({ milestones }) => {
    const reached = new Set(milestones);
    const differences = lifecycleTruthRegistry.filter((truth) => (
      truth.mismatch
      && lifecycleTimingLaneRecordIDSet.has(truth.id)
      && reached.has(lifecycleProjectionAnchor(truth))
    ));
    if (!differences.length) return null;
    const stack = document.createElement("div");
    stack.className = "timing-difference-stack";
    stack.append(...differences.map(makeTimingLifecycleReviewCard));
    return stack;
  }));

  grid.append(makeTimingLane("UI", "ui", columns, ({ entry }) => {
    if (entry.pageBefore === entry.pageAfter) return null;
    return makeCausalEvent(
      `${pageLabels[entry.pageBefore] || entry.pageBefore} → ${pageLabels[entry.pageAfter] || entry.pageAfter}`,
      entry.seq
    );
  }));

  grid.append(makeTimingLane("Reducer", "reducer", columns, ({ entry }) => makeCausalEvent(
    `#${entry.seq} · ${eventLabels[entry.event.type] || entry.event.type}`,
    entry.seq,
    { primary: true }
  )));

  const workloadDifferenceProjection = buildTimingWorkloadDifferenceProjection(columns);
  grid.append(makeTimingLane("Workload", "workload", columns, ({ entry, stateAfter }) => {
    const differences = workloadDifferenceProjection.actualBySequence.get(entry.seq) || [];
    const traceWorkloadIds = entry.effects.workloads || [];
    if (!differences.length && !traceWorkloadIds.length) return null;
    const stack = document.createElement("div");
    stack.className = "timing-workload-stack";
    stack.append(
      ...differences.map(makeTimingWorkloadActual),
      ...traceWorkloadIds.map((workloadId, effectIndex) => makeTimingWorkloadTraceEffect(
        workloadId,
        effectIndex,
        entry,
        stateAfter,
        workloadDifferenceProjection.targetByEffect.get(timingWorkloadEffectKey(entry.seq, workloadId, effectIndex)) || null
      ))
    );
    return stack;
  }));

  grid.append(makeTimingLane("Marker", "marker", columns, ({ entry }) => {
    const markers = entry.effects.markers || [];
    if (!markers.length) return null;
    const details = markers.map((marker) => `${marker.id}: ${compactEffectValue(marker.from)} → ${compactEffectValue(marker.to)}`);
    const button = makeCausalEvent(markers.length === 1 ? details[0] : `${markers.length} marker effects · ${markers[0].id}`, entry.seq);
    button.title = details.join("\n");
    return button;
  }));

  const connectorSVG = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  connectorSVG.classList.add("timing-difference-connectors");
  connectorSVG.setAttribute("aria-hidden", "true");
  connectorSVG.setAttribute("focusable", "false");
  grid.append(connectorSVG);

  const timingView = byID("timing-event-view");
  timingView.replaceChildren(grid);
  const focusedColumn = timingView.querySelector(`[data-causal-seq="${focusedTrace()?.seq ?? ""}"]`);
  if (focusedColumn) {
    timingView.scrollLeft = Math.max(0, focusedColumn.offsetLeft - timingView.clientWidth + focusedColumn.offsetWidth + 12);
  }
  scheduleTimingDifferenceConnectors();
}

function renderEventViews() {
  const timing = byID("timing-event-view");
  const log = byID("event-log");
  timing.hidden = eventViewMode !== "timing";
  log.hidden = eventViewMode !== "log";
  document.querySelectorAll("[data-event-view]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.eventView === eventViewMode));
  });
  document.documentElement.dataset.prototypeEventView = eventViewMode;
  if (eventViewMode === "timing") scheduleTimingDifferenceConnectors();
}

function renderAll() {
  renderScenarioControls();
  renderPhone();
  renderSurfaceCatalog();
  renderSurfaceOperations();
  renderTimeline();
  renderMachines();
  renderSurfaceBusiness();
  renderTapShareInspector();
  renderTraceEffects();
  renderWorkloads();
  renderEventLog();
  renderTimingEventView();
  renderEventViews();
  document.documentElement.dataset.prototypeRevision = REVISION;
  document.documentElement.dataset.prototypePage = state.phone.page;
  document.documentElement.dataset.prototypeSurface = currentReviewSurface() || "none";
  document.documentElement.dataset.prototypeScenario = state.scenarioId;
  document.documentElement.dataset.prototypeSeq = String(state.seq);
  document.documentElement.dataset.prototypeEventView = eventViewMode;
}

function focusTraceSequence(seq) {
  const normalized = Number(seq);
  focusSeq = state.log.some((entry) => entry.seq === normalized) ? normalized : state.log.at(-1)?.seq ?? null;
  selectedWorkloadId = null;
  renderAll();
  return snapshot();
}

byID("scenario-select").addEventListener("change", (event) => reset(event.target.value));
document.querySelectorAll("[data-review-surface]").forEach((button) => {
  if (button.disabled) return;
  button.addEventListener("click", () => openSurface(button.dataset.reviewSurface));
});
byID("activate-button").addEventListener("click", startScenario);
byID("previous-button").addEventListener("click", stepBack);
byID("next-button").addEventListener("click", advance);
byID("reset-button").addEventListener("click", () => reset());
byID("auto-transition-toggle").addEventListener("change", () => {
  clearLaunchTransition();
  scheduleStartupTransitionIfNeeded();
});
byID("debugger-toggle").addEventListener("change", (event) => {
  dispatch({ type: "MEASUREMENT_PROFILE_CHANGED", measurement: { debuggerAttached: event.target.checked } });
});
document.querySelectorAll("[data-measurement-build]").forEach((button) => {
  button.addEventListener("click", () => dispatch({ type: "MEASUREMENT_PROFILE_CHANGED", measurement: { build: button.dataset.measurementBuild } }));
});
document.querySelectorAll("[data-workload-filter]").forEach((button) => {
  button.addEventListener("click", () => {
    workloadFilter = button.dataset.workloadFilter;
    document.querySelectorAll("[data-workload-filter]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
    renderWorkloads();
  });
});
byID("workload-list").addEventListener("scroll", scheduleLifecycleDifferenceConnectors, { passive: true });
byID("timing-event-view").addEventListener("scroll", scheduleTimingDifferenceConnectors, { passive: true });
window.addEventListener("resize", scheduleLifecycleDifferenceConnectors, { passive: true });
window.addEventListener("resize", scheduleTimingDifferenceConnectors, { passive: true });
const lifecycleConnectorResizeObserver = new ResizeObserver(scheduleLifecycleDifferenceConnectors);
lifecycleConnectorResizeObserver.observe(document.querySelector(".inspector-panel"));
lifecycleConnectorResizeObserver.observe(byID("workload-list"));
const timingConnectorResizeObserver = new ResizeObserver(scheduleTimingDifferenceConnectors);
timingConnectorResizeObserver.observe(byID("timing-event-view"));
byID("workload-list").addEventListener("click", (event) => {
  const card = event.target.closest("[data-workload-id]");
  if (!card) return;
  focusWorkload(card.dataset.workloadId);
});
byID("follow-latest").addEventListener("click", () => {
  focusSeq = state.log.at(-1)?.seq ?? null;
  selectedWorkloadId = null;
  renderAll();
});
byID("event-log").addEventListener("click", (event) => {
  const button = event.target.closest("[data-focus-seq]");
  if (!button) return;
  focusTraceSequence(button.dataset.focusSeq);
});
byID("timing-event-view").addEventListener("click", (event) => {
  const button = event.target.closest("[data-focus-seq]");
  if (!button) return;
  focusTraceSequence(button.dataset.focusSeq);
});
byID("machine-flow-diagram").addEventListener("click", (event) => {
  const button = event.target.closest("[data-focus-seq]");
  if (!button) return;
  focusTraceSequence(button.dataset.focusSeq);
});
byID("machine-flow-select").addEventListener("change", (event) => {
  if (!machineRegistry[event.target.value]) return;
  selectedMachineId = event.target.value;
  selectedMachineFocusSeq = focusedTrace()?.seq ?? `page:${state.phone.page}:${state.seq}`;
  renderMachines();
});
byID("surface-business-machines").addEventListener("click", (event) => {
  const button = event.target.closest("[data-business-machine]");
  if (!button || !machineRegistry[button.dataset.businessMachine]) return;
  selectedMachineId = button.dataset.businessMachine;
  selectedMachineFocusSeq = focusedTrace()?.seq ?? `page:${state.phone.page}:${state.seq}`;
  renderMachines();
  renderSurfaceBusiness();
});
document.querySelectorAll("[data-event-view]").forEach((button) => {
  button.addEventListener("click", () => {
    eventViewMode = button.dataset.eventView === "log" ? "log" : "timing";
    renderEventViews();
  });
});

byID("phone-surface").addEventListener("click", (event) => {
  const target = event.target.closest("[data-phone-action]");
  if (!target || target.disabled) return;
  const action = target.dataset.phoneAction;
  const prototypeEvent = prototypeEventForControl(target);
  if (prototypeEvent) {
    if (canReduce(state, prototypeEvent)) dispatch(prototypeEvent);
  } else if (action === "open-library") {
    if (state.milestones.t5 == null) dispatch({ type: "DEFERRED_WORK_RELEASED" }, { announce: false });
    dispatch({ type: "LIBRARY_OPENED" });
  } else if (action === "library-back") {
    dispatch({ type: "LIBRARY_BACK_TAPPED" });
  } else if (action === "open-photo") {
    dispatch({ type: "PHOTO_OPENED", assetId: target.dataset.assetId });
  } else if (action === "viewer-back") {
    if (!dismissTapSharePresentation({ restoreFocus: true })) dispatch({ type: "VIEWER_BACK_TAPPED" });
  }
});

tapShareSlice = mountTapShareSlice({
  root: document.querySelector("[data-tap0081-share]"),
  trigger: document.querySelector("[data-existing-share-boundary]"),
  onStateChange(shareSnapshot, { reason }) {
    renderTapShareInspector(shareSnapshot);
    if (!["mounted", "resource.rendered"].includes(reason)) {
      byID("prototype-announcement").textContent = `TAP Share 本地状态：${shareSnapshot.panel}。TAP-0087 seq ${state.seq} 未改变。`;
    }
  }
});

window.__tapCamStartupPrototype = Object.freeze({
  schemaVersion: 1,
  revision: REVISION,
  dispatch,
  next: advance,
  back: stepBack,
  reset,
  openSurface,
  snapshot,
  scenarios: () => clone(Object.values(scenarioFixtures).map(({ id, label, summary, installationContext }) => ({ id, label, summary, installationContext }))),
  focus(seq = null) {
    if (seq == null) {
      focusSeq = state.log.at(-1)?.seq ?? null;
      renderAll();
      return snapshot();
    }
    return focusTraceSequence(seq);
  },
  focusWorkload,
  share: () => tapShareSlice.snapshot()
});

byID("auto-transition-toggle").checked = initialReviewEntry.autoTransition;
renderAll();
