import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import {
  canReduce,
  chooseRoute,
  createState,
  initializationIdentityMatches,
  machineRegistry,
  nextEvent,
  photosUsable,
  publicSnapshot,
  reduce,
  requiredPermissionsUsable,
  scenarioFixtures,
  setupRequiredReady,
  TARGET_INITIALIZATION_IDENTITY,
  timelineRegistry,
  workloadRegistry,
  workloadStates
} from "./startup-model.mjs";

const dispatch = (state, ...events) => events.reduce((current, event) => reduce(current, event), state);
const manifest = JSON.parse(fs.readFileSync(new URL("manifest.json", import.meta.url), "utf8"));
const modelSource = fs.readFileSync(new URL("startup-model.mjs", import.meta.url), "utf8");

const activate = (scenarioId) => dispatch(
  createState(scenarioId),
  { type: "ACTIVATION_REQUESTED" },
  { type: "APP_FIRST_FRAME_COMMITTED" },
  { type: "INITIAL_ROUTE_COMMITTED" }
);

const authorizeSetupPermission = (state, permission, status = "authorized") => dispatch(
  state,
  { type: "SETUP_PERMISSION_TAPPED", permission },
  { type: "SYSTEM_PERMISSION_RETURNED", permission, status }
);

const makeCameraInteractive = (state) => dispatch(
  state,
  { type: "CAMERA_DISCOVERY_STARTED" },
  { type: "CAMERA_SESSION_CONFIGURED" },
  { type: "CAMERA_PREVIEW_PRESENTED" },
  { type: "CAMERA_INTERACTION_READY" }
);

const openColdLibrary = (state) => dispatch(
  state,
  { type: "DEFERRED_WORK_RELEASED" },
  { type: "LIBRARY_OPENED" }
);

const expectedInitialRoutes = Object.freeze({
  freshInstall: "firstInstallSetup",
  freshInstallOffline: "firstInstallSetup",
  inPlaceUpdate: "resourceInitialization",
  updateWithRevokedPhotos: "requiredPermissionCheck",
  developmentReplacement: "resourceInitialization",
  developmentReplacementSameBuild: "viewfinder",
  deleteReinstall: "firstInstallSetup",
  offloadReinstall: "viewfinder",
  offloadReinstallChangedBuild: "resourceInitialization",
  sameDeviceRestore: "firstInstallSetup",
  sameDeviceRestoreValidBinding: "resourceInitialization",
  crossDeviceMigration: "firstInstallSetup",
  localMarkerLoss: "resourceInitialization",
  interruptedInitialization: "resourceInitialization",
  setupInterrupted: "firstInstallSetup",
  ordinaryProcessLaunch: "viewfinder",
  ordinaryProcessLaunchEmptyLibrary: "viewfinder",
  foregroundResumeRevoked: "requiredPermissionCheck",
  foregroundResumeRestrictedCamera: "requiredPermissionCheck",
  ordinaryForegroundResume: "viewfinder",
  settingsReturn: "viewfinder"
});

test("scenario labels are diagnostic while S/P/I facts choose every required route", () => {
  assert.deepEqual(Object.keys(scenarioFixtures), Object.keys(expectedInitialRoutes));
  assert.deepEqual(manifest.independentCandidates.startupLifecycle.scenarioFixtures, Object.keys(scenarioFixtures));
  for (const [scenarioId, expectedPage] of Object.entries(expectedInitialRoutes)) {
    const state = activate(scenarioId);
    assert.equal(state.phone.page, expectedPage, scenarioId);
    assert.equal(state.route.page, expectedPage, scenarioId);
    assert.equal(state.milestones.t0, 1, scenarioId);
    assert.equal(state.milestones.t1, 2, scenarioId);
    assert.equal(state.milestones.t2, 3, scenarioId);
  }

  assert.match(scenarioFixtures.inPlaceUpdate.label, /In-place App Update/);
  assert.match(scenarioFixtures.developmentReplacement.label, /Development Replacement Install/);
  assert.match(scenarioFixtures.crossDeviceMigration.label, /Cross-Device Migration Restore/);
  assert.match(scenarioFixtures.localMarkerLoss.label, /Local State Inconsistency/);
  assert.match(scenarioFixtures.ordinaryProcessLaunch.label, /Ordinary Later Process Launch/);
});

test("App First Frame and Initial Route Commit are distinct events and phone states", () => {
  let state = createState("freshInstall");
  state = reduce(state, { type: "ACTIVATION_REQUESTED" });
  state = reduce(state, { type: "APP_FIRST_FRAME_COMMITTED" });
  assert.equal(state.phone.page, "firstAppFrame");
  assert.equal(state.phone.stage, "resolvingFacts");
  assert.equal(state.machines.activation, "appFirstFrame");
  assert.equal(state.machines.routeDecision, "readingFacts");
  assert.equal(state.route.page, null);
  assert.equal(state.milestones.t1, 2);
  assert.equal(state.milestones.t2, null);
  assert.equal(state.currentInterval, "Δt1–t2");

  state = reduce(state, { type: "INITIAL_ROUTE_COMMITTED" });
  assert.equal(state.phone.page, "firstInstallSetup");
  assert.equal(state.milestones.t2, 3);
  assert.equal(state.machines.activation, "routeCommitted");
  assert.equal(state.machines.routeDecision, "firstInstallSetup");
});

test("Foreground Resume and Settings Return keep the safe return surface through t1", () => {
  for (const scenarioId of ["ordinaryForegroundResume", "settingsReturn", "foregroundResumeRevoked"]) {
    let state = createState(scenarioId);
    state = reduce(state, { type: "ACTIVATION_REQUESTED" });
    assert.equal(state.phone.page, "viewfinder", scenarioId);
    assert.equal(state.phone.stage, "suspendedSnapshot", scenarioId);

    state = reduce(state, { type: "APP_FIRST_FRAME_COMMITTED" });
    assert.equal(state.phone.page, "viewfinder", scenarioId);
    assert.equal(state.phone.stage, "resumeFirstFrame", scenarioId);
    assert.equal(state.milestones.t1, 2, scenarioId);

    state = reduce(state, { type: "INITIAL_ROUTE_COMMITTED" });
    assert.equal(state.phone.page, expectedInitialRoutes[scenarioId], scenarioId);
    assert.notEqual(state.phone.page, "firstAppFrame", scenarioId);
  }
});

test("first-install Continue requires explicit App Attest plus Camera and Photos, but not optional rows", () => {
  let state = activate("freshInstall");
  assert.equal(state.workloads.initialAttestation, "waitingPrerequisite");
  assert.equal(setupRequiredReady(state), false);
  assert.throws(() => reduce(state, { type: "SETUP_CONTINUE_TAPPED" }), /requires firstInstallSetup requiredReady/);

  state = dispatch(
    state,
    { type: "SETUP_ATTESTATION_TAPPED" },
    { type: "SETUP_ATTESTATION_COMPLETED" }
  );
  assert.equal(state.facts.attestation.bootstrap, "ready");
  assert.equal(state.workloads.initialAttestation, "succeeded");
  assert.equal(state.workloads.appAttestMaintenance, "dormant");

  state = authorizeSetupPermission(state, "camera");
  state = authorizeSetupPermission(state, "photos", "limited");
  assert.equal(state.facts.permissions.location, "notDetermined");
  assert.equal(state.facts.permissions.microphone, "notDetermined");
  assert.equal(setupRequiredReady(state), true);
  assert.equal(state.machines.firstInstallSetup, "requiredReady");

  state = reduce(state, { type: "SETUP_CONTINUE_TAPPED" });
  assert.equal(state.phone.page, "resourceInitialization");
  assert.deepEqual(state.facts.setupReceipt, { state: "valid", credentialBinding: "present" });
  assert.deepEqual(state.highlight.markers.map(({ id }) => id), ["setupReceipt"]);
  assert.deepEqual(state.highlight, state.log.at(-1).effects);
});

test("first-install denied permission opens Settings explicitly while restricted stays stable", () => {
  let denied = activate("freshInstall");
  denied = dispatch(
    denied,
    { type: "SETUP_PERMISSION_TAPPED", permission: "camera" },
    { type: "SYSTEM_PERMISSION_RETURNED", permission: "camera", status: "denied" }
  );
  assert.equal(denied.facts.permissions.camera, "denied");
  assert.throws(
    () => reduce(denied, { type: "SETUP_PERMISSION_TAPPED", permission: "camera" }),
    /requires notDetermined/
  );

  denied = reduce(denied, { type: "SETUP_PERMISSION_RECOVERY_TAPPED", permission: "camera", currentStatus: "denied" });
  assert.equal(denied.machines.firstInstallSetup, "waitingSystem");
  assert.equal(denied.facts.permissions.camera, "denied");
  denied = reduce(denied, { type: "SYSTEM_PERMISSION_RETURNED", permission: "camera", status: "authorized" });
  assert.equal(denied.facts.permissions.camera, "authorized");

  let restricted = activate("freshInstall");
  restricted = dispatch(
    restricted,
    { type: "SETUP_PERMISSION_TAPPED", permission: "camera" },
    { type: "SYSTEM_PERMISSION_RETURNED", permission: "camera", status: "restricted" }
  );
  assert.equal(restricted.facts.permissions.camera, "restricted");
  assert.throws(
    () => reduce(restricted, { type: "SETUP_PERMISSION_RECOVERY_TAPPED", permission: "camera", currentStatus: "restricted" }),
    /requires a denied row/
  );
});

test("Setup gives the active system permission boundary priority and restores only legal actions after return", () => {
  let state = activate("freshInstall");
  const cameraTap = { type: "SETUP_PERMISSION_TAPPED", permission: "camera" };
  assert.equal(canReduce(state, cameraTap), true);

  state = reduce(state, cameraTap);
  assert.equal(state.machines.firstInstallSetup, "waitingSystem");
  assert.equal(state.phone.stage, "waitingSystem");
  assert.equal(state.facts.permissions.camera, "requesting");
  assert.deepEqual(nextEvent(state), {
    type: "SYSTEM_PERMISSION_RETURNED",
    permission: "camera",
    status: "authorized"
  });

  for (const blocked of [
    { type: "SETUP_ATTESTATION_TAPPED" },
    { type: "SETUP_PERMISSION_TAPPED", permission: "photos" },
    { type: "SETUP_OPTIONAL_SKIPPED", permission: "location" },
    { type: "SETUP_CONTINUE_TAPPED" }
  ]) {
    assert.equal(canReduce(state, blocked), false, blocked.type);
    assert.throws(() => reduce(state, blocked), /requires firstInstallSetup|requiredReady/);
  }
  assert.equal(canReduce(state, {
    type: "SYSTEM_PERMISSION_RETURNED",
    permission: "photos",
    status: "authorized"
  }), false);

  state = reduce(state, {
    type: "SYSTEM_PERMISSION_RETURNED",
    permission: "camera",
    status: "authorized"
  });
  assert.equal(state.machines.firstInstallSetup, "awaitingExplicitActions");
  assert.equal(state.phone.stage, "awaitingExplicitActions");
  assert.equal(state.facts.permissions.camera, "authorized");
  assert.equal(canReduce(state, { type: "SETUP_ATTESTATION_TAPPED" }), true);
  assert.equal(canReduce(state, { type: "SETUP_PERMISSION_TAPPED", permission: "photos" }), true);
  assert.equal(canReduce(state, { type: "SETUP_OPTIONAL_SKIPPED", permission: "location" }), true);
  assert.equal(canReduce(state, { type: "SETUP_CONTINUE_TAPPED" }), false);
});

test("one explicit Network action reaches automatic retry wait, timeout, and explicit Retry without an implicit new attempt", () => {
  let state = activate("freshInstallOffline");
  state = reduce(state, { type: "SETUP_ATTESTATION_TAPPED" });
  assert.equal(state.machines.appAttestCredential, "bootstrapRunning");
  assert.equal(state.attestationAttempt.explicitSequence, 1);
  assert.equal(state.workloads.initialAttestation, "running");
  assert.deepEqual(nextEvent(state), { type: "SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING" });

  state = reduce(state, { type: "SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING" });
  assert.equal(state.machines.appAttestCredential, "automaticRetryWaiting");
  assert.equal(state.facts.attestation.bootstrap, "automaticRetryWaiting");
  assert.equal(state.attestationAttempt.explicitSequence, 1);
  assert.equal(state.attestationAttempt.automaticRetryWaits, 1);
  assert.equal(state.workloads.initialAttestation, "waitingNetwork");
  assert.deepEqual(nextEvent(state), { type: "SETUP_ATTESTATION_TIMED_OUT" });

  state = reduce(state, { type: "SETUP_ATTESTATION_TIMED_OUT" });
  assert.equal(state.machines.appAttestCredential, "timedOutAwaitingExplicitRetry");
  assert.equal(state.facts.attestation.bootstrap, "timedOutAwaitingExplicitRetry");
  assert.equal(state.attestationAttempt.explicitSequence, 1);
  assert.deepEqual(nextEvent(state), { type: "NETWORK_BECAME_AVAILABLE" });

  state = reduce(state, { type: "NETWORK_BECAME_AVAILABLE" });
  assert.equal(state.facts.attestation.bootstrap, "timedOutAwaitingExplicitRetry");
  assert.equal(state.machines.appAttestCredential, "timedOutAwaitingExplicitRetry");
  assert.equal(state.attestationAttempt.explicitSequence, 1);
  assert.deepEqual(nextEvent(state), { type: "SETUP_ATTESTATION_RETRY_TAPPED" });

  state = reduce(state, { type: "SETUP_ATTESTATION_RETRY_TAPPED" });
  assert.equal(state.attestationAttempt.explicitSequence, 2);
  state = reduce(state, { type: "SETUP_ATTESTATION_COMPLETED" });
  assert.equal(state.facts.attestation.bootstrap, "ready");
  assert.equal(state.machines.appAttestCredential, "bootstrapReady");
});

test("post-setup network state never changes normal launch or permission routing", () => {
  const offlineFacts = createState("ordinaryProcessLaunch").facts;
  const onlineFacts = structuredClone(offlineFacts);
  onlineFacts.attestation.network = "available";
  onlineFacts.attestation.maintenance = "failedRetryable";
  assert.deepEqual(chooseRoute(offlineFacts), { page: "viewfinder", reason: "currentFacts" });
  assert.deepEqual(chooseRoute(onlineFacts), chooseRoute(offlineFacts));

  const revokedOffline = createState("updateWithRevokedPhotos").facts;
  const revokedOnline = structuredClone(revokedOffline);
  revokedOnline.attestation.network = "available";
  assert.deepEqual(chooseRoute(revokedOnline), chooseRoute(revokedOffline));
  assert.equal(chooseRoute(revokedOffline).page, "requiredPermissionCheck");
});

test("Required Permission Check owns only Camera and Photos and automatically re-runs routing", () => {
  let state = activate("updateWithRevokedPhotos");
  assert.equal(state.machines.requiredPermissionCheck, "awaitingSettings");
  assert.throws(
    () => reduce(state, { type: "PERMISSIONS_RECHECKED", permissions: { network: "available" } }),
    /only Camera and Photos/
  );

  state = dispatch(
    state,
    { type: "PERMISSION_RECOVERY_TAPPED", permission: "photos", currentStatus: "denied" },
    { type: "PERMISSIONS_RECHECKED", permissions: { photos: "limited" } }
  );
  assert.equal(state.machines.requiredPermissionCheck, "resolved");
  assert.equal(state.phone.page, "resourceInitialization");
  assert.equal(state.facts.attestation.network, "offline");
  assert.equal(state.workloads.initialAttestation, "dormant");
});

test("a restricted required permission is a stable no-Settings-promise state", () => {
  const state = activate("foregroundResumeRestrictedCamera");
  assert.equal(state.phone.page, "requiredPermissionCheck");
  assert.equal(state.machines.requiredPermissionCheck, "restricted");
  assert.equal(nextEvent(state), null);
  assert.throws(
    () => reduce(state, { type: "PERMISSION_RECOVERY_TAPPED", permission: "camera", currentStatus: "restricted" }),
    /no promised Settings recovery/
  );
});

test("scenario selection is itself a traceable reducer event", () => {
  const previous = activate("ordinaryProcessLaunch");
  const selected = reduce(previous, { type: "SCENARIO_SELECTED", scenarioId: "freshInstall" });
  assert.equal(selected.scenarioId, "freshInstall");
  assert.equal(selected.seq, 1);
  assert.equal(selected.log.at(-1).event.type, "SCENARIO_SELECTED");
  assert.equal(selected.log.at(-1).pageBefore, "viewfinder");
  assert.equal(selected.log.at(-1).pageAfter, "dormant");
});

test("Camera and Photos usability exactly matches the permission contract", () => {
  assert.equal(photosUsable("authorized"), true);
  assert.equal(photosUsable("limited"), true);
  for (const status of ["notDetermined", "denied", "restricted"]) assert.equal(photosUsable(status), false);
  assert.equal(requiredPermissionsUsable({ camera: "authorized", photos: "limited" }), true);
  assert.equal(requiredPermissionsUsable({ camera: "denied", photos: "authorized" }), false);
  assert.equal(requiredPermissionsUsable({ camera: "authorized", photos: "restricted" }), false);
});

test("structured Initialization identity covers build, schema, and installation-device generation", () => {
  assert.equal(initializationIdentityMatches(TARGET_INITIALIZATION_IDENTITY, structuredClone(TARGET_INITIALIZATION_IDENTITY)), true);
  for (const key of ["bundleID", "shortVersion", "build", "schemaGeneration", "installationDeviceGeneration"]) {
    const changed = structuredClone(TARGET_INITIALIZATION_IDENTITY);
    changed[key] = `${changed[key]}-changed`;
    assert.equal(initializationIdentityMatches(changed, TARGET_INITIALIZATION_IDENTITY), false, key);
  }

  const crossDeviceFacts = structuredClone(scenarioFixtures.crossDeviceMigration);
  crossDeviceFacts.setupReceipt = { state: "valid", credentialBinding: "present" };
  assert.equal(chooseRoute(crossDeviceFacts).page, "resourceInitialization");
  assert.notEqual(
    crossDeviceFacts.initialization.storedIdentity.installationDeviceGeneration,
    crossDeviceFacts.initialization.targetIdentity.installationDeviceGeneration
  );
});

test("Resource Initialization commits I and reaches t4 atomically only after Camera and catalog", () => {
  let state = activate("inPlaceUpdate");
  const staleIdentity = structuredClone(state.facts.initialization.storedIdentity);
  state = makeCameraInteractive(state);
  assert.equal(state.phone.page, "resourceInitialization");
  assert.equal(state.machines.resourceInitialization, "cameraReadyCatalogPending");
  assert.equal(state.milestones.t4, null);
  assert.deepEqual(state.facts.initialization.storedIdentity, staleIdentity);

  state = dispatch(
    state,
    { type: "LIBRARY_CATALOG_STARTED" },
    { type: "LIBRARY_CATALOG_PUBLISHED", count: 908 }
  );
  assert.equal(state.phone.page, "viewfinder");
  assert.equal(state.phone.stage, "interactive");
  assert.equal(state.machines.resourceInitialization, "markerCommitted");
  assert.equal(initializationIdentityMatches(state.facts.initialization.storedIdentity, state.facts.initialization.targetIdentity), true);
  assert.equal(state.milestones.t4, state.seq);
  assert.deepEqual(state.highlight.milestones, ["t4"]);
  assert.deepEqual(state.highlight.markers.map(({ id }) => id), ["initializationCompletion"]);
  assert.ok(state.highlight.edges.some(({ edgeId }) => edgeId === "route.initializationToViewfinder"));
  assert.equal(timelineRegistry.find(({ id }) => id === "t4").allowed, "Release the deferred-work guard");
});

test("an empty first catalog snapshot remains explicitly empty and satisfies Resource Initialization", () => {
  let state = activate("localMarkerLoss");
  state = dispatch(
    state,
    { type: "LIBRARY_CATALOG_STARTED" },
    { type: "LIBRARY_CATALOG_PUBLISHED", count: 0 }
  );
  assert.equal(state.machines.libraryCatalog, "published");
  assert.equal(state.facts.library.catalog, "publishedEmpty");
  assert.equal(state.facts.library.itemCount, 0);
  assert.equal(state.phone.page, "resourceInitialization");
  state = makeCameraInteractive(state);
  assert.equal(state.phone.page, "viewfinder");
  assert.equal(state.machines.resourceInitialization, "markerCommitted");
  assert.equal(state.facts.library.catalog, "publishedEmpty");
});

test("an ordinary empty Library is a stable successful page, not fabricated media", () => {
  let state = activate("ordinaryProcessLaunchEmptyLibrary");
  state = makeCameraInteractive(state);
  state = dispatch(state, { type: "DEFERRED_WORK_RELEASED" }, { type: "LIBRARY_OPENED" });
  assert.equal(state.phone.page, "library");
  assert.equal(state.phone.stage, "catalogReady");
  assert.equal(state.facts.library.catalog, "publishedEmpty");
  assert.equal(state.facts.library.itemCount, 0);
  assert.deepEqual(nextEvent(state), { type: "SCENARIO_TERMINATED" });
});

test("ordinary offline launch becomes interactive before deferred credential and pending work", () => {
  let state = activate("ordinaryProcessLaunch");
  assert.equal(state.facts.attestation.network, "offline");
  assert.equal(state.workloads.initialAttestation, "dormant");
  state = makeCameraInteractive(state);
  assert.notEqual(state.milestones.t4, null);
  assert.equal(state.workloads.appAttestMaintenance, "dormant");
  assert.equal(state.workloads.pendingRecovery, "dormant");

  state = reduce(state, { type: "DEFERRED_WORK_RELEASED" });
  assert.equal(state.milestones.t5, state.seq);
  assert.equal(state.workloads.appAttestMaintenance, "eligible");
  assert.equal(state.workloads.pendingRecovery, "eligible");
  assert.equal(state.machines.appAttestCredential, "eligible");
  assert.equal(state.machines.pendingCaptureRecovery, "eligible");
});

test("Foreground Resume and Settings Return never mark root Library observation as launch conflict", () => {
  for (const scenarioId of ["ordinaryForegroundResume", "foregroundResumeRevoked", "settingsReturn"]) {
    let state = createState(scenarioId);
    state = reduce(state, { type: "ACTIVATION_REQUESTED" });
    assert.equal(state.machines.activation, "sceneResumed", scenarioId);
    assert.equal(state.workloads.libraryRootObservation, "dormant", scenarioId);
    assert.notEqual(state.phone.page, "systemLaunchScreen", scenarioId);
  }

  let processState = createState("ordinaryProcessLaunch");
  processState = reduce(processState, { type: "ACTIVATION_REQUESTED" });
  assert.equal(processState.workloads.libraryRootObservation, "running");
});

test("Library Back cancels a superseded catalog refresh", () => {
  let state = activate("ordinaryProcessLaunch");
  state = makeCameraInteractive(state);
  state = openColdLibrary(state);
  assert.equal(state.machines.libraryCatalog, "refreshing");
  assert.equal(state.workloads.libraryCatalog, "running");

  const routeBefore = structuredClone(state.route);
  const milestonesBefore = structuredClone(state.milestones);
  state = reduce(state, { type: "LIBRARY_BACK_TAPPED" });
  assert.equal(state.phone.page, "viewfinder");
  assert.equal(state.phone.stage, "interactive");
  assert.equal(state.machines.libraryCatalog, "stale");
  assert.equal(state.workloads.libraryCatalog, "stale");
  assert.deepEqual(state.route, routeBefore);
  assert.deepEqual(state.milestones, milestonesBefore);
  assert.deepEqual(state.highlight, state.log.at(-1).effects);
});

test("Library Back cancels an in-flight thumbnail resolution while preserving catalog facts", () => {
  let state = activate("ordinaryProcessLaunch");
  state = makeCameraInteractive(state);
  state = dispatch(
    state,
    { type: "DEFERRED_WORK_RELEASED" },
    { type: "LIBRARY_OPENED" },
    { type: "LIBRARY_CATALOG_PUBLISHED", count: 58 },
    { type: "THUMBNAIL_BATCH_STARTED" }
  );
  const libraryBefore = structuredClone(state.facts.library);
  state = reduce(state, { type: "LIBRARY_BACK_TAPPED" });
  assert.equal(state.machines.thumbnailPipeline, "cancelled");
  assert.equal(state.workloads.thumbnailDecode, "cancelled");
  assert.deepEqual(state.facts.library, libraryBefore);
  assert.equal(state.phone.page, "viewfinder");
});

test("Viewer Back during display loading cancels Viewer work and closes the Viewer machine", () => {
  let state = activate("ordinaryProcessLaunch");
  state = makeCameraInteractive(state);
  state = dispatch(
    state,
    { type: "DEFERRED_WORK_RELEASED" },
    { type: "LIBRARY_OPENED" },
    { type: "LIBRARY_CATALOG_PUBLISHED", count: 58 },
    { type: "PHOTO_OPENED", assetId: "fixture-photo-01" }
  );
  assert.equal(state.machines.viewerLoading, "displayLoading");
  assert.equal(state.workloads.viewerDisplay, "running");
  assert.equal(state.workloads.viewerFullAnalysis, "running");

  state = reduce(state, { type: "VIEWER_BACK_TAPPED" });
  assert.equal(state.phone.page, "library");
  assert.equal(state.machines.viewerLoading, "closed");
  assert.equal(state.workloads.viewerDisplay, "cancelled");
  assert.equal(state.workloads.viewerFullAnalysis, "cancelled");
  assert.equal(state.journey.viewerReturned, true);
});

test("Scenario Terminal requires a complete Viewfinder-Library-Viewer-return journey", () => {
  let state = activate("ordinaryProcessLaunch");
  state = makeCameraInteractive(state);
  state = openColdLibrary(state);
  assert.throws(() => reduce(state, { type: "SCENARIO_TERMINATED" }), /Viewer return/);

  state = dispatch(
    state,
    { type: "LIBRARY_CATALOG_PUBLISHED", count: 58 },
    { type: "THUMBNAIL_BATCH_STARTED" },
    { type: "THUMBNAIL_BATCH_PUBLISHED" },
    { type: "PHOTO_OPENED", assetId: "fixture-photo-01" },
    { type: "VIEWER_DISPLAY_READY" },
    { type: "VIEWER_BACK_TAPPED" },
    { type: "SCENARIO_TERMINATED" }
  );
  assert.equal(state.milestones.tn, state.seq);
  assert.equal(state.machines.activation, "terminal");
  assert.throws(() => reduce(state, { type: "SCENARIO_TERMINATED" }), /requires activation routeCommitted/);
});

test("a stable empty Library is a valid selected journey terminal", () => {
  let state = activate("ordinaryProcessLaunchEmptyLibrary");
  state = makeCameraInteractive(state);
  state = openColdLibrary(state);
  assert.equal(state.phone.page, "library");
  assert.equal(state.facts.library.itemCount, 0);
  assert.equal(state.journey.catalogPublished, true);
  assert.deepEqual(nextEvent(state), { type: "SCENARIO_TERMINATED" });

  state = reduce(state, { type: "SCENARIO_TERMINATED" });
  assert.equal(state.milestones.tn, state.seq);
  assert.equal(state.machines.activation, "terminal");
  assert.equal(state.journey.viewerReturned, false);
});

test("all events enforce predecessors and cannot make the timeline run backward", () => {
  const dormant = createState("ordinaryProcessLaunch");
  assert.throws(() => reduce(dormant, { type: "APP_FIRST_FRAME_COMMITTED" }), /requires activation/);
  assert.throws(() => reduce(dormant, { type: "INITIAL_ROUTE_COMMITTED" }), /requires page firstAppFrame/);

  let state = reduce(dormant, { type: "ACTIVATION_REQUESTED" });
  assert.throws(() => reduce(state, { type: "ACTIVATION_REQUESTED" }), /requires activation idle/);
  state = reduce(state, { type: "APP_FIRST_FRAME_COMMITTED" });
  assert.throws(() => reduce(state, { type: "CAMERA_PREVIEW_PRESENTED" }), /requires page/);
  state = reduce(state, { type: "INITIAL_ROUTE_COMMITTED" });
  assert.throws(() => reduce(state, { type: "CAMERA_PREVIEW_PRESENTED" }), /requires cameraReadiness configuring/);
  assert.throws(() => reduce(state, { type: "DEFERRED_WORK_RELEASED" }), /requires cameraReadiness interactive/);

  const reached = Object.values(state.milestones).filter((value) => value != null);
  assert.deepEqual(reached, [...reached].sort((a, b) => a - b));
  assert.equal(new Set(reached).size, reached.length);
});

test("machine IDs/states and workload states always belong to their canonical registries", () => {
  for (const alias of ["setup", "permissionCheck", "appAttest", "pendingRecovery"]) {
    assert.equal(Object.hasOwn(machineRegistry, alias), false, alias);
  }
  for (const id of ["firstInstallSetup", "requiredPermissionCheck", "appAttestCredential", "pendingCaptureRecovery", "viewerAnalysis"]) {
    assert.equal(Object.hasOwn(machineRegistry, id), true, id);
  }

  for (const scenarioId of Object.keys(scenarioFixtures)) {
    let state = createState(scenarioId);
    let steps = 0;
    while (state.milestones.tn == null && steps < 80) {
      for (const [machineId, node] of Object.entries(state.machines)) {
        assert.ok(machineRegistry[machineId].nodes.includes(node), `${scenarioId}:${machineId}:${node}`);
      }
      for (const [workloadId, status] of Object.entries(state.workloads)) {
        assert.ok(workloadStates.includes(status), `${scenarioId}:${workloadId}:${status}`);
      }
      const event = nextEvent(state);
      if (scenarioId === "foregroundResumeRestrictedCamera" && event == null) {
        assert.equal(state.phone.page, "requiredPermissionCheck");
        assert.equal(state.machines.requiredPermissionCheck, "restricted");
        break;
      }
      assert.ok(event, `${scenarioId} stopped at ${state.phone.page}/${state.phone.stage}`);
      state = reduce(state, event);
      steps += 1;
    }
    if (scenarioId !== "foregroundResumeRestrictedCamera") assert.notEqual(state.milestones.tn, null, scenarioId);
    assert.ok(steps < 80, scenarioId);
  }
});

test("every workload names its machine, current/target placement, alignment, and source evidence", () => {
  const alignments = new Set(["aligned", "partial", "gap", "deferred"]);
  for (const [workloadId, workload] of Object.entries(workloadRegistry)) {
    assert.ok(machineRegistry[workload.machineId], `${workloadId}:machineId`);
    assert.ok(alignments.has(workload.alignment), `${workloadId}:alignment`);
    assert.ok(Array.isArray(workload.pages) && workload.pages.length > 0, `${workloadId}:pages`);

    for (const field of ["trigger", "owner", "earliest", "blocks", "network"]) {
      assert.equal(typeof workload.observed?.[field], "string", `${workloadId}:observed.${field}`);
      assert.ok(workload.observed[field].length > 0, `${workloadId}:observed.${field}`);
      assert.equal(typeof workload.target?.[field], "string", `${workloadId}:target.${field}`);
      assert.ok(workload.target[field].length > 0, `${workloadId}:target.${field}`);
    }
    assert.equal(typeof workload.observed.evidence, "string", `${workloadId}:observed.evidence`);
    assert.ok(workload.observed.evidence.length > 0, `${workloadId}:observed.evidence`);
    assert.ok(Array.isArray(workload.target.forbiddenDuring), `${workloadId}:target.forbiddenDuring`);
    assert.equal(typeof workload.target.task, "string", `${workloadId}:target.task`);
    assert.ok(workload.target.task.length > 0, `${workloadId}:target.task`);
  }
});

test("nextEvent uses the canonical t0/t1/t2 and offline App Attest sequence", () => {
  let state = createState("freshInstallOffline");
  const events = [];
  while (events.length < 9) {
    const event = nextEvent(state);
    events.push(event.type);
    state = reduce(state, event);
  }
  assert.deepEqual(events, [
    "ACTIVATION_REQUESTED",
    "APP_FIRST_FRAME_COMMITTED",
    "INITIAL_ROUTE_COMMITTED",
    "SETUP_ATTESTATION_TAPPED",
    "SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING",
    "SETUP_ATTESTATION_TIMED_OUT",
    "NETWORK_BECAME_AVAILABLE",
    "SETUP_ATTESTATION_RETRY_TAPPED",
    "SETUP_ATTESTATION_COMPLETED"
  ]);
});

test("Debug and debugger attachment remain measurement dimensions, not route facts", () => {
  let state = activate("ordinaryProcessLaunch");
  const routeBefore = structuredClone(state.route);
  state = reduce(state, {
    type: "MEASUREMENT_PROFILE_CHANGED",
    measurement: { build: "Debug", debuggerAttached: true, resourcePath: "cold" }
  });
  assert.deepEqual(state.route, routeBefore);
  assert.equal(state.phone.page, "viewfinder");
});

test("every dispatch exposes one trace shared by timeline, machines, workloads, markers, and phone", () => {
  let state = activate("freshInstall");
  state = dispatch(
    state,
    { type: "SETUP_ATTESTATION_TAPPED" },
    { type: "SETUP_ATTESTATION_COMPLETED" }
  );
  state = authorizeSetupPermission(state, "camera");
  state = authorizeSetupPermission(state, "photos");
  state = reduce(state, { type: "SETUP_CONTINUE_TAPPED" });

  const snapshot = publicSnapshot(state);
  assert.equal(state.highlight.seq, state.seq);
  assert.equal(state.log.at(-1).seq, state.seq);
  assert.deepEqual(state.highlight, state.log.at(-1).effects);
  assert.deepEqual(snapshot.highlight, snapshot.lastTrace.effects);
  assert.equal(state.log.at(-1).pageAfter, state.highlight.page);
  assert.ok(state.highlight.machines.length > 0);
  assert.ok(state.highlight.edges.length > 0);
  assert.ok(state.highlight.workloads.length > 0);
  assert.ok(state.highlight.markers.length > 0);
});

test("the TAP-0087 state model contains no Share, AirDrop, or Locked Camera behavior", () => {
  for (const [workloadId, workload] of Object.entries(workloadRegistry)) {
    assert.doesNotMatch(workloadId, /share|airdrop/i);
    assert.doesNotMatch(`${workload.label} ${workload.family}`, /(?:^|[^A-Za-z])Share(?:[^A-Za-z]|$)|AirDrop/i);
  }
  assert.doesNotMatch(modelSource, /\bSHARE_[A-Z0-9_]+\b/);
  assert.doesNotMatch(modelSource, /UIActivityViewController|AirDrop|Locked[ -]?Camera/i);

  const state = activate("ordinaryProcessLaunch");
  for (const type of ["SHARE_TAPPED", "SHARE_PAYLOAD_STARTED", "SHARE_COMPLETED", "AIRDROP_SELECTED", "LOCKED_CAMERA_STARTED", "VIEWER_2D_SELECTED", "VIEWER_3D_SELECTED"]) {
    assert.throws(() => reduce(state, { type }), /Unsupported event/);
  }
});

test("a Viewer continuity journal replays entirely through the canonical reducer", () => {
  const baseScenarioId = "ordinaryProcessLaunch";
  let live = createState(baseScenarioId);
  const events = [];
  let steps = 0;
  while (live.phone.page !== "photoViewer" && steps < 40) {
    const event = nextEvent(live);
    assert.ok(event, `journey stopped at ${live.phone.page}/${live.phone.stage}`);
    assert.doesNotMatch(event.type, /^SHARE_/);
    events.push(structuredClone(event));
    live = reduce(live, event);
    steps += 1;
  }

  assert.equal(live.phone.page, "photoViewer");
  assert.ok(live.phone.selectedAssetId);
  const restored = events.reduce((current, event) => reduce(current, event), createState(baseScenarioId));
  assert.equal(restored.seq, live.seq);
  assert.equal(restored.scenarioId, live.scenarioId);
  assert.equal(restored.phone.page, "photoViewer");
  assert.equal(restored.phone.selectedAssetId, live.phone.selectedAssetId);
  assert.deepEqual(publicSnapshot(restored), publicSnapshot(live));
  assert.ok(steps < 40);
});

test("public snapshots are detached and illegal cross-domain events do not mutate state", () => {
  const state = activate("ordinaryProcessLaunch");
  const before = structuredClone(state);
  assert.throws(() => reduce(state, { type: "SETUP_ATTESTATION_TAPPED" }), /requires page firstInstallSetup/);
  assert.throws(() => reduce(state, { type: "PHOTO_OPENED" }), /requires page library/);
  assert.throws(() => reduce(state, { type: "LIBRARY_BACK_TAPPED" }), /requires page library/);
  assert.deepEqual(state, before);

  const snapshot = publicSnapshot(state);
  snapshot.phone.page = "mutatedOutside";
  assert.equal(state.phone.page, "viewfinder");
});
