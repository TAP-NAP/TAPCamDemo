const clone = (value) => JSON.parse(JSON.stringify(value));

async function loadPrototypeManifest() {
  const manifestURL = new URL("./manifest.json", import.meta.url);
  if (manifestURL.protocol === "file:") {
    const { readFile } = await import("node:fs/promises");
    return JSON.parse(await readFile(manifestURL, "utf8"));
  }
  const response = await fetch(manifestURL, { cache: "no-store" });
  if (!response.ok) throw new Error(`Unable to load prototype manifest: ${response.status}`);
  return response.json();
}

let prototypeDifferenceDataError = null;
const prototypeManifest = await loadPrototypeManifest().catch((error) => {
  prototypeDifferenceDataError = error instanceof Error ? error.message : String(error);
  return null;
});
const loadedLifecycleDifferenceManifest = prototypeManifest
  ?.independentCandidates
  ?.startupLifecycle
  ?.workbench
  ?.right
  ?.tap0008Tap0009CodeTruth;
const lifecycleDifferenceManifest = Array.isArray(loadedLifecycleDifferenceManifest?.records)
  ? loadedLifecycleDifferenceManifest
  : { records: [], timingProjection: {}, workloadDifferenceComparison: { records: [] }, fix0809DispositionCatalog: {}, fix0809OutcomeCatalog: {} };
const loadedFix0809DispositionCatalog = lifecycleDifferenceManifest.fix0809DispositionCatalog;
const fix0809DispositionCatalog = (
  loadedFix0809DispositionCatalog
  && typeof loadedFix0809DispositionCatalog === "object"
  && !Array.isArray(loadedFix0809DispositionCatalog)
  && Object.values(loadedFix0809DispositionCatalog).every((disposition) => (
    disposition
    && typeof disposition === "object"
    && typeof disposition.visibleLabel === "string"
    && typeof disposition.accessibleLabel === "string"
    && typeof disposition.includedInFix0809 === "boolean"
    && disposition.renderAsMismatch === true
  ))
)
  ? loadedFix0809DispositionCatalog
  : {};
const loadedFix0809OutcomeCatalog = lifecycleDifferenceManifest.fix0809OutcomeCatalog;
const fix0809OutcomeCatalog = (
  loadedFix0809OutcomeCatalog
  && typeof loadedFix0809OutcomeCatalog === "object"
  && !Array.isArray(loadedFix0809OutcomeCatalog)
  && Object.values(loadedFix0809OutcomeCatalog).every((outcome) => (
    outcome
    && typeof outcome === "object"
    && typeof outcome.visibleLabel === "string"
    && typeof outcome.accessibleLabel === "string"
    && ["implemented", "frozen"].includes(outcome.implementationState)
    && ["deviceLogAccepted", "notCoveredByDeviceLog", "notApplicable"].includes(outcome.verificationState)
    && ["yellow", "red"].includes(outcome.fillTone)
    && ["yellow", "red"].includes(outcome.borderTone)
    && outcome.preservesBaselineMismatch === true
  ))
)
  ? loadedFix0809OutcomeCatalog
  : {};
const loadedWorkloadDifferenceManifest = lifecycleDifferenceManifest.workloadDifferenceComparison;
const workloadDifferenceManifest = Array.isArray(loadedWorkloadDifferenceManifest?.records)
  ? loadedWorkloadDifferenceManifest
  : { records: [], scenarioGroups: {} };
const loadedWorkloadDifferenceScenarioGroups = workloadDifferenceManifest.scenarioGroups;
const workloadDifferenceScenarioGroups = (
  loadedWorkloadDifferenceScenarioGroups
  && typeof loadedWorkloadDifferenceScenarioGroups === "object"
  && !Array.isArray(loadedWorkloadDifferenceScenarioGroups)
  && Object.values(loadedWorkloadDifferenceScenarioGroups).every((scenarioIDs) => Array.isArray(scenarioIDs))
)
  ? loadedWorkloadDifferenceScenarioGroups
  : {};
const loadedTimingProjection = lifecycleDifferenceManifest.timingProjection;
const timingProjection = (
  Array.isArray(loadedTimingProjection?.lifecycleLaneRecordIDs)
  && Array.isArray(loadedTimingProjection?.workloadLaneTruthRecordIDs)
)
  ? loadedTimingProjection
  : { lifecycleLaneRecordIDs: [], workloadLaneTruthRecordIDs: [] };
if (
  !prototypeDifferenceDataError
  && (
    lifecycleDifferenceManifest !== loadedLifecycleDifferenceManifest
    || fix0809DispositionCatalog !== loadedFix0809DispositionCatalog
    || fix0809OutcomeCatalog !== loadedFix0809OutcomeCatalog
    || workloadDifferenceManifest !== loadedWorkloadDifferenceManifest
    || workloadDifferenceScenarioGroups !== loadedWorkloadDifferenceScenarioGroups
    || timingProjection !== loadedTimingProjection
  )
) {
  prototypeDifferenceDataError = "Prototype difference manifest has an invalid record shape";
}

export const PROTOTYPE_DIFFERENCE_DATA_SOURCE = "Prototype/manifest.json";
export const PROTOTYPE_DIFFERENCE_DATA_STATUS = Object.freeze({
  loaded: prototypeDifferenceDataError == null,
  error: prototypeDifferenceDataError
});
export const lifecycleTruthRegistry = Object.freeze(clone(lifecycleDifferenceManifest.records));
export const fix0809DispositionRegistry = Object.freeze(clone(fix0809DispositionCatalog));
export const fix0809OutcomeRegistry = Object.freeze(clone(fix0809OutcomeCatalog));
export const lifecycleTimingLaneRecordIDs = Object.freeze(clone(timingProjection.lifecycleLaneRecordIDs));
export const workloadLaneTruthRecordIDs = Object.freeze(clone(timingProjection.workloadLaneTruthRecordIDs));
export const workloadDifferenceRegistry = Object.freeze(clone(workloadDifferenceManifest.records));
export const workloadDifferenceScenarioRegistry = Object.freeze(clone(workloadDifferenceScenarioGroups));

function occurrenceMatch(columns, matcher, { requireWorkload = false } = {}) {
  const eventTypes = Array.isArray(matcher?.eventTypes) ? matcher.eventTypes : [];
  const occurrence = Number.isInteger(matcher?.occurrence) && matcher.occurrence > 0 ? matcher.occurrence : 1;
  const matches = columns.filter(({ entry, stateAfter }) => {
    if (!eventTypes.includes(entry?.event?.type)) return false;
    if (!requireWorkload) return true;
    const workloadID = matcher.workloadID;
    if (!entry?.effects?.workloads?.includes(workloadID)) return false;
    return matcher.status == null || stateAfter?.workloads?.[workloadID] === matcher.status;
  });
  return matches[occurrence - 1] || null;
}

export function resolveWorkloadDifferenceTraceBinding(difference, scenarioID, columns) {
  const binding = difference?.traceBinding;
  const scenarioIDs = workloadDifferenceScenarioRegistry[binding?.scenarioGroupID];
  const applicable = Array.isArray(scenarioIDs) && scenarioIDs.includes(scenarioID);
  if (!applicable) {
    return Object.freeze({ applicable: false, visible: false, actualColumn: null, visibilityColumn: null, targetColumn: null });
  }

  const visibilityColumn = occurrenceMatch(columns, binding.actualVisibleAfter);
  const actualColumn = columns.find(({ milestones }) => milestones?.includes(difference.actual.anchor)) || null;
  const targetColumn = occurrenceMatch(columns, binding.targetEffect, { requireWorkload: true });
  return Object.freeze({
    applicable: true,
    visible: Boolean(visibilityColumn),
    actualColumn,
    visibilityColumn,
    targetColumn
  });
}

export const REVISION = "TAP-0087-r1-candidate";
export const TARGET_INITIALIZATION_IDENTITY = Object.freeze({
  bundleID: "com.tapnap.TAPCamDemo",
  shortVersion: "0.2",
  build: "2",
  schemaGeneration: "startup-g2",
  installationDeviceGeneration: "device-install-g2"
});

const makeInitializationIdentity = (overrides = {}) => ({
  ...TARGET_INITIALIZATION_IDENTITY,
  ...overrides
});

const basePermissions = Object.freeze({
  camera: "authorized",
  photos: "authorized",
  location: "skipped",
  microphone: "skipped"
});

const processLaunch = Object.freeze({ kind: "processLaunch", returnPage: null });

export const scenarioFixtures = Object.freeze({
  freshInstall: {
    id: "freshInstall",
    label: "Fresh Installation · 全新安装",
    summary: "New container. Initial App Attest, Camera, and Photos are required before Continue.",
    installationContext: "freshInstallation",
    activation: processLaunch,
    setupReceipt: { state: "absent", credentialBinding: "absent" },
    attestation: { bootstrap: "idle", network: "available", maintenance: "dormant" },
    permissions: { camera: "notDetermined", photos: "notDetermined", location: "notDetermined", microphone: "notDetermined" },
    initialization: { storedIdentity: null, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 18, thumbnails: "absent" },
    pendingQueueCount: 0,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  freshInstallOffline: {
    id: "freshInstallOffline",
    label: "Fresh Installation · 初始网络离线",
    summary: "The explicit Network row owns a bounded App Attest failure and Retry; the Setup page itself remains responsive.",
    installationContext: "freshInstallation",
    activation: processLaunch,
    setupReceipt: { state: "absent", credentialBinding: "absent" },
    attestation: { bootstrap: "idle", network: "offline", maintenance: "dormant" },
    permissions: { camera: "notDetermined", photos: "notDetermined", location: "notDetermined", microphone: "notDetermined" },
    initialization: { storedIdentity: null, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 18, thumbnails: "absent" },
    pendingQueueCount: 0,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  inPlaceUpdate: {
    id: "inPlaceUpdate",
    label: "In-place App Update · 原位更新",
    summary: "The Setup receipt and local credential binding survive; a changed build makes Resource Initialization stale.",
    installationContext: "inPlaceAppUpdate",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: makeInitializationIdentity({ shortVersion: "0.1", build: "1", schemaGeneration: "startup-g1" }), targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 908, thumbnails: "cold" },
    pendingQueueCount: 7,
    readinessOrder: "catalogFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  updateWithRevokedPhotos: {
    id: "updateWithRevokedPhotos",
    label: "In-place App Update · Photos 已撤销",
    summary: "Required Permission Check takes priority; after recovery the stale initialization marker routes to Resource Initialization.",
    installationContext: "inPlaceAppUpdate",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { ...basePermissions, photos: "denied" },
    initialization: { storedIdentity: makeInitializationIdentity({ shortVersion: "0.1", build: "1", schemaGeneration: "startup-g1" }), targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 908, thumbnails: "cold" },
    pendingQueueCount: 7,
    readinessOrder: "catalogFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  developmentReplacement: {
    id: "developmentReplacement",
    label: "Development Replacement Install · Xcode 覆盖安装（构建已变化）",
    summary: "A development install is diagnostic context only. The preserved facts route to Resource Initialization because the build identity changed.",
    installationContext: "developmentReplacementInstall",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "available", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: makeInitializationIdentity({ build: "1" }), targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 908, thumbnails: "cold" },
    pendingQueueCount: 7,
    readinessOrder: "cameraFirst",
    measurement: { build: "Debug", debuggerAttached: true, resourcePath: "cold" }
  },
  developmentReplacementSameBuild: {
    id: "developmentReplacementSameBuild",
    label: "Development Replacement Install · Xcode 覆盖安装（同一构建）",
    summary: "A same-build development replacement preserves current route facts; debugger attachment remains measurement metadata only.",
    installationContext: "developmentReplacementInstall",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "available", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 908, thumbnails: "cold" },
    pendingQueueCount: 7,
    readinessOrder: "cameraFirst",
    measurement: { build: "Debug", debuggerAttached: true, resourcePath: "cold" }
  },
  deleteReinstall: {
    id: "deleteReinstall",
    label: "Delete-and-Reinstall · 删除后重装",
    summary: "The new container cannot inherit Setup authority from possible Keychain residue.",
    installationContext: "deleteAndReinstall",
    activation: processLaunch,
    setupReceipt: { state: "absent", credentialBinding: "ignoredResidue" },
    attestation: { bootstrap: "idle", network: "available", maintenance: "dormant" },
    permissions: { camera: "notDetermined", photos: "notDetermined", location: "notDetermined", microphone: "notDetermined" },
    initialization: { storedIdentity: null, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 18, thumbnails: "absent" },
    pendingQueueCount: 0,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  offloadReinstall: {
    id: "offloadReinstall",
    label: "Offload-and-Reinstall · 保留数据卸载后重装",
    summary: "Preserved Setup and a current marker bypass Setup and Resource Initialization; empty caches do not change routing.",
    installationContext: "offloadAndReinstall",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { ...basePermissions, photos: "limited" },
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 18, thumbnails: "evicted" },
    pendingQueueCount: 2,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  offloadReinstallChangedBuild: {
    id: "offloadReinstallChangedBuild",
    label: "Offload-and-Reinstall · 保留数据卸载后重装（构建已变化）",
    summary: "The Setup receipt survives, while a changed build makes the independent initialization identity stale.",
    installationContext: "offloadAndReinstall",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { ...basePermissions, photos: "limited" },
    initialization: { storedIdentity: makeInitializationIdentity({ build: "1" }), targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 18, thumbnails: "evicted" },
    pendingQueueCount: 2,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  sameDeviceRestore: {
    id: "sameDeviceRestore",
    label: "Same-Device Backup Restore · 同设备恢复",
    summary: "The restored receipt lacks a locally bound App Attest system key, so Setup recovery re-runs credential bootstrap without replaying granted prompts.",
    installationContext: "sameDeviceBackupRestore",
    activation: processLaunch,
    setupReceipt: { state: "invalidCredentialBinding", credentialBinding: "missing" },
    attestation: { bootstrap: "idle", network: "available", maintenance: "dormant" },
    permissions: { ...basePermissions, location: "authorized", microphone: "authorized" },
    initialization: { storedIdentity: makeInitializationIdentity({ installationDeviceGeneration: "previous-device-install" }), targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 120, thumbnails: "absent" },
    pendingQueueCount: 4,
    readinessOrder: "catalogFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  sameDeviceRestoreValidBinding: {
    id: "sameDeviceRestoreValidBinding",
    label: "Same-Device Backup Restore · 有效本地凭据绑定",
    summary: "A restored Setup receipt with a valid local credential binding bypasses Setup; its stale restored initialization identity still requires Resource Initialization.",
    installationContext: "sameDeviceBackupRestore",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { ...basePermissions, location: "authorized", microphone: "authorized" },
    initialization: { storedIdentity: makeInitializationIdentity({ installationDeviceGeneration: "previous-device-install" }), targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 120, thumbnails: "absent" },
    pendingQueueCount: 4,
    readinessOrder: "catalogFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  crossDeviceMigration: {
    id: "crossDeviceMigration",
    label: "Cross-Device Migration Restore · 跨设备迁移恢复",
    summary: "Restored app data cannot prove a device-bound App Attest key on the new iPhone; Setup recovery precedes new-device initialization.",
    installationContext: "crossDeviceMigrationRestore",
    activation: processLaunch,
    setupReceipt: { state: "invalidCredentialBinding", credentialBinding: "missing" },
    attestation: { bootstrap: "idle", network: "available", maintenance: "dormant" },
    permissions: { camera: "authorized", photos: "limited", location: "authorized", microphone: "authorized" },
    initialization: { storedIdentity: makeInitializationIdentity({ installationDeviceGeneration: "source-device-install" }), targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 406, thumbnails: "absent" },
    pendingQueueCount: 9,
    readinessOrder: "catalogFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  localMarkerLoss: {
    id: "localMarkerLoss",
    label: "Local State Inconsistency · 初始化标记丢失",
    summary: "A valid Setup receipt is not reconstructed or replayed; the missing initialization fact routes directly to Resource Initialization.",
    installationContext: "localStateInconsistency",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: null, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 58, thumbnails: "warm" },
    pendingQueueCount: 1,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "mixed" }
  },
  interruptedInitialization: {
    id: "interruptedInitialization",
    label: "Interrupted Relaunch · 初始化中断后重启",
    summary: "Setup is valid, but the initialization marker was never atomically written; Resource Initialization resumes.",
    installationContext: "unchangedInstallation",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: null, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 58, thumbnails: "cold" },
    pendingQueueCount: 1,
    readinessOrder: "catalogFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  setupInterrupted: {
    id: "setupInterrupted",
    label: "First-Install Setup Interrupted · Continue 前中断",
    summary: "Required rows may already be complete, but an absent Setup receipt returns the next process launch to Setup until Continue is explicitly pressed.",
    installationContext: "unchangedInstallation",
    activation: processLaunch,
    setupReceipt: { state: "absent", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { camera: "authorized", photos: "limited", location: "notDetermined", microphone: "notDetermined" },
    initialization: { storedIdentity: null, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 18, thumbnails: "absent" },
    pendingQueueCount: 0,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  ordinaryProcessLaunch: {
    id: "ordinaryProcessLaunch",
    label: "Ordinary Later Process Launch · 普通后续进程启动",
    summary: "Current Setup, permissions, and initialization marker bypass the gates; cold resources still do not change the route.",
    installationContext: "unchangedInstallation",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "absent", itemCount: 58, thumbnails: "cold" },
    pendingQueueCount: 3,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "cold" }
  },
  ordinaryProcessLaunchEmptyLibrary: {
    id: "ordinaryProcessLaunchEmptyLibrary",
    label: "Ordinary Later Process Launch · 空 TAP Library",
    summary: "Current lifecycle facts enter Viewfinder normally; an empty published catalog is a successful Library state, not a startup failure.",
    installationContext: "unchangedInstallation",
    activation: processLaunch,
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "publishedEmpty", itemCount: 0, thumbnails: "ready" },
    pendingQueueCount: 0,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "warm" }
  },
  foregroundResumeRevoked: {
    id: "foregroundResumeRevoked",
    label: "Foreground Resume · Camera 已撤销",
    summary: "The existing process has no Launch Screen. A fresh required-permission snapshot enters Permission Check.",
    installationContext: "unchangedInstallation",
    activation: { kind: "foregroundResume", returnPage: "viewfinder" },
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { ...basePermissions, camera: "denied" },
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "publishedNonEmpty", itemCount: 58, thumbnails: "partial" },
    pendingQueueCount: 3,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "warm" }
  },
  foregroundResumeRestrictedCamera: {
    id: "foregroundResumeRestrictedCamera",
    label: "Foreground Resume · Camera 受系统限制",
    summary: "The running process resumes without a Launch Screen and shows a stable policy-restriction state with no false Settings recovery promise.",
    installationContext: "unchangedInstallation",
    activation: { kind: "foregroundResume", returnPage: "viewfinder" },
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { ...basePermissions, camera: "restricted" },
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "publishedNonEmpty", itemCount: 58, thumbnails: "partial" },
    pendingQueueCount: 3,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "warm" }
  },
  ordinaryForegroundResume: {
    id: "ordinaryForegroundResume",
    label: "Ordinary Foreground Resume · 普通前台恢复",
    summary: "A valid running process resumes without a Launch Screen and returns to the safe Viewfinder route.",
    installationContext: "unchangedInstallation",
    activation: { kind: "foregroundResume", returnPage: "viewfinder" },
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: basePermissions,
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "publishedNonEmpty", itemCount: 58, thumbnails: "partial" },
    pendingQueueCount: 3,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "warm" }
  },
  settingsReturn: {
    id: "settingsReturn",
    label: "Settings Return · 设置返回",
    summary: "Returning from Settings has no Launch Screen; the targeted Camera/Photos snapshot is already restored and the reducer returns to Viewfinder without replaying Setup.",
    installationContext: "unchangedInstallation",
    activation: { kind: "settingsReturn", returnPage: "viewfinder" },
    setupReceipt: { state: "valid", credentialBinding: "present" },
    attestation: { bootstrap: "ready", network: "offline", maintenance: "dormant" },
    permissions: { ...basePermissions, photos: "limited" },
    initialization: { storedIdentity: TARGET_INITIALIZATION_IDENTITY, targetIdentity: TARGET_INITIALIZATION_IDENTITY },
    library: { catalog: "publishedNonEmpty", itemCount: 58, thumbnails: "partial" },
    pendingQueueCount: 3,
    readinessOrder: "cameraFirst",
    measurement: { build: "Release", debuggerAttached: false, resourcePath: "warm" }
  }
});

export const timelineRegistry = Object.freeze([
  { id: "t0", label: "Activation Requested", interval: "Δt0–t1", allowed: "Minimal bootstrap", forbidden: "Library, camera discovery, network, analysis" },
  { id: "t1", label: "App First Frame", interval: "Δt1–t2", allowed: "Local facts + passive status", forbidden: "Prompt, catalog, media decode" },
  { id: "t2", label: "Route Committed", interval: "Δt2–t3", allowed: "Selected route work", forbidden: "Unrelated maintenance" },
  { id: "t3", label: "First Camera Preview Ready", interval: "Δt3–t4", allowed: "Real preview + remaining direct readiness blockers", forbidden: "Deferred contention" },
  { id: "t4", label: "Interactive Viewfinder Ready", interval: "Δt4–t5", allowed: "Release the deferred-work guard", forbidden: "Marker writes or new entry blockers" },
  { id: "t5", label: "Deferred Work Released", interval: "Δt5–tn", allowed: "Guarded maintenance + user-triggered work", forbidden: "Stale or unbounded publication" },
  { id: "tn", label: "Scenario Terminal", interval: "complete", allowed: "Stable target state", forbidden: "Performance inference from fixture timing" }
]);

export const machineRegistry = Object.freeze({
  activation: { label: "Activation", nodes: ["idle", "launchRequested", "sceneResumed", "appFirstFrame", "routeCommitted", "terminal"] },
  routeDecision: { label: "Route Decision", nodes: ["idle", "readingFacts", "firstInstallSetup", "requiredPermissionCheck", "resourceInitialization", "viewfinder"] },
  firstInstallSetup: { label: "First-Install Setup", nodes: ["notRequired", "awaitingExplicitActions", "credentialRecovery", "attestationRunning", "automaticRetryWaiting", "timedOutAwaitingExplicitRetry", "waitingSystem", "requiredReady", "completed"] },
  requiredPermissionCheck: { label: "Required Permission Check", nodes: ["notRequired", "inspecting", "awaitingAllow", "awaitingSettings", "restricted", "rechecking", "resolved"] },
  resourceInitialization: { label: "Resource Initialization", nodes: ["notRequired", "preparing", "cameraReadyCatalogPending", "catalogReadyCameraPending", "bothReady", "markerCommitted"] },
  cameraReadiness: { label: "Camera Readiness", nodes: ["idle", "shell", "configuring", "previewReady", "interactive"] },
  libraryCatalog: { label: "Library Catalog", nodes: ["dormant", "scheduled", "refreshing", "published", "stale"] },
  thumbnailPipeline: { label: "Thumbnail Pipeline", nodes: ["idle", "resolving", "ready", "cancelled"] },
  appAttestCredential: { label: "App Attest Credential", nodes: ["bootstrapIdle", "bootstrapRunning", "automaticRetryWaiting", "timedOutAwaitingExplicitRetry", "bootstrapReady", "dormant", "eligible", "preparing", "waitingNetwork", "ready", "failedRetryable"] },
  pendingCaptureRecovery: { label: "Pending Capture Recovery", nodes: ["dormant", "eligible", "reconciling", "processing", "quiescent", "blocked"] },
  viewerLoading: { label: "Photo Viewer Loading", nodes: ["closed", "shell", "displayLoading", "displayReady", "returning"] },
  viewerAnalysis: { label: "Viewer Analysis", nodes: ["deferredTAP0089"] },
  viewfinderControls: { label: "Viewfinder Controls", nodes: ["deferredTAP0088"] }
});

export const workloadStates = Object.freeze([
  "dormant",
  "waitingPrerequisite",
  "eligible",
  "scheduled",
  "running",
  "waitingSystem",
  "waitingNetwork",
  "succeeded",
  "failedRetryable",
  "failedTerminal",
  "cancelled",
  "stale",
  "skipped"
]);

export const workloadRegistry = Object.freeze({
  startupFacts: {
    label: "Lifecycle facts + permission snapshot", machineId: "routeDecision", family: "startup", pages: ["systemLaunchScreen", "firstAppFrame"], alignment: "gap",
    observed: { trigger: "App/root construction", owner: "MainActor + legacy StartupGate", earliest: "Δt0–t1 (inferred)", blocks: "Legacy Boolean route; snapshot is not consumed", network: "denied refresh may start /healthz", evidence: "App/StartupGateView.swift:16; App/StartupGateCoordinator.swift:90" },
    target: { trigger: "Activation facts read", owner: "Bounded structured S/P/I route snapshot", earliest: "Δt0–t1", blocks: "Route only", network: "never", forbiddenDuring: [], task: "TAP-0087 → TAP-0008/0009" }
  },
  libraryRootObservation: {
    label: "Library store + PhotoKit observer construction", machineId: "libraryCatalog", family: "library", pages: ["systemLaunchScreen", "firstInstallSetup", "viewfinder"], alignment: "gap",
    observed: { trigger: "TAPCamDemoApp.init", owner: "MainActor / LibraryMediaStore", earliest: "Δt0–t1 (synchronous)", blocks: "Consumes pre-frame path", network: "never", evidence: "App/TAPCamDemoApp.swift:37; MediaLibrary/LibraryMediaStore.swift:38" },
    target: { trigger: "Permission-safe route committed", owner: "Library owner", earliest: "after t2", blocks: "nothing", network: "never", forbiddenDuring: ["Δt0–t1"], task: "TAP-0087/TAP-0009" }
  },
  initialAttestation: {
    label: "First-install Network gate / target App Attest", machineId: "appAttestCredential", family: "attestation", pages: ["firstInstallSetup"], alignment: "gap",
    observed: { trigger: "Explicit Network row tap", owner: "MainActor + URLSession /healthz", earliest: "Setup action", blocks: "Setup Continue today", network: "required", evidence: "App/StartupBackendSecurityPreflight.swift:9,80" },
    target: { trigger: "Explicit Network row tap", owner: "AppAttestKit + DeviceCheck + backend", earliest: "after t2", blocks: "Setup Continue", network: "required", forbiddenDuring: ["Launch Screen", "pre-action"], task: "TAP-0008" }
  },
  cameraDiscovery: {
    label: "Camera capability discovery", machineId: "cameraReadiness", family: "camera", pages: ["resourceInitialization", "viewfinder"], alignment: "gap",
    observed: { trigger: "CameraViewModel default construction", owner: "MainActor synchronous resolver", earliest: "Δt0–t1 returning; post-Continue first install", blocks: "View construction", network: "never", evidence: "CameraCapture/UI/CameraView.swift:115; UI/CameraViewModel.swift:235" },
    target: { trigger: "Camera route shell acknowledged", owner: "Camera owner", earliest: "after t2", blocks: "Camera readiness", network: "never", forbiddenDuring: ["Δt0–t1", "Δt1–t2"], task: "TAP-0009" }
  },
  cameraSession: {
    label: "Camera session construction + graph start", machineId: "cameraReadiness", family: "camera", pages: ["resourceInitialization", "viewfinder"], alignment: "partial",
    observed: { trigger: "ViewModel construction, then mounted task", owner: "MainActor objects + session serial queue", earliest: "Construction Δt0–t1; graph after mount", blocks: "Preview", network: "never", evidence: "CameraCapture/Runtime/CaptureSessionController.swift:42,191" },
    target: { trigger: "Camera shell acknowledged", owner: "Camera owner + session queue", earliest: "after t2", blocks: "Preview", network: "never", forbiddenDuring: ["Δt0–t1"], task: "TAP-0009" }
  },
  firstPreview: {
    label: "First real preview", machineId: "cameraReadiness", family: "camera", pages: ["resourceInitialization", "viewfinder"], alignment: "gap",
    observed: { trigger: "PreviewLayer isPreviewing KVO", owner: "CameraPreviewView callback", earliest: "after session start", blocks: "Path-transition overlay only; not initial gate", network: "never", evidence: "CameraCapture/UI/CameraPreviewView.swift:116; UI/CameraView.swift:1934" },
    target: { trigger: "First real preview callback", owner: "Camera readiness event source", earliest: "after t2", blocks: "t3; must precede t4", network: "never", forbiddenDuring: [], task: "TAP-0009" }
  },
  cameraInteraction: {
    label: "Shutter, primary controls + haptics", machineId: "cameraReadiness", family: "camera", pages: ["resourceInitialization", "viewfinder"], alignment: "partial",
    observed: { trigger: "onAppear + session/depth state", owner: "MainActor + UIKit haptics", earliest: "Unordered against real preview", blocks: "Current gate omits isPreviewing", network: "never", evidence: "CameraCapture/UI/CameraInitialReadinessGate.swift:35; UI/CameraView.swift:401" },
    target: { trigger: "Real preview is ready", owner: "Bounded camera readiness", earliest: "after t3", blocks: "t4", network: "never", forbiddenDuring: [], task: "TAP-0009" }
  },
  libraryCatalog: {
    label: "First usable Library catalog snapshot", machineId: "libraryCatalog", family: "library", pages: ["firstInstallSetup", "resourceInitialization", "library"], alignment: "gap",
    observed: { trigger: "Root task / permission / observer / cover refresh", owner: "MainActor + actors + detached merge", earliest: "Root mounted task", blocks: "No I marker; root refresh waits behind poster backfill", network: "PhotoKit conditional by caller", evidence: "DepthAnalysis/DepthAlbumItemProvider.swift:83; App/StartupGateView.swift:43" },
    target: { trigger: "Stale initialization marker or Library entry", owner: "Generation-aware catalog service", earliest: "after t2", blocks: "RI only when I is stale", network: "never for identity catalog", forbiddenDuring: ["Δt0–t1"], task: "TAP-0009" }
  },
  thumbnailDecode: {
    label: "Visible-cell thumbnail decode", machineId: "thumbnailPipeline", family: "library", pages: ["library"], alignment: "aligned",
    observed: { trigger: "Visible cell task", owner: "Cell task + actors + detached utility", earliest: "Explicit Library entry", blocks: "Cell only", network: "disabled", evidence: "DepthAnalysis/TAPLibraryItemCell.swift:41,185" },
    target: { trigger: "Visible cell demand", owner: "On-demand visible cells", earliest: "Library entry", blocks: "Cell only", network: "never", forbiddenDuring: ["startup critical path"], task: "TAP-0087" }
  },
  videoPosterBackfill: {
    label: "Video poster backfill", machineId: "libraryCatalog", family: "library", pages: ["firstInstallSetup", "viewfinder", "library"], alignment: "gap",
    observed: { trigger: "Root mounted task", owner: "Backfill actor + detached utility", earliest: "Before root catalog refresh", blocks: "Indirectly delays root catalog; candidate-count-scaled", network: "never", evidence: "App/StartupGateView.swift:43; MediaLibrary/LibraryVideoPosterService.swift:70" },
    target: { trigger: "Deferred-work release", owner: "Bounded maintenance owner", earliest: "after t5", blocks: "nothing", network: "never", forbiddenDuring: ["Δt0–t5"], task: "TAP-0083 follow-up" }
  },
  recentLibraryCover: {
    label: "Recent Library cover", machineId: "libraryCatalog", family: "library", pages: ["viewfinder"], alignment: "partial",
    observed: { trigger: "Configure completion + 900 ms / foreground / revision", owner: "MainActor + fetch/decode actors", earliest: "Timer-based after camera configuration", blocks: "nothing", network: "PhotoKit conditional", evidence: "CameraCapture/UI/CameraViewModel.swift:425; UI/CameraViewModel+Capture.swift:140" },
    target: { trigger: "Deferred-work release", owner: "Cancellable Library request", earliest: "after t5", blocks: "nothing", network: "PhotoKit conditional", forbiddenDuring: ["Δt0–t5"], task: "TAP-0083 follow-up" }
  },
  appAttestMaintenance: {
    label: "Post-setup App Attest health/recovery", machineId: "appAttestCredential", family: "attestation", pages: ["viewfinder"], alignment: "partial",
    observed: { trigger: "Camera start returned + 1.5 s + idle guard", owner: "MainActor + AppAttestKit + backend", earliest: "Fixed delay", blocks: "Pending signing only", network: "conditional; update/build token may reset", evidence: "CameraCapture/UI/CaptureLifecycleCoordinator.swift:61; App/AppAttestRuntimeController.swift:68" },
    target: { trigger: "Deferred-work release", owner: "Credential owner", earliest: "after t5", blocks: "Pending signing only", network: "conditional", forbiddenDuring: ["Δt0–t5"], task: "TAP-0083 follow-up" }
  },
  pendingRecovery: {
    label: "Pending Capture Recovery Worker", machineId: "pendingCaptureRecovery", family: "queue", pages: ["viewfinder", "library"], alignment: "partial",
    observed: { trigger: "Fixed delay / foreground / Library return / credential completion", owner: "TAPPendingCaptureProcessor actor", earliest: "Trigger-dependent", blocks: "nothing in startup", network: "conditional via credential", evidence: "TAPLibrary/TAPPendingCaptureProcessor.swift:18; CameraCapture/UI/CaptureLifecycleCoordinator.swift:177" },
    target: { trigger: "Deferred-work release + guarded signals", owner: "One guarded serial worker", earliest: "after t5", blocks: "nothing in startup", network: "conditional via credential", forbiddenDuring: ["Δt0–t5"], task: "TAP-0083 follow-up" }
  },
  viewerDisplay: {
    label: "Viewer bounded display rendition", machineId: "viewerLoading", family: "viewer", pages: ["photoViewer"], alignment: "aligned",
    observed: { trigger: "Photo Viewer task", owner: "Viewer slot + PhotoKit/store", earliest: "Explicit photo open", blocks: "Viewer visual", network: "PhotoKit conditional", evidence: "DepthAnalysis/DepthAnalysisView.swift:331; MediaLibrary/PhotoKitLibraryMediaFetcher.swift:148" },
    target: { trigger: "Photo Viewer open", owner: "Acknowledged shell + cancellable load", earliest: "Explicit photo open", blocks: "Viewer visual", network: "PhotoKit conditional", forbiddenDuring: [], task: "TAP-0087" }
  },
  viewerFullAnalysis: {
    label: "Viewer original resource + full analysis", machineId: "viewerAnalysis", family: "viewer", pages: ["photoViewer"], alignment: "gap",
    observed: { trigger: "RAW Viewer open", owner: "PhotoKit resource loader + async decoder + MainActor", earliest: "Concurrent with bounded Viewer display", blocks: "2D/3D inputs; original also serves existing Share", network: "PhotoKit/iCloud conditional", evidence: "DepthAnalysis/DepthAnalysisCarouselState.swift:589; CameraCapture/Output/PhotoLibraryWriter.swift:1139" },
    target: { trigger: "No TAP-0087 behavior change; future split resource/decode", owner: "Viewer resource owner + analysis owner", earliest: "Explicit Viewer demand", blocks: "2D/3D only", network: "resource conditional; decode never", forbiddenDuring: [], task: "TAP-0089" }
  },
  viewer2D: {
    label: "2D plane analysis", machineId: "viewerAnalysis", family: "deferred", pages: ["photoViewer"], alignment: "deferred",
    observed: { trigger: "2D tap; plane detector after seed/strictness action", owner: "Detached utility + MainActor", earliest: "Native explicit action", blocks: "2D visual only", network: "never", evidence: "DepthAnalysis/DepthAnalysisView.swift:1528; DepthAnalysisPlaneRegionRequestCoordinator.swift:90" },
    target: { trigger: "Deferred from this prototype", owner: "TAP-0089", earliest: "after TAP-0008/0009/0083", blocks: "deferred", network: "never", forbiddenDuring: [], task: "TAP-0089" }
  },
  viewer3D: {
    label: "3D projection + SceneKit install", machineId: "viewerAnalysis", family: "deferred", pages: ["photoViewer"], alignment: "deferred",
    observed: { trigger: "3D tap", owner: "Detached builder + MainActor SceneKit", earliest: "Native explicit action", blocks: "3D visual only", network: "never", evidence: "DepthAnalysis/DepthAnalysisView.swift:1600; AnalysisTools/DepthPointCloudPreview.swift:1484" },
    target: { trigger: "Deferred from this prototype", owner: "TAP-0089", earliest: "after TAP-0008/0009/0083", blocks: "deferred", network: "never", forbiddenDuring: [], task: "TAP-0089" }
  },
  viewfinderControls: {
    label: "Viewfinder controls (scope placeholder)", machineId: "viewfinderControls", family: "deferred", pages: ["viewfinder"], alignment: "deferred", scopePlaceholder: true, observedNativeExists: true,
    observed: { trigger: "Native control interactions", owner: "Existing Camera SwiftUI seams", earliest: "Interactive Viewfinder", blocks: "Action-specific", network: "never", evidence: "CameraCapture/UI/CameraView.swift:501,535" },
    target: { trigger: "Functional prototype intentionally deferred", owner: "TAP-0088", earliest: "after TAP-0008/0009/0083", blocks: "deferred", network: "never", forbiddenDuring: [], task: "TAP-0088" }
  }
});

// Reviewer navigation targets are explicit because a workload's owning page and
// meaningful inspection moment cannot be inferred from registry order or from
// whichever event happens to be focused. Each target is reached only by replaying
// canonical reducer events. "eligible", "running", and "skipped" remain those
// exact states; the inspector must not upgrade them to a synthetic Ready state.
export const workloadInspectionRegistry = Object.freeze({
  startupFacts: { scenarioId: "ordinaryProcessLaunch", eventType: "APP_FIRST_FRAME_COMMITTED", status: "succeeded", page: "firstAppFrame" },
  libraryRootObservation: { scenarioId: "ordinaryProcessLaunch", eventType: "INITIAL_ROUTE_COMMITTED", status: "succeeded", page: "viewfinder" },
  initialAttestation: { scenarioId: "freshInstall", eventType: "SETUP_ATTESTATION_COMPLETED", status: "succeeded", page: "firstInstallSetup" },
  cameraDiscovery: { scenarioId: "ordinaryProcessLaunch", eventType: "CAMERA_SESSION_CONFIGURED", status: "succeeded", page: "viewfinder" },
  cameraSession: { scenarioId: "ordinaryProcessLaunch", eventType: "CAMERA_SESSION_CONFIGURED", status: "succeeded", page: "viewfinder" },
  firstPreview: { scenarioId: "ordinaryProcessLaunch", eventType: "CAMERA_PREVIEW_PRESENTED", status: "succeeded", page: "viewfinder" },
  cameraInteraction: { scenarioId: "ordinaryProcessLaunch", eventType: "CAMERA_INTERACTION_READY", status: "succeeded", page: "viewfinder" },
  libraryCatalog: { scenarioId: "inPlaceUpdate", eventType: "LIBRARY_CATALOG_PUBLISHED", status: "succeeded", page: "resourceInitialization" },
  thumbnailDecode: { scenarioId: "ordinaryProcessLaunch", eventType: "THUMBNAIL_BATCH_PUBLISHED", status: "succeeded", page: "library" },
  videoPosterBackfill: { scenarioId: "ordinaryProcessLaunch", eventType: "DEFERRED_WORK_RELEASED", status: "eligible", page: "viewfinder" },
  recentLibraryCover: { scenarioId: "ordinaryProcessLaunch", eventType: "DEFERRED_WORK_RELEASED", status: "eligible", page: "viewfinder" },
  appAttestMaintenance: { scenarioId: "ordinaryProcessLaunch", eventType: "DEFERRED_WORK_RELEASED", status: "eligible", page: "viewfinder" },
  pendingRecovery: { scenarioId: "ordinaryProcessLaunch", eventType: "DEFERRED_WORK_RELEASED", status: "eligible", page: "viewfinder" },
  viewerDisplay: { scenarioId: "ordinaryProcessLaunch", eventType: "VIEWER_DISPLAY_READY", status: "succeeded", page: "photoViewer" },
  viewerFullAnalysis: { scenarioId: "ordinaryProcessLaunch", eventType: "PHOTO_OPENED", status: "running", page: "photoViewer" },
  viewer2D: { scenarioId: "ordinaryProcessLaunch", eventType: "PHOTO_OPENED", status: "skipped", page: "photoViewer" },
  viewer3D: { scenarioId: "ordinaryProcessLaunch", eventType: "PHOTO_OPENED", status: "skipped", page: "photoViewer" },
  viewfinderControls: { scenarioId: "inPlaceUpdate", eventType: "CAMERA_INTERACTION_READY", status: "skipped", page: "viewfinder" }
});

const initialWorkloadStates = () => Object.fromEntries(
  Object.keys(workloadRegistry).map((id) => [id, "dormant"])
);

const catalogWasPublished = (catalog) => ["published", "publishedEmpty", "publishedNonEmpty"].includes(catalog);

const initialMachines = (facts) => ({
  activation: "idle",
  routeDecision: "idle",
  firstInstallSetup: "notRequired",
  requiredPermissionCheck: "notRequired",
  resourceInitialization: "notRequired",
  cameraReadiness: "idle",
  libraryCatalog: catalogWasPublished(facts.library.catalog) ? "published" : "dormant",
  thumbnailPipeline: ["partial", "ready"].includes(facts.library.thumbnails) ? "ready" : "idle",
  appAttestCredential: facts.attestation.bootstrap === "ready" ? "bootstrapReady" : "bootstrapIdle",
  pendingCaptureRecovery: "dormant",
  viewerLoading: "closed",
  viewerAnalysis: "deferredTAP0089",
  viewfinderControls: "deferredTAP0088"
});

const milestoneRecord = () => ({ t0: null, t1: null, t2: null, t3: null, t4: null, t5: null, tn: null });
const milestoneOrder = timelineRegistry.map(({ id }) => id);

const routeNodeByPage = Object.freeze({
  firstInstallSetup: "firstInstallSetup",
  requiredPermissionCheck: "requiredPermissionCheck",
  resourceInitialization: "resourceInitialization",
  viewfinder: "viewfinder"
});

export function photosUsable(status) {
  return status === "authorized" || status === "limited";
}

export function requiredPermissionsUsable(permissions) {
  return permissions.camera === "authorized" && photosUsable(permissions.photos);
}

export function setupReceiptValid(facts) {
  return facts.setupReceipt.state === "valid" && facts.setupReceipt.credentialBinding === "present";
}

export function initializationIdentityMatches(storedIdentity, targetIdentity) {
  if (!storedIdentity || !targetIdentity) return false;
  return ["bundleID", "shortVersion", "build", "schemaGeneration", "installationDeviceGeneration"]
    .every((key) => storedIdentity[key] === targetIdentity[key]);
}

export function chooseRoute(facts) {
  if (!setupReceiptValid(facts)) return { page: "firstInstallSetup", reason: facts.setupReceipt.state };
  if (!requiredPermissionsUsable(facts.permissions)) return { page: "requiredPermissionCheck", reason: "requiredPermissionUnavailable" };
  if (!initializationIdentityMatches(facts.initialization.storedIdentity, facts.initialization.targetIdentity)) {
    return { page: "resourceInitialization", reason: "initializationMarkerMismatch" };
  }
  if (facts.activation.kind === "settingsReturn") return { page: "viewfinder", reason: "settingsReturn" };
  if (facts.activation.kind === "foregroundResume") return { page: "viewfinder", reason: "foregroundReturn" };
  return { page: "viewfinder", reason: "currentFacts" };
}

export function createState(scenarioId = "freshInstall") {
  const fixture = scenarioFixtures[scenarioId];
  if (!fixture) throw new Error(`Unknown scenario: ${scenarioId}`);
  const facts = clone(fixture);
  const state = {
    revision: REVISION,
    seq: 0,
    scenarioId,
    facts,
    route: { page: null, reason: null },
    phone: { page: "dormant", stage: "idle", selectedAssetId: null },
    milestones: milestoneRecord(),
    machines: initialMachines(facts),
    workloads: initialWorkloadStates(),
    currentInterval: null,
    highlight: { seq: 0, machines: [], edges: [], workloads: [], milestones: [], markers: [], page: "dormant" },
    journey: {
      catalogPublished: catalogWasPublished(facts.library.catalog),
      thumbnailsPublished: ["partial", "ready"].includes(facts.library.thumbnails),
      viewerReturned: false
    },
    attestationAttempt: { explicitSequence: 0, automaticRetryWaits: 0 },
    log: []
  };
  assertStateInvariants(state);
  return state;
}

function begin(previous, event) {
  const state = clone(previous);
  state.seq += 1;
  state.highlight = { seq: state.seq, machines: [], edges: [], workloads: [], milestones: [], markers: [], page: state.phone.page };
  return { state, event, pageBefore: previous.phone.page, effects: state.highlight };
}

function move(tx, machineId, to, edgeId = `${machineId}.${to}`) {
  const registry = machineRegistry[machineId];
  if (!registry) throw new Error(`Unknown machine: ${machineId}`);
  if (!registry.nodes.includes(to)) throw new Error(`${machineId} has no node ${to}`);
  const from = tx.state.machines[machineId];
  tx.state.machines[machineId] = to;
  if (!tx.effects.machines.includes(machineId)) tx.effects.machines.push(machineId);
  tx.effects.edges.push({ machineId, edgeId, from, to });
}

function work(tx, id, status) {
  if (!Object.hasOwn(workloadRegistry, id)) throw new Error(`Unknown workload: ${id}`);
  if (!workloadStates.includes(status)) throw new Error(`Unknown workload state: ${status}`);
  tx.state.workloads[id] = status;
  if (!tx.effects.workloads.includes(id)) tx.effects.workloads.push(id);
}

function activateLibraryRootObservationIfAllowed(tx) {
  if (tx.state.facts.activation.kind !== "processLaunch") return;
  if (!photosUsable(tx.state.facts.permissions.photos)) return;
  if (tx.state.workloads.libraryRootObservation !== "dormant") return;
  work(tx, "libraryRootObservation", "succeeded");
}

function mark(tx, id, from, to) {
  tx.effects.markers.push({ id, from: clone(from), to: clone(to) });
}

function reach(tx, milestone) {
  const index = milestoneOrder.indexOf(milestone);
  if (index < 0) throw new Error(`Unknown milestone: ${milestone}`);
  if (tx.state.milestones[milestone] != null) throw new Error(`${milestone} was already reached`);
  for (const prior of milestoneOrder.slice(0, index)) {
    if (tx.state.milestones[prior] == null) throw new Error(`${milestone} requires ${prior}`);
  }
  tx.state.milestones[milestone] = tx.state.seq;
  tx.effects.milestones.push(milestone);
  tx.state.currentInterval = timelineRegistry[index].interval;
}

function setPage(tx, page, stage) {
  tx.state.phone.page = page;
  tx.state.phone.stage = stage;
  tx.effects.page = page;
}

export function setupRequiredReady(state) {
  return state.facts.attestation.bootstrap === "ready" && requiredPermissionsUsable(state.facts.permissions);
}

function updateFirstInstallSetupMachine(tx) {
  let node;
  if (setupRequiredReady(tx.state)) {
    node = "requiredReady";
  } else if (tx.state.facts.attestation.bootstrap === "running") {
    node = "attestationRunning";
  } else if (tx.state.facts.attestation.bootstrap === "automaticRetryWaiting") {
    node = "automaticRetryWaiting";
  } else if (tx.state.facts.attestation.bootstrap === "timedOutAwaitingExplicitRetry") {
    node = "timedOutAwaitingExplicitRetry";
  } else if (tx.state.facts.setupReceipt.state === "invalidCredentialBinding") {
    node = "credentialRecovery";
  } else {
    node = "awaitingExplicitActions";
  }
  move(tx, "firstInstallSetup", node, `firstInstallSetup.${node}`);
  if (tx.state.phone.page === "firstInstallSetup") tx.state.phone.stage = node;
}

function permissionNode(facts) {
  const permission = firstUnavailableRequiredPermission(facts);
  if (!permission) return "resolved";
  const status = facts.permissions[permission];
  if (status === "notDetermined" || status === "requesting") return "awaitingAllow";
  if (status === "restricted") return "restricted";
  return "awaitingSettings";
}

function enterRoute(tx, decision = chooseRoute(tx.state.facts), { initial = false } = {}) {
  const routeNode = routeNodeByPage[decision.page];
  if (!routeNode) throw new Error(`No route node for ${decision.page}`);
  tx.state.route = decision;
  move(tx, "routeDecision", routeNode, `route.${decision.page}`);
  if (initial) {
    reach(tx, "t2");
    move(tx, "activation", "routeCommitted", "activation.routeCommitted");
  }
  activateLibraryRootObservationIfAllowed(tx);

  switch (decision.page) {
    case "firstInstallSetup":
      setPage(tx, decision.page, "awaitingExplicitActions");
      updateFirstInstallSetupMachine(tx);
      move(tx, "appAttestCredential", tx.state.facts.attestation.bootstrap === "ready" ? "bootstrapReady" : "bootstrapIdle", "appAttestCredential.setupEntry");
      work(tx, "initialAttestation", tx.state.facts.attestation.bootstrap === "ready" ? "succeeded" : "waitingPrerequisite");
      break;
    case "requiredPermissionCheck": {
      setPage(tx, decision.page, "blocked");
      move(tx, "requiredPermissionCheck", "inspecting", "requiredPermissionCheck.inspecting");
      move(tx, "requiredPermissionCheck", permissionNode(tx.state.facts), "requiredPermissionCheck.awaitingRecovery");
      break;
    }
    case "resourceInitialization":
      setPage(tx, decision.page, "preparing");
      move(tx, "resourceInitialization", "preparing", "resourceInitialization.preparing");
      move(tx, "cameraReadiness", "shell", "cameraReadiness.shell");
      move(tx, "libraryCatalog", "scheduled", "libraryCatalog.scheduledForInitialization");
      work(tx, "cameraDiscovery", "eligible");
      work(tx, "libraryCatalog", "scheduled");
      break;
    case "viewfinder":
      setPage(tx, decision.page, "shell");
      move(tx, "cameraReadiness", "shell", "cameraReadiness.shell");
      work(tx, "cameraDiscovery", "eligible");
      work(tx, "viewfinderControls", "skipped");
      break;
  }
}

function maybeCompleteInitialization(tx) {
  if (tx.state.phone.page !== "resourceInitialization") return;
  const cameraReady = tx.state.machines.cameraReadiness === "interactive";
  const catalogReady = tx.state.machines.libraryCatalog === "published";
  if (cameraReady && !catalogReady) {
    move(tx, "resourceInitialization", "cameraReadyCatalogPending", "resourceInitialization.cameraReadyCatalogPending");
    tx.state.phone.stage = "cameraReadyCatalogPending";
    return;
  }
  if (!cameraReady && catalogReady) {
    move(tx, "resourceInitialization", "catalogReadyCameraPending", "resourceInitialization.catalogReadyCameraPending");
    tx.state.phone.stage = "catalogReadyCameraPending";
    return;
  }
  if (!cameraReady || !catalogReady) return;

  move(tx, "resourceInitialization", "bothReady", "resourceInitialization.bothReady");
  const previousIdentity = tx.state.facts.initialization.storedIdentity;
  tx.state.facts.initialization.storedIdentity = clone(tx.state.facts.initialization.targetIdentity);
  mark(tx, "initializationCompletion", previousIdentity, tx.state.facts.initialization.storedIdentity);
  move(tx, "resourceInitialization", "markerCommitted", "resourceInitialization.markerCommitted");
  tx.state.route = { page: "viewfinder", reason: "initializationComplete" };
  move(tx, "routeDecision", "viewfinder", "route.initializationToViewfinder");
  setPage(tx, "viewfinder", "interactive");
  work(tx, "viewfinderControls", "skipped");
  reach(tx, "t4");
}

function requirePage(state, event, ...pages) {
  if (!pages.includes(state.phone.page)) throw new Error(`${event.type} requires page ${pages.join(" or ")}`);
}

function requireMachine(state, event, machineId, ...nodes) {
  if (!nodes.includes(state.machines[machineId])) {
    throw new Error(`${event.type} requires ${machineId} ${nodes.join(" or ")}`);
  }
}

function requireWorkload(state, event, workloadId, ...statuses) {
  if (!statuses.includes(state.workloads[workloadId])) {
    throw new Error(`${event.type} requires ${workloadId} ${statuses.join(" or ")}`);
  }
}

function requireMilestone(state, event, milestone, reached) {
  const isReached = state.milestones[milestone] != null;
  if (isReached !== reached) throw new Error(`${event.type} requires ${milestone} ${reached ? "reached" : "pending"}`);
}

function validateEvent(previous, event) {
  if (!event || typeof event.type !== "string") throw new Error("Prototype event requires a type");
  if (event.type === "SCENARIO_SELECTED") {
    if (!scenarioFixtures[event.scenarioId]) throw new Error(`Unknown scenario: ${event.scenarioId}`);
    return;
  }

  switch (event.type) {
    case "ACTIVATION_REQUESTED":
      requireMachine(previous, event, "activation", "idle");
      requireMilestone(previous, event, "t0", false);
      break;
    case "APP_FIRST_FRAME_COMMITTED":
      requireMachine(previous, event, "activation", "launchRequested", "sceneResumed");
      requireMilestone(previous, event, "t0", true);
      requireMilestone(previous, event, "t1", false);
      break;
    case "INITIAL_ROUTE_COMMITTED":
      requirePage(
        previous,
        event,
        previous.facts.activation.kind === "processLaunch"
          ? "firstAppFrame"
          : (previous.facts.activation.returnPage || "viewfinder")
      );
      requireMachine(previous, event, "activation", "appFirstFrame");
      requireMachine(previous, event, "routeDecision", "readingFacts");
      requireMilestone(previous, event, "t1", true);
      requireMilestone(previous, event, "t2", false);
      break;
    case "SETUP_ATTESTATION_TAPPED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "firstInstallSetup", "awaitingExplicitActions", "credentialRecovery", "requiredReady");
      requireMachine(previous, event, "appAttestCredential", "bootstrapIdle");
      if (previous.facts.attestation.bootstrap !== "idle") throw new Error("Initial App Attest action requires idle bootstrap");
      break;
    case "SETUP_ATTESTATION_RETRY_TAPPED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "firstInstallSetup", "timedOutAwaitingExplicitRetry");
      requireMachine(previous, event, "appAttestCredential", "timedOutAwaitingExplicitRetry");
      if (previous.facts.attestation.bootstrap !== "timedOutAwaitingExplicitRetry") throw new Error("Retry requires an explicitly timed-out bootstrap");
      break;
    case "SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "appAttestCredential", "bootstrapRunning");
      requireWorkload(previous, event, "initialAttestation", "running");
      break;
    case "SETUP_ATTESTATION_TIMED_OUT":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "appAttestCredential", "automaticRetryWaiting");
      break;
    case "SETUP_ATTESTATION_COMPLETED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "appAttestCredential", "bootstrapRunning");
      requireWorkload(previous, event, "initialAttestation", "running");
      if (previous.facts.attestation.network !== "available") throw new Error("App Attest completion requires network availability");
      break;
    case "NETWORK_BECAME_AVAILABLE":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "appAttestCredential", "automaticRetryWaiting", "timedOutAwaitingExplicitRetry");
      if (previous.facts.attestation.network !== "offline") throw new Error("Network is already available");
      break;
    case "SETUP_PERMISSION_TAPPED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "firstInstallSetup", "awaitingExplicitActions", "credentialRecovery", "requiredReady");
      if (!["camera", "photos", "location", "microphone"].includes(event.permission)) throw new Error("Unknown Setup permission");
      if (previous.facts.permissions[event.permission] !== "notDetermined") throw new Error("Setup permission action requires notDetermined");
      break;
    case "SETUP_PERMISSION_RECOVERY_TAPPED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "firstInstallSetup", "awaitingExplicitActions", "credentialRecovery", "requiredReady");
      if (!["camera", "photos", "location", "microphone"].includes(event.permission)) throw new Error("Unknown Setup permission");
      if (event.currentStatus !== "denied" || previous.facts.permissions[event.permission] !== "denied") {
        throw new Error("Setup permission recovery requires a denied row");
      }
      break;
    case "SYSTEM_PERMISSION_RETURNED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "firstInstallSetup", "waitingSystem");
      if (!["requesting", "denied"].includes(previous.facts.permissions[event.permission])) {
        throw new Error("System permission return requires a requesting prompt or denied Settings row");
      }
      if (!["authorized", "limited", "denied", "restricted"].includes(event.status)) throw new Error("Unsupported permission result");
      if (event.permission === "camera" && event.status === "limited") throw new Error("Camera has no limited status");
      break;
    case "SETUP_OPTIONAL_SKIPPED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "firstInstallSetup", "awaitingExplicitActions", "credentialRecovery", "requiredReady");
      if (!["location", "microphone"].includes(event.permission)) throw new Error("Only Location or Microphone can be skipped");
      if (previous.facts.permissions[event.permission] !== "notDetermined") throw new Error("Optional skip requires notDetermined");
      break;
    case "SETUP_CONTINUE_TAPPED":
      requirePage(previous, event, "firstInstallSetup");
      requireMachine(previous, event, "firstInstallSetup", "requiredReady");
      if (!setupRequiredReady(previous)) throw new Error("Setup Continue requires App Attest, Camera, and Photos");
      break;
    case "PERMISSION_RECOVERY_TAPPED": {
      requirePage(previous, event, "requiredPermissionCheck");
      requireMachine(previous, event, "requiredPermissionCheck", "awaitingAllow", "awaitingSettings", "restricted");
      const expected = firstUnavailableRequiredPermission(previous.facts);
      if (event.permission !== expected || event.currentStatus !== previous.facts.permissions[expected]) throw new Error("Permission recovery must target the current required permission");
      if (event.currentStatus === "restricted") throw new Error("A restricted permission has no promised Settings recovery");
      break;
    }
    case "PERMISSIONS_RECHECKED": {
      requirePage(previous, event, "requiredPermissionCheck");
      requireMachine(previous, event, "requiredPermissionCheck", "awaitingAllow", "awaitingSettings", "rechecking");
      const keys = Object.keys(event.permissions || {});
      if (keys.some((key) => !["camera", "photos"].includes(key))) throw new Error("Required Permission Check refreshes only Camera and Photos");
      break;
    }
    case "CAMERA_DISCOVERY_STARTED":
      requirePage(previous, event, "resourceInitialization", "viewfinder");
      requireMachine(previous, event, "cameraReadiness", "shell");
      requireWorkload(previous, event, "cameraDiscovery", "eligible");
      break;
    case "CAMERA_SESSION_CONFIGURED":
      requirePage(previous, event, "resourceInitialization", "viewfinder");
      requireMachine(previous, event, "cameraReadiness", "configuring");
      requireWorkload(previous, event, "cameraDiscovery", "running");
      break;
    case "CAMERA_PREVIEW_PRESENTED":
      requirePage(previous, event, "resourceInitialization", "viewfinder");
      requireMachine(previous, event, "cameraReadiness", "configuring");
      requireWorkload(previous, event, "firstPreview", "running");
      requireMilestone(previous, event, "t3", false);
      break;
    case "CAMERA_INTERACTION_READY":
      requirePage(previous, event, "resourceInitialization", "viewfinder");
      requireMachine(previous, event, "cameraReadiness", "previewReady");
      requireWorkload(previous, event, "cameraInteraction", "running");
      break;
    case "LIBRARY_CATALOG_STARTED":
      requirePage(previous, event, "resourceInitialization", "library");
      requireMachine(previous, event, "libraryCatalog", "scheduled", "stale");
      requireWorkload(previous, event, "libraryCatalog", "scheduled", "stale");
      break;
    case "LIBRARY_CATALOG_PUBLISHED":
      requirePage(previous, event, "resourceInitialization", "library");
      requireMachine(previous, event, "libraryCatalog", "refreshing");
      requireWorkload(previous, event, "libraryCatalog", "running");
      break;
    case "DEFERRED_WORK_RELEASED":
      requirePage(previous, event, "viewfinder");
      requireMachine(previous, event, "cameraReadiness", "interactive");
      requireMilestone(previous, event, "t4", true);
      requireMilestone(previous, event, "t5", false);
      break;
    case "LIBRARY_OPENED":
      requirePage(previous, event, "viewfinder");
      requireMachine(previous, event, "cameraReadiness", "interactive");
      requireMilestone(previous, event, "t5", true);
      break;
    case "LIBRARY_BACK_TAPPED":
      requirePage(previous, event, "library");
      break;
    case "THUMBNAIL_BATCH_STARTED":
      requirePage(previous, event, "library");
      requireMachine(previous, event, "thumbnailPipeline", "idle", "cancelled");
      requireMachine(previous, event, "libraryCatalog", "published");
      requireWorkload(previous, event, "thumbnailDecode", "eligible", "cancelled");
      break;
    case "THUMBNAIL_BATCH_PUBLISHED":
      requirePage(previous, event, "library");
      requireMachine(previous, event, "thumbnailPipeline", "resolving");
      requireWorkload(previous, event, "thumbnailDecode", "running");
      break;
    case "PHOTO_OPENED":
      requirePage(previous, event, "library");
      requireMachine(previous, event, "viewerLoading", "closed");
      if (!previous.journey.catalogPublished) throw new Error("Photo open requires a published catalog");
      break;
    case "VIEWER_DISPLAY_READY":
      requirePage(previous, event, "photoViewer");
      requireMachine(previous, event, "viewerLoading", "displayLoading");
      requireWorkload(previous, event, "viewerDisplay", "running");
      break;
    case "VIEWER_BACK_TAPPED":
      requirePage(previous, event, "photoViewer");
      requireMachine(previous, event, "viewerLoading", "displayLoading", "displayReady");
      break;
    case "SCENARIO_TERMINATED":
      requirePage(previous, event, "library");
      requireMachine(previous, event, "activation", "routeCommitted");
      requireMachine(previous, event, "viewerLoading", "closed");
      requireMilestone(previous, event, "t5", true);
      requireMilestone(previous, event, "tn", false);
      if (!previous.journey.viewerReturned && !(previous.facts.library.itemCount === 0 && previous.journey.catalogPublished)) {
        throw new Error("Scenario terminal requires Viewer return or a stable empty Library");
      }
      break;
    case "MEASUREMENT_PROFILE_CHANGED":
      if (previous.machines.activation === "terminal") throw new Error("Measurement profile cannot mutate a terminal scenario");
      break;
    default:
      throw new Error(`Unsupported event: ${event.type}`);
  }
}

export function canReduce(previous, event) {
  try {
    validateEvent(previous, event);
    return true;
  } catch {
    return false;
  }
}

function assertStateInvariants(state) {
  const actualMachines = Object.keys(state.machines).sort();
  const registeredMachines = Object.keys(machineRegistry).sort();
  if (JSON.stringify(actualMachines) !== JSON.stringify(registeredMachines)) throw new Error("Machine registry/runtime keys diverged");
  for (const [machineId, node] of Object.entries(state.machines)) {
    if (!machineRegistry[machineId].nodes.includes(node)) throw new Error(`${machineId} current node ${node} is not registered`);
  }

  const actualWorkloads = Object.keys(state.workloads).sort();
  const registeredWorkloads = Object.keys(workloadRegistry).sort();
  if (JSON.stringify(actualWorkloads) !== JSON.stringify(registeredWorkloads)) throw new Error("Workload registry/runtime keys diverged");
  for (const [workloadId, status] of Object.entries(state.workloads)) {
    if (!workloadStates.includes(status)) throw new Error(`${workloadId} has invalid workload state ${status}`);
  }

  let previousSeq = -1;
  let foundPending = false;
  for (const milestone of milestoneOrder) {
    const seq = state.milestones[milestone];
    if (seq == null) {
      foundPending = true;
      continue;
    }
    if (foundPending) throw new Error(`${milestone} reached before an earlier milestone`);
    if (seq <= previousSeq) throw new Error(`${milestone} did not advance the timeline`);
    previousSeq = seq;
  }

  const lastReached = [...milestoneOrder].reverse().find((id) => state.milestones[id] != null);
  const expectedInterval = lastReached ? timelineRegistry.find(({ id }) => id === lastReached).interval : null;
  if (state.currentInterval !== expectedInterval) throw new Error("Current interval does not match the latest milestone");
}

function record(tx) {
  const entry = {
    seq: tx.state.seq,
    event: clone(tx.event),
    pageBefore: tx.pageBefore,
    pageAfter: tx.state.phone.page,
    effects: clone(tx.effects)
  };
  tx.state.log.push(entry);
  if (tx.state.log.length > 36) tx.state.log.shift();
  assertStateInvariants(tx.state);
  return tx.state;
}

export function reduce(previous, event) {
  validateEvent(previous, event);
  if (event.type === "SCENARIO_SELECTED") {
    const selected = createState(event.scenarioId);
    const selectionTx = begin(selected, event);
    selectionTx.pageBefore = previous.phone.page;
    return record(selectionTx);
  }
  const tx = begin(previous, event);
  const { state } = tx;

  switch (event.type) {
    case "ACTIVATION_REQUESTED":
      reach(tx, "t0");
      work(tx, "startupFacts", "running");
      if (state.facts.activation.kind === "processLaunch") {
        setPage(tx, "systemLaunchScreen", "staticReference");
        move(tx, "activation", "launchRequested", "activation.launchRequested");
      } else {
        setPage(tx, state.facts.activation.returnPage || "viewfinder", "suspendedSnapshot");
        move(tx, "activation", "sceneResumed", "activation.sceneResumed");
      }
      break;
    case "APP_FIRST_FRAME_COMMITTED":
      reach(tx, "t1");
      work(tx, "startupFacts", "succeeded");
      move(tx, "activation", "appFirstFrame", "activation.appFirstFrame");
      move(tx, "routeDecision", "readingFacts", "routeDecision.readingFacts");
      if (state.facts.activation.kind === "processLaunch") {
        setPage(tx, "firstAppFrame", "resolvingFacts");
      } else {
        setPage(tx, state.facts.activation.returnPage || "viewfinder", "resumeFirstFrame");
      }
      break;
    case "INITIAL_ROUTE_COMMITTED":
      enterRoute(tx, chooseRoute(state.facts), { initial: true });
      break;
    case "SETUP_ATTESTATION_TAPPED":
    case "SETUP_ATTESTATION_RETRY_TAPPED":
      state.facts.attestation.bootstrap = "running";
      state.attestationAttempt.explicitSequence += 1;
      state.attestationAttempt.automaticRetryWaits = 0;
      move(tx, "appAttestCredential", "bootstrapRunning", "appAttestCredential.explicitAttemptStarted");
      move(tx, "firstInstallSetup", "attestationRunning", "firstInstallSetup.attestationRunning");
      work(tx, "initialAttestation", "running");
      break;
    case "SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING":
      state.facts.attestation.bootstrap = "automaticRetryWaiting";
      state.attestationAttempt.automaticRetryWaits += 1;
      move(tx, "appAttestCredential", "automaticRetryWaiting", "appAttestCredential.automaticRetryWaiting");
      work(tx, "initialAttestation", state.facts.attestation.network === "offline" ? "waitingNetwork" : "waitingPrerequisite");
      updateFirstInstallSetupMachine(tx);
      break;
    case "SETUP_ATTESTATION_TIMED_OUT":
      state.facts.attestation.bootstrap = "timedOutAwaitingExplicitRetry";
      move(tx, "appAttestCredential", "timedOutAwaitingExplicitRetry", "appAttestCredential.timedOutAwaitingExplicitRetry");
      work(tx, "initialAttestation", "failedRetryable");
      updateFirstInstallSetupMachine(tx);
      break;
    case "SETUP_ATTESTATION_COMPLETED":
      state.facts.attestation.bootstrap = "ready";
      state.facts.setupReceipt.credentialBinding = "present";
      move(tx, "appAttestCredential", "bootstrapReady", "appAttestCredential.bootstrapReady");
      work(tx, "initialAttestation", "succeeded");
      updateFirstInstallSetupMachine(tx);
      break;
    case "NETWORK_BECAME_AVAILABLE":
      state.facts.attestation.network = "available";
      break;
    case "SETUP_PERMISSION_TAPPED":
      state.facts.permissions[event.permission] = "requesting";
      move(tx, "firstInstallSetup", "waitingSystem", `firstInstallSetup.${event.permission}Tapped`);
      state.phone.stage = "waitingSystem";
      break;
    case "SETUP_PERMISSION_RECOVERY_TAPPED":
      move(tx, "firstInstallSetup", "waitingSystem", `firstInstallSetup.${event.permission}SettingsOpened`);
      state.phone.stage = "waitingSystem";
      break;
    case "SYSTEM_PERMISSION_RETURNED":
      state.facts.permissions[event.permission] = event.status;
      activateLibraryRootObservationIfAllowed(tx);
      updateFirstInstallSetupMachine(tx);
      break;
    case "SETUP_OPTIONAL_SKIPPED":
      state.facts.permissions[event.permission] = "skipped";
      updateFirstInstallSetupMachine(tx);
      break;
    case "SETUP_CONTINUE_TAPPED": {
      const previousReceipt = state.facts.setupReceipt;
      state.facts.setupReceipt = { state: "valid", credentialBinding: "present" };
      mark(tx, "setupReceipt", previousReceipt, state.facts.setupReceipt);
      move(tx, "firstInstallSetup", "completed", "firstInstallSetup.completed");
      enterRoute(tx);
      break;
    }
    case "PERMISSION_RECOVERY_TAPPED":
      if (event.currentStatus === "notDetermined") state.facts.permissions[event.permission] = "requesting";
      move(tx, "requiredPermissionCheck", event.currentStatus === "notDetermined" ? "awaitingAllow" : "awaitingSettings", "requiredPermissionCheck.recoveryAction");
      break;
    case "PERMISSIONS_RECHECKED":
      state.facts.permissions = { ...state.facts.permissions, ...event.permissions };
      move(tx, "requiredPermissionCheck", "rechecking", "requiredPermissionCheck.rechecking");
      if (requiredPermissionsUsable(state.facts.permissions)) {
        move(tx, "requiredPermissionCheck", "resolved", "requiredPermissionCheck.resolved");
        enterRoute(tx);
      } else {
        move(tx, "requiredPermissionCheck", permissionNode(state.facts), "requiredPermissionCheck.stillBlocked");
      }
      break;
    case "CAMERA_DISCOVERY_STARTED":
      move(tx, "cameraReadiness", "configuring", "cameraReadiness.configuring");
      work(tx, "cameraDiscovery", "running");
      work(tx, "cameraSession", "scheduled");
      break;
    case "CAMERA_SESSION_CONFIGURED":
      work(tx, "cameraDiscovery", "succeeded");
      work(tx, "cameraSession", "succeeded");
      work(tx, "firstPreview", "running");
      break;
    case "CAMERA_PREVIEW_PRESENTED":
      move(tx, "cameraReadiness", "previewReady", "cameraReadiness.previewReady");
      work(tx, "firstPreview", "succeeded");
      work(tx, "cameraInteraction", "running");
      reach(tx, "t3");
      if (state.phone.page === "viewfinder") state.phone.stage = "previewReady";
      maybeCompleteInitialization(tx);
      break;
    case "CAMERA_INTERACTION_READY":
      move(tx, "cameraReadiness", "interactive", "cameraReadiness.interactive");
      work(tx, "cameraInteraction", "succeeded");
      if (state.phone.page === "viewfinder") {
        state.phone.stage = "interactive";
        reach(tx, "t4");
      }
      maybeCompleteInitialization(tx);
      break;
    case "LIBRARY_CATALOG_STARTED":
      move(tx, "libraryCatalog", "refreshing", "libraryCatalog.refreshing");
      work(tx, "libraryCatalog", "running");
      break;
    case "LIBRARY_CATALOG_PUBLISHED": {
      state.journey.catalogPublished = true;
      state.facts.library.itemCount = event.count ?? state.facts.library.itemCount;
      state.facts.library.catalog = state.facts.library.itemCount === 0 ? "publishedEmpty" : "publishedNonEmpty";
      move(tx, "libraryCatalog", "published", "libraryCatalog.published");
      work(tx, "libraryCatalog", "succeeded");
      if (state.phone.page === "library") {
        state.phone.stage = "catalogReady";
        work(tx, "thumbnailDecode", "eligible");
      }
      maybeCompleteInitialization(tx);
      break;
    }
    case "DEFERRED_WORK_RELEASED":
      reach(tx, "t5");
      move(tx, "appAttestCredential", "eligible", "appAttestCredential.eligible");
      move(tx, "pendingCaptureRecovery", "eligible", "pendingCaptureRecovery.eligible");
      work(tx, "appAttestMaintenance", "eligible");
      work(tx, "pendingRecovery", "eligible");
      work(tx, "videoPosterBackfill", "eligible");
      work(tx, "recentLibraryCover", "eligible");
      break;
    case "LIBRARY_OPENED":
      setPage(tx, "library", state.journey.catalogPublished ? "catalogReady" : "loading");
      if (state.journey.catalogPublished) {
        move(tx, "libraryCatalog", "published", "libraryCatalog.reusedPublishedSnapshot");
        work(tx, "thumbnailDecode", state.journey.thumbnailsPublished ? "succeeded" : "eligible");
      } else {
        move(tx, "libraryCatalog", "scheduled", "libraryCatalog.scheduledForLibrary");
        work(tx, "libraryCatalog", "scheduled");
        move(tx, "libraryCatalog", "refreshing", "libraryCatalog.refreshingForLibrary");
        work(tx, "libraryCatalog", "running");
      }
      break;
    case "LIBRARY_BACK_TAPPED":
      if (["scheduled", "refreshing"].includes(state.machines.libraryCatalog)) {
        move(tx, "libraryCatalog", "stale", "libraryCatalog.cancelledByBack");
        work(tx, "libraryCatalog", "stale");
      }
      if (state.machines.thumbnailPipeline === "resolving") {
        move(tx, "thumbnailPipeline", "cancelled", "thumbnailPipeline.cancelledByBack");
        work(tx, "thumbnailDecode", "cancelled");
      }
      setPage(tx, "viewfinder", "interactive");
      break;
    case "THUMBNAIL_BATCH_STARTED":
      move(tx, "thumbnailPipeline", "resolving", "thumbnailPipeline.resolving");
      work(tx, "thumbnailDecode", "running");
      break;
    case "THUMBNAIL_BATCH_PUBLISHED":
      state.journey.thumbnailsPublished = true;
      state.facts.library.thumbnails = "ready";
      state.phone.stage = "thumbnailsReady";
      move(tx, "thumbnailPipeline", "ready", "thumbnailPipeline.ready");
      work(tx, "thumbnailDecode", "succeeded");
      break;
    case "PHOTO_OPENED":
      state.phone.selectedAssetId = event.assetId || "fixture-photo-01";
      setPage(tx, "photoViewer", "opening");
      move(tx, "viewerLoading", "shell", "viewerLoading.shell");
      move(tx, "viewerLoading", "displayLoading", "viewerLoading.displayLoading");
      work(tx, "viewerDisplay", "running");
      work(tx, "viewerFullAnalysis", "running");
      work(tx, "viewer2D", "skipped");
      work(tx, "viewer3D", "skipped");
      break;
    case "VIEWER_DISPLAY_READY":
      state.phone.stage = "photoReady";
      move(tx, "viewerLoading", "displayReady", "viewerLoading.displayReady");
      work(tx, "viewerDisplay", "succeeded");
      break;
    case "VIEWER_BACK_TAPPED":
      move(tx, "viewerLoading", "returning", "viewerLoading.returning");
      if (state.workloads.viewerDisplay === "running") work(tx, "viewerDisplay", "cancelled");
      if (state.workloads.viewerFullAnalysis === "running") work(tx, "viewerFullAnalysis", "cancelled");
      move(tx, "viewerLoading", "closed", "viewerLoading.closed");
      setPage(tx, "library", state.journey.thumbnailsPublished ? "thumbnailsReady" : "catalogReady");
      state.journey.viewerReturned = true;
      break;
    case "SCENARIO_TERMINATED":
      reach(tx, "tn");
      move(tx, "activation", "terminal", "activation.terminal");
      break;
    case "MEASUREMENT_PROFILE_CHANGED":
      state.facts.measurement = { ...state.facts.measurement, ...event.measurement };
      break;
    default:
      throw new Error(`Unsupported event: ${event.type}`);
  }

  return record(tx);
}

function firstUnavailableRequiredPermission(facts) {
  if (facts.permissions.camera !== "authorized") return "camera";
  if (!photosUsable(facts.permissions.photos)) return "photos";
  return null;
}

export function nextEvent(state) {
  if (state.milestones.t0 == null) return { type: "ACTIVATION_REQUESTED" };
  if (state.milestones.t1 == null) return { type: "APP_FIRST_FRAME_COMMITTED" };
  if (state.milestones.t2 == null) return { type: "INITIAL_ROUTE_COMMITTED" };

  if (state.phone.page === "firstInstallSetup") {
    if (state.machines.firstInstallSetup === "waitingSystem") {
      const permission = ["camera", "photos", "location", "microphone"]
        .find((key) => ["requesting", "denied"].includes(state.facts.permissions[key]));
      if (permission) return { type: "SYSTEM_PERMISSION_RETURNED", permission, status: "authorized" };
    }
    const bootstrap = state.facts.attestation.bootstrap;
    if (bootstrap === "idle") return { type: "SETUP_ATTESTATION_TAPPED" };
    if (bootstrap === "running") {
      return state.facts.attestation.network === "available"
        ? { type: "SETUP_ATTESTATION_COMPLETED" }
        : { type: "SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING" };
    }
    if (bootstrap === "automaticRetryWaiting") return { type: "SETUP_ATTESTATION_TIMED_OUT" };
    if (bootstrap === "timedOutAwaitingExplicitRetry" && state.facts.attestation.network === "offline") return { type: "NETWORK_BECAME_AVAILABLE" };
    if (bootstrap === "timedOutAwaitingExplicitRetry") return { type: "SETUP_ATTESTATION_RETRY_TAPPED" };
    for (const permission of ["camera", "photos"]) {
      const status = state.facts.permissions[permission];
      if (status === "notDetermined") return { type: "SETUP_PERMISSION_TAPPED", permission };
      if (status === "requesting") return { type: "SYSTEM_PERMISSION_RETURNED", permission, status: "authorized" };
    }
    for (const permission of ["location", "microphone"]) {
      if (state.facts.permissions[permission] === "notDetermined") return { type: "SETUP_OPTIONAL_SKIPPED", permission };
    }
    if (setupRequiredReady(state)) return { type: "SETUP_CONTINUE_TAPPED" };
  }

  if (state.phone.page === "requiredPermissionCheck") {
    const permission = firstUnavailableRequiredPermission(state.facts);
    if (!permission) return { type: "PERMISSIONS_RECHECKED", permissions: {} };
    const status = state.facts.permissions[permission];
    if (status === "restricted") return null;
    if (state.machines.requiredPermissionCheck === "awaitingAllow" && status === "requesting") {
      return { type: "PERMISSIONS_RECHECKED", permissions: { [permission]: "authorized" } };
    }
    if (state.machines.requiredPermissionCheck === "awaitingSettings" && status === "denied") {
      return { type: "PERMISSIONS_RECHECKED", permissions: { [permission]: "authorized" } };
    }
    return { type: "PERMISSION_RECOVERY_TAPPED", permission, currentStatus: status };
  }

  if (["resourceInitialization", "viewfinder"].includes(state.phone.page)) {
    const camera = state.machines.cameraReadiness;
    const catalogReady = state.machines.libraryCatalog === "published";
    const catalogFirst = state.facts.readinessOrder === "catalogFirst";
    if (state.phone.page === "resourceInitialization" && catalogFirst && !catalogReady) {
      if (state.machines.libraryCatalog !== "refreshing") return { type: "LIBRARY_CATALOG_STARTED" };
      return { type: "LIBRARY_CATALOG_PUBLISHED", count: state.facts.library.itemCount };
    }
    if (camera === "shell") return { type: "CAMERA_DISCOVERY_STARTED" };
    if (camera === "configuring" && state.workloads.cameraDiscovery === "running") return { type: "CAMERA_SESSION_CONFIGURED" };
    if (camera === "configuring" && state.workloads.firstPreview === "running") return { type: "CAMERA_PREVIEW_PRESENTED" };
    if (camera === "previewReady") return { type: "CAMERA_INTERACTION_READY" };
    if (state.phone.page === "resourceInitialization" && !catalogReady) {
      if (state.machines.libraryCatalog !== "refreshing") return { type: "LIBRARY_CATALOG_STARTED" };
      return { type: "LIBRARY_CATALOG_PUBLISHED", count: state.facts.library.itemCount };
    }
    if (state.phone.page === "viewfinder" && state.milestones.t5 == null) return { type: "DEFERRED_WORK_RELEASED" };
    if (state.phone.page === "viewfinder") return { type: "LIBRARY_OPENED" };
  }

  if (state.phone.page === "library") {
    if (!state.journey.catalogPublished) {
      return state.machines.libraryCatalog === "refreshing"
        ? { type: "LIBRARY_CATALOG_PUBLISHED", count: state.facts.library.itemCount }
        : { type: "LIBRARY_CATALOG_STARTED" };
    }
    if (!state.journey.thumbnailsPublished) {
      return state.machines.thumbnailPipeline === "resolving"
        ? { type: "THUMBNAIL_BATCH_PUBLISHED" }
        : { type: "THUMBNAIL_BATCH_STARTED" };
    }
    if (state.facts.library.itemCount === 0) {
      return state.milestones.tn == null ? { type: "SCENARIO_TERMINATED" } : null;
    }
    if (!state.journey.viewerReturned) return { type: "PHOTO_OPENED", assetId: "fixture-photo-01" };
    if (state.milestones.tn == null) return { type: "SCENARIO_TERMINATED" };
  }

  if (state.phone.page === "photoViewer") {
    if (state.machines.viewerLoading === "displayLoading") return { type: "VIEWER_DISPLAY_READY" };
    return { type: "VIEWER_BACK_TAPPED" };
  }

  return null;
}

export function workloadInspectionReached(state, workloadId) {
  const plan = workloadInspectionRegistry[workloadId];
  if (!plan || !Object.hasOwn(workloadRegistry, workloadId)) return false;
  const trace = state.log.at(-1) || null;
  return trace?.event.type === plan.eventType
    && trace.effects.workloads.includes(workloadId)
    && state.phone.page === plan.page
    && state.workloads[workloadId] === plan.status;
}

export function buildWorkloadInspectionJourney(workloadId, { stepLimit = 64 } = {}) {
  const plan = workloadInspectionRegistry[workloadId];
  if (!plan || !Object.hasOwn(workloadRegistry, workloadId)) {
    throw new Error(`Unknown workload inspection target: ${workloadId}`);
  }

  const base = createState(plan.scenarioId);
  let state = reduce(base, { type: "SCENARIO_SELECTED", scenarioId: plan.scenarioId });
  const history = [clone(base), clone(state)];

  for (let step = 0; step < stepLimit && !workloadInspectionReached(state, workloadId); step += 1) {
    const event = nextEvent(state);
    if (!event || !canReduce(state, event)) break;
    state = reduce(state, event);
    history.push(clone(state));
  }

  if (!workloadInspectionReached(state, workloadId)) {
    throw new Error(`Canonical journal did not reach workload inspection target: ${workloadId}`);
  }

  return { plan: clone(plan), state: clone(state), history };
}

export function publicSnapshot(state) {
  const last = state.log.at(-1) || null;
  return clone({
    revision: state.revision,
    scenarioId: state.scenarioId,
    route: state.route,
    phone: state.phone,
    milestones: state.milestones,
    currentInterval: state.currentInterval,
    machines: state.machines,
    workloads: state.workloads,
    facts: state.facts,
    highlight: state.highlight,
    lastTrace: last,
    log: state.log
  });
}
