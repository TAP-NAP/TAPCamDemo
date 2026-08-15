import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import {
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
  PROTOTYPE_DIFFERENCE_DATA_SOURCE,
  PROTOTYPE_DIFFERENCE_DATA_STATUS,
  publicSnapshot,
  reduce,
  resolveWorkloadDifferenceTraceBinding,
  requiredPermissionsUsable,
  scenarioFixtures,
  setupRequiredReady,
  TARGET_INITIALIZATION_IDENTITY,
  timelineRegistry,
  workloadInspectionReached,
  workloadInspectionRegistry,
  workloadDifferenceRegistry,
  workloadDifferenceScenarioRegistry,
  workloadLaneTruthRecordIDs,
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

const replayScenarioColumns = (scenarioId, limit = 80) => {
  let state = createState(scenarioId);
  const columns = [];
  for (let index = 0; index < limit; index += 1) {
    const event = nextEvent(state);
    if (!event) break;
    state = reduce(state, event);
    const entry = state.log.at(-1);
    columns.push({
      entry,
      milestones: entry.effects.milestones || [],
      stateAfter: structuredClone(state)
    });
    if (event.type === "SCENARIO_TERMINATED") break;
  }
  return { state, columns };
};

test("TAP-0008/TAP-0009 code-truth records use explicit lifecycle anchors", () => {
  const timelineIDs = new Set(timelineRegistry.map(({ id }) => id));
  const truthIDs = lifecycleTruthRegistry.map(({ id }) => id);
  assert.equal(new Set(truthIDs).size, truthIDs.length);
  assert.ok(lifecycleTruthRegistry.length >= 10);

  for (const truth of lifecycleTruthRegistry) {
    assert.ok(truth.taskIDs.some((taskID) => taskID === "TAP-0008" || taskID === "TAP-0009"), truth.id);
    assert.ok(timelineIDs.has(truth.actual.anchor), `${truth.id} actual anchor`);
    assert.ok(timelineIDs.has(truth.target.anchor), `${truth.id} target anchor`);
    assert.ok(truth.actual.phase && truth.actual.summary && truth.actual.evidence, `${truth.id} actual record`);
    assert.ok(truth.target.phase && truth.target.summary && truth.target.evidence, `${truth.id} target record`);
    assert.equal(truth.mismatch, truth.alignment !== "aligned", truth.id);
  }

  const aligned = lifecycleTruthRegistry.filter(({ mismatch }) => !mismatch).map(({ id }) => id);
  assert.deepEqual(aligned.sort(), ["explicitPermissionActions", "optionalPermissionPolicy"]);
  assert.equal(
    lifecycleTruthRegistry.filter(({ mismatch }) => !mismatch).every(({ fix0809Disposition, fix0809Outcome }) => (
      fix0809Disposition == null && fix0809Outcome == null
    )),
    true,
    "aligned records are outside fix0809 mismatch scope"
  );
  const truthManifest = manifest.independentCandidates.startupLifecycle.workbench.right.tap0008Tap0009CodeTruth;
  assert.equal(truthManifest.schemaVersion, 3);
  const mismatchTruths = lifecycleTruthRegistry.filter(({ mismatch }) => mismatch);
  for (const truth of mismatchTruths) {
    const disposition = fix0809DispositionRegistry[truth.fix0809Disposition];
    const outcome = fix0809OutcomeRegistry[truth.fix0809Outcome];
    assert.ok(disposition, `${truth.id} fix0809 disposition`);
    assert.ok(outcome, `${truth.id} fix0809 outcome`);
    assert.equal(disposition.renderAsMismatch, true, `${truth.id} remains mismatch`);
    assert.equal(outcome.preservesBaselineMismatch, true, `${truth.id} outcome preserves baseline mismatch`);
  }
  assert.deepEqual(
    mismatchTruths.filter(({ fix0809Disposition }) => fix0809Disposition === "approvedToFix").map(({ id }) => id).sort(),
    [
      "cameraReadinessPredicate",
      "deferredWorkGuard",
      "initializationCommit",
      "legacyReceiptAndMarker",
      "libraryReadinessPredicate",
      "permissionRecoverySemantics",
      "preFrameLibraryObserver",
      "requiredPermissionRoute",
      "resourceInitializationSurface",
      "retainedContainerRouting",
      "returningCameraConstruction"
    ]
  );
  assert.deepEqual(
    mismatchTruths.filter(({ fix0809Disposition }) => fix0809Disposition === "deferredFrozen").map(({ id }) => id),
    ["networkBootstrap"]
  );
  assert.equal(truthManifest.fix0809DispositionSummary.approvedToFixMismatchCount, 11);
  assert.equal(truthManifest.fix0809DispositionSummary.deferredFrozenMismatchCount, 1);
  assert.equal(truthManifest.fix0809DispositionSummary.ownerDecisionRecordedAt, "2026-08-15");
  assert.match(truthManifest.fix0809DispositionSummary.ownerDecision, /retain the existing Network and App Attest implementation/);
  assert.match(truthManifest.fix0809DispositionSummary.ownerDecision, /must not change network behavior or treat \/healthz as the target state/);
  assert.match(truthManifest.fix0809DispositionSummary.policy, /ownerReviewRequired/);
  assert.match(fix0809DispositionRegistry.deferredFrozen.visibleLabel, /本轮暂缓 · Network frozen/);
  assert.equal(fix0809DispositionRegistry.deferredFrozen.includedInFix0809, false);
  assert.deepEqual(
    mismatchTruths.filter(({ fix0809Outcome }) => fix0809Outcome === "implementedLogAccepted").map(({ id }) => id).sort(),
    ["cameraReadinessPredicate", "initializationCommit", "libraryReadinessPredicate"]
  );
  assert.deepEqual(
    mismatchTruths.filter(({ fix0809Outcome }) => fix0809Outcome === "implementedNotLogVerified").map(({ id }) => id).sort(),
    [
      "deferredWorkGuard",
      "legacyReceiptAndMarker",
      "permissionRecoverySemantics",
      "preFrameLibraryObserver",
      "requiredPermissionRoute",
      "resourceInitializationSurface",
      "retainedContainerRouting",
      "returningCameraConstruction"
    ]
  );
  assert.deepEqual(
    mismatchTruths.filter(({ fix0809Outcome }) => fix0809Outcome === "deferredFrozen").map(({ id }) => id),
    ["networkBootstrap"]
  );
  assert.deepEqual(truthManifest.fix0809OutcomeSummary, {
    baselineRef: "main@4cc02e5f12f2",
    candidateRef: "fix0809@66ac001",
    implementedLogAcceptedMismatchCount: 3,
    implementedNotLogVerifiedMismatchCount: 8,
    deferredFrozenMismatchCount: 1,
    alignedUnchangedCount: 2,
    ownerDecisionRecordedAt: "2026-08-15",
    evidence: "Docs/Acceptance/TAP-0041-camera-readiness.md#2026-08-15-bounded-device-observation",
    policy: truthManifest.fix0809OutcomeSummary.policy
  });
  assert.match(truthManifest.fix0809OutcomeSummary.policy, /yellow\/yellow/);
  assert.deepEqual(
    Object.fromEntries(Object.entries(fix0809OutcomeRegistry).map(([id, outcome]) => (
      [id, [outcome.fillTone, outcome.borderTone]]
    ))),
    {
      implementedLogAccepted: ["yellow", "yellow"],
      implementedNotLogVerified: ["yellow", "red"],
      deferredFrozen: ["red", "red"]
    }
  );
  const networkBootstrap = lifecycleTruthRegistry.find(({ id }) => id === "networkBootstrap");
  assert.match(networkBootstrap.actual.summary, /healthz/);
  assert.match(networkBootstrap.target.summary, /App Attest registration \/ verification/);
  assert.doesNotMatch(networkBootstrap.target.summary, /healthz/);
  assert.equal(manifest.independentCandidates.startupLifecycle.workbench.revision, "v17");
  assert.equal(truthManifest.recordCount, lifecycleTruthRegistry.length);
  assert.equal(truthManifest.mismatchCount, lifecycleTruthRegistry.filter(({ mismatch }) => mismatch).length);
  assert.equal(truthManifest.alignedCount, aligned.length);
  assert.equal(lifecycleTruthRegistry.find(({ id }) => id === "cameraReadinessPredicate").actual.anchor, "t3");
  assert.equal(lifecycleTruthRegistry.find(({ id }) => id === "initializationCommit").actual.anchor, "t4");
  assert.equal(lifecycleTruthRegistry.find(({ id }) => id === "deferredWorkGuard").actual.anchor, "t5");
  assert.deepEqual(lifecycleTruthRegistry, truthManifest.records);
  assert.equal(PROTOTYPE_DIFFERENCE_DATA_SOURCE, "Prototype/manifest.json");
  assert.deepEqual(PROTOTYPE_DIFFERENCE_DATA_STATUS, { loaded: true, error: null });
  assert.doesNotMatch(modelSource, /id:\s*"legacyReceiptAndMarker"/);
});

test("lifecycle and workload mismatches have disjoint JSON-backed Timing owners", () => {
  const truthManifest = manifest.independentCandidates.startupLifecycle.workbench.right.tap0008Tap0009CodeTruth;
  const comparison = truthManifest.workloadDifferenceComparison;
  assert.equal(comparison.schemaVersion, 4);
  const timelineIDs = new Set(timelineRegistry.map(({ id }) => id));
  const workloadIDs = new Set(Object.keys(workloadRegistry));
  const recordIDs = workloadDifferenceRegistry.map(({ id }) => id);
  const mismatchTruthIDs = new Set(lifecycleTruthRegistry.filter(({ mismatch }) => mismatch).map(({ id }) => id));
  const lifecycleOwnerIDs = new Set(lifecycleTimingLaneRecordIDs);
  const workloadOwnerIDs = new Set(workloadLaneTruthRecordIDs);

  assert.equal(new Set(recordIDs).size, recordIDs.length);
  assert.deepEqual(workloadDifferenceRegistry, comparison.records);
  assert.equal(comparison.recordCount, comparison.records.length);
  assert.equal(comparison.mismatchCount, comparison.records.filter(({ mismatch }) => mismatch).length);
  assert.equal(comparison.records.length, 13);
  assert.equal(comparison.timingMismatchCount, comparison.records.filter(({ differenceType }) => differenceType === "timing").length);
  assert.equal(comparison.semanticMismatchCount, comparison.records.filter(({ differenceType }) => differenceType === "semantic").length);
  assert.equal(comparison.timingMismatchCount, 10);
  assert.equal(comparison.semanticMismatchCount, 3);
  assert.equal(lifecycleOwnerIDs.size, 6);
  assert.equal(workloadOwnerIDs.size, 6);
  assert.deepEqual([...lifecycleOwnerIDs].filter((id) => workloadOwnerIDs.has(id)), []);
  assert.deepEqual(new Set([...lifecycleOwnerIDs, ...workloadOwnerIDs]), mismatchTruthIDs);

  for (const difference of workloadDifferenceRegistry) {
    assert.ok(["timing", "semantic"].includes(difference.differenceType), difference.id);
    assert.equal(difference.mismatch, true, difference.id);
    assert.ok(fix0809DispositionRegistry[difference.fix0809Disposition], `${difference.id} fix0809 disposition`);
    assert.ok(fix0809OutcomeRegistry[difference.fix0809Outcome], `${difference.id} fix0809 outcome`);
    const sourceTruthDispositions = new Set(difference.lifecycleTruthIDs.map((truthID) => (
      lifecycleTruthRegistry.find(({ id }) => id === truthID)?.fix0809Disposition
    )));
    if (!sourceTruthDispositions.has(difference.fix0809Disposition)) {
      assert.equal(difference.fix0809Disposition, "deferredFrozen", `${difference.id} may only narrow to deferred`);
      assert.ok(
        comparison.fix0809DispositionSummary.deferredFrozenWorkloadRecordIDs.includes(difference.id),
        `${difference.id} explicit child narrowing`
      );
    }
    assert.ok(difference.scope?.path && difference.scope?.trigger && difference.scope?.anchorMeaning, difference.id);
    assert.ok(difference.lifecycleTruthIDs.length > 0, difference.id);
    assert.ok(difference.lifecycleTruthIDs.every((id) => workloadOwnerIDs.has(id)), `${difference.id} truth ownership`);
    assert.ok(workloadIDs.has(difference.actual.workloadID), `${difference.id} actual workload`);
    assert.ok(workloadIDs.has(difference.target.workloadID), `${difference.id} target workload`);
    assert.ok(timelineIDs.has(difference.actual.anchor), `${difference.id} actual anchor`);
    assert.ok(timelineIDs.has(difference.target.anchor), `${difference.id} target anchor`);
    assert.ok(difference.actual.phase && difference.actual.summary && difference.actual.evidence, `${difference.id} actual evidence`);
    assert.ok(difference.target.phase && difference.target.summary && difference.target.evidence, `${difference.id} target evidence`);
    const binding = difference.traceBinding;
    assert.ok(Array.isArray(workloadDifferenceScenarioRegistry[binding?.scenarioGroupID]), `${difference.id} scenario group`);
    assert.ok(binding.actualVisibleAfter.eventTypes.length > 0, `${difference.id} visibility events`);
    assert.ok(binding.targetEffect.eventTypes.length > 0, `${difference.id} target events`);
    assert.equal(binding.targetEffect.workloadID, difference.target.workloadID, `${difference.id} target workload binding`);
    assert.ok(workloadStates.includes(binding.targetEffect.status), `${difference.id} target status`);
    assert.ok(Number.isInteger(binding.targetEffect.occurrence) && binding.targetEffect.occurrence > 0, `${difference.id} target occurrence`);
  }

  const scenarioIDs = new Set(Object.keys(scenarioFixtures));
  for (const [groupID, groupedScenarioIDs] of Object.entries(workloadDifferenceScenarioRegistry)) {
    assert.ok(groupedScenarioIDs.length > 0, groupID);
    assert.equal(new Set(groupedScenarioIDs).size, groupedScenarioIDs.length, `${groupID} duplicate scenarios`);
    assert.ok(groupedScenarioIDs.every((scenarioID) => scenarioIDs.has(scenarioID)), `${groupID} unknown scenario`);
  }

  const coveredWorkloadTruthIDs = new Set(workloadDifferenceRegistry.flatMap(({ lifecycleTruthIDs }) => lifecycleTruthIDs));
  assert.deepEqual(coveredWorkloadTruthIDs, workloadOwnerIDs);
  assert.deepEqual(comparison.projectionCounts, {
    lifecycleMismatchCards: 6,
    migratedLifecycleTruthSources: 6,
    workloadDifferenceCards: 13,
    workloadTimingCards: 10,
    workloadSemanticCards: 3,
    maximumRenderedMismatchCards: 19
  });

  const excludedIDs = comparison.excludedFromWorkloadMismatch.map(({ comparisonID }) => comparisonID);
  assert.equal(new Set(excludedIDs).size, excludedIDs.length);
  assert.deepEqual(excludedIDs.sort(), ["startupFactsShapeOnly", "thumbnailDecodeAligned"]);
  assert.equal(workloadDifferenceRegistry.some(({ id }) => id === "attestationRetryStartsOnRefresh"), false);
  assert.equal(workloadDifferenceRegistry.some(({ id }) => id === "firstPreviewGateConsumption"), true);
  assert.deepEqual(
    workloadDifferenceRegistry
      .filter(({ fix0809Disposition }) => fix0809Disposition === "deferredFrozen")
      .map(({ id }) => id)
      .sort(),
    [
      "firstInstallCredentialStartsAfterContinue",
      "initialAttestationCompletionMeaning",
      "pendingRecoveryLacksDeferredReleaseGuard",
      "postSetupAttestLacksDeferredReleaseGuard"
    ]
  );
  assert.equal(
    workloadDifferenceRegistry.filter(({ fix0809Disposition }) => fix0809Disposition === "approvedToFix").length,
    9
  );
  assert.equal(comparison.fix0809DispositionSummary.approvedToFixMismatchCount, 9);
  assert.equal(comparison.fix0809DispositionSummary.deferredFrozenMismatchCount, 4);
  assert.deepEqual(
    [...comparison.fix0809DispositionSummary.deferredFrozenWorkloadRecordIDs].sort(),
    workloadDifferenceRegistry
      .filter(({ fix0809Disposition }) => fix0809Disposition === "deferredFrozen")
      .map(({ id }) => id)
      .sort()
  );
  assert.deepEqual(
    workloadDifferenceRegistry
      .filter(({ fix0809Outcome }) => fix0809Outcome === "implementedLogAccepted")
      .map(({ id }) => id)
      .sort(),
    [
      "cameraInteractionReadyEligibilityOmitsPreviewSafety",
      "firstPreviewGateConsumption",
      "libraryCatalogReadyNotConsumedByInitialization",
      "libraryCatalogStartsBeforeRouteOwnership",
      "recentCoverLacksDeferredReleaseGuard"
    ]
  );
  assert.deepEqual(
    workloadDifferenceRegistry
      .filter(({ fix0809Outcome }) => fix0809Outcome === "implementedNotLogVerified")
      .map(({ id }) => id)
      .sort(),
    [
      "cameraDiscoveryStartsPreRoute",
      "cameraSessionConstructionStartsPreRoute",
      "libraryObserverStartsPreFrame",
      "videoPosterStartsBeforeDeferredRelease"
    ]
  );
  assert.equal(comparison.fix0809OutcomeSummary.implementedLogAcceptedMismatchCount, 5);
  assert.equal(comparison.fix0809OutcomeSummary.implementedNotLogVerifiedMismatchCount, 4);
  assert.equal(comparison.fix0809OutcomeSummary.deferredFrozenMismatchCount, 4);
  assert.deepEqual(
    [...comparison.fix0809OutcomeSummary.implementedLogAcceptedWorkloadRecordIDs].sort(),
    workloadDifferenceRegistry
      .filter(({ fix0809Outcome }) => fix0809Outcome === "implementedLogAccepted")
      .map(({ id }) => id)
      .sort()
  );
  assert.deepEqual(
    [...comparison.fix0809OutcomeSummary.implementedNotLogVerifiedWorkloadRecordIDs].sort(),
    workloadDifferenceRegistry
      .filter(({ fix0809Outcome }) => fix0809Outcome === "implementedNotLogVerified")
      .map(({ id }) => id)
      .sort()
  );
  assert.deepEqual(
    [...comparison.fix0809OutcomeSummary.deferredFrozenWorkloadRecordIDs].sort(),
    workloadDifferenceRegistry
      .filter(({ fix0809Outcome }) => fix0809Outcome === "deferredFrozen")
      .map(({ id }) => id)
      .sort()
  );

  const firstInstallCredential = workloadDifferenceRegistry.find(({ id }) => id === "firstInstallCredentialStartsAfterContinue");
  assert.equal(firstInstallCredential.actual.anchor, "t2");
  assert.equal(firstInstallCredential.target.anchor, "t2");
  assert.match(firstInstallCredential.actual.phase, /post-Continue/);
  assert.match(firstInstallCredential.target.phase, /before Continue/);
  assert.equal(workloadDifferenceRegistry.find(({ id }) => id === "videoPosterStartsBeforeDeferredRelease").target.anchor, "t5");
  assert.equal(workloadDifferenceRegistry.find(({ id }) => id === "initialAttestationCompletionMeaning").differenceType, "semantic");
  assert.equal(workloadDifferenceRegistry.find(({ id }) => id === "libraryCatalogReadyNotConsumedByInitialization").target.anchor, "t4");
  assert.doesNotMatch(modelSource, /id:\s*"libraryObserverStartsPreFrame"/);
});

test("JSON workload bindings resolve only to applicable recorded target effects", () => {
  const replayCache = new Map();
  const replay = (scenarioID) => {
    if (!replayCache.has(scenarioID)) replayCache.set(scenarioID, replayScenarioColumns(scenarioID));
    return replayCache.get(scenarioID);
  };

  let concreteBindingCoverage = 0;
  for (const difference of workloadDifferenceRegistry) {
    const scenarioIDs = workloadDifferenceScenarioRegistry[difference.traceBinding.scenarioGroupID];
    for (const scenarioID of scenarioIDs) {
      concreteBindingCoverage += 1;
      const { columns } = replay(scenarioID);
      const resolved = resolveWorkloadDifferenceTraceBinding(difference, scenarioID, columns);
      const assertionScope = `${difference.id} / ${scenarioID}`;
      assert.equal(resolved.applicable, true, assertionScope);
      assert.equal(resolved.visible, true, `${assertionScope} visibility projection`);
      assert.ok(resolved.actualColumn?.milestones.includes(difference.actual.anchor), `${assertionScope} actual anchor column`);
      assert.ok(resolved.targetColumn, `${assertionScope} target effect`);
      assert.ok(
        difference.traceBinding.targetEffect.eventTypes.includes(resolved.targetColumn.entry.event.type),
        `${assertionScope} target event`
      );
      assert.ok(
        resolved.targetColumn.entry.effects.workloads.includes(difference.target.workloadID),
        `${assertionScope} target workload effect`
      );
      assert.equal(
        resolved.targetColumn.stateAfter.workloads[difference.target.workloadID],
        difference.traceBinding.targetEffect.status,
        `${assertionScope} target status`
      );
    }

    const excludedScenarioID = Object.keys(scenarioFixtures).find((candidate) => !scenarioIDs.includes(candidate));
    const excluded = resolveWorkloadDifferenceTraceBinding(difference, excludedScenarioID, replay(excludedScenarioID).columns);
    assert.equal(excluded.applicable, false, `${difference.id} cross-scenario exclusion`);
    assert.equal(excluded.visible, false, `${difference.id} cross-scenario visibility`);
    assert.equal(excluded.targetColumn, null, `${difference.id} cross-scenario target`);
  }
  assert.equal(concreteBindingCoverage, 154, "every manifest record/scenario binding is replayed");

  let earlyState = createState("ordinaryProcessLaunch");
  const earlyColumns = [];
  for (const event of [
    { type: "ACTIVATION_REQUESTED" },
    { type: "APP_FIRST_FRAME_COMMITTED" },
    { type: "INITIAL_ROUTE_COMMITTED" }
  ]) {
    earlyState = reduce(earlyState, event);
    const entry = earlyState.log.at(-1);
    earlyColumns.push({ entry, milestones: entry.effects.milestones || [], stateAfter: structuredClone(earlyState) });
  }
  const deferred = workloadDifferenceRegistry.find(({ id }) => id === "videoPosterStartsBeforeDeferredRelease");
  const unresolved = resolveWorkloadDifferenceTraceBinding(deferred, "ordinaryProcessLaunch", earlyColumns);
  assert.equal(unresolved.visible, true);
  assert.equal(unresolved.targetColumn, null);

  const directLibrary = workloadDifferenceRegistry.find(({ id }) => id === "libraryCatalogStartsBeforeRouteOwnership");
  const directLibraryBinding = resolveWorkloadDifferenceTraceBinding(
    directLibrary,
    "ordinaryProcessLaunch",
    replay("ordinaryProcessLaunch").columns
  );
  assert.equal(directLibraryBinding.targetColumn.entry.event.type, "LIBRARY_OPENED");
  assert.equal(directLibraryBinding.targetColumn.stateAfter.workloads.libraryCatalog, "running");

  const catalogGate = workloadDifferenceRegistry.find(({ id }) => id === "libraryCatalogReadyNotConsumedByInitialization");
  const initializationColumns = replay("inPlaceUpdate").columns;
  const catalogPublishedIndex = initializationColumns.findIndex(({ entry }) => entry.event.type === "LIBRARY_CATALOG_PUBLISHED");
  const catalogBeforeT4 = resolveWorkloadDifferenceTraceBinding(
    catalogGate,
    "inPlaceUpdate",
    initializationColumns.slice(0, catalogPublishedIndex + 1)
  );
  assert.equal(catalogBeforeT4.visible, true, "JSON visibility checkpoint exposes the actual difference before coarse t4 exists");
  assert.equal(catalogBeforeT4.actualColumn, null, "coarse lifecycle anchor is a label, not a visibility gate");
  assert.equal(catalogBeforeT4.targetColumn.entry.event.type, "LIBRARY_CATALOG_PUBLISHED");
  assert.equal(catalogBeforeT4.targetColumn.stateAfter.workloads.libraryCatalog, "succeeded");
});

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
  assert.equal(processState.workloads.libraryRootObservation, "dormant");
  processState = reduce(processState, { type: "APP_FIRST_FRAME_COMMITTED" });
  assert.equal(processState.workloads.libraryRootObservation, "dormant");
  processState = reduce(processState, { type: "INITIAL_ROUTE_COMMITTED" });
  assert.equal(processState.workloads.libraryRootObservation, "succeeded");
});

test("fresh install activates root Library observation only after explicit Photos authorization", () => {
  let state = activate("freshInstall");
  assert.equal(state.workloads.libraryRootObservation, "dormant");

  state = authorizeSetupPermission(state, "photos");
  assert.equal(state.facts.permissions.photos, "authorized");
  assert.equal(state.workloads.libraryRootObservation, "succeeded");
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

test("workload inspection journeys replay canonical reducer journals without synthetic focus events", () => {
  assert.deepEqual(
    Object.keys(workloadInspectionRegistry).sort(),
    Object.keys(workloadRegistry).sort()
  );

  for (const [workloadId, plan] of Object.entries(workloadInspectionRegistry)) {
    const journey = buildWorkloadInspectionJourney(workloadId);
    assert.equal(workloadInspectionReached(journey.state, workloadId), true, workloadId);
    assert.equal(journey.plan.scenarioId, plan.scenarioId, `${workloadId}:scenarioId`);
    assert.equal(journey.state.scenarioId, plan.scenarioId, `${workloadId}:state.scenarioId`);
    assert.equal(journey.state.phone.page, plan.page, `${workloadId}:page`);
    assert.equal(journey.state.workloads[workloadId], plan.status, `${workloadId}:status`);
    assert.equal(journey.state.log.at(-1).event.type, plan.eventType, `${workloadId}:eventType`);
    assert.ok(journey.state.log.at(-1).effects.workloads.includes(workloadId), `${workloadId}:matching trace`);
    assert.equal(journey.history.at(-1).seq, journey.state.seq, `${workloadId}:history tail`);
    assert.deepEqual(journey.history.map(({ seq }) => seq),
      Array.from({ length: journey.state.seq + 1 }, (_, index) => index),
      `${workloadId}:complete history`);

    const replayed = journey.state.log.reduce(
      (state, entry) => reduce(state, entry.event),
      createState(plan.scenarioId)
    );
    assert.deepEqual(publicSnapshot(replayed), publicSnapshot(journey.state), `${workloadId}:journal replay`);
    assert.doesNotMatch(
      journey.state.log.map((entry) => entry.event.type).join(" "),
      /WORKLOAD_(?:FOCUSED|READY)|INSPECTION_(?:OPENED|READY)/,
      `${workloadId}:synthetic event`
    );

    const withoutMatchingEffect = structuredClone(journey.state);
    withoutMatchingEffect.log.at(-1).effects.workloads = withoutMatchingEffect.log.at(-1).effects.workloads
      .filter((candidate) => candidate !== workloadId);
    assert.equal(workloadInspectionReached(withoutMatchingEffect, workloadId), false, `${workloadId}:effect required`);

    if (plan.status === "succeeded") {
      for (const nonReadyStatus of ["cancelled", "stale"]) {
        const nonReady = structuredClone(journey.state);
        nonReady.workloads[workloadId] = nonReadyStatus;
        assert.equal(workloadInspectionReached(nonReady, workloadId), false, `${workloadId}:${nonReadyStatus}`);
      }
    }
  }

  assert.throws(
    () => buildWorkloadInspectionJourney("not-a-workload"),
    /Unknown workload inspection target/
  );
  assert.throws(
    () => buildWorkloadInspectionJourney("initialAttestation", { stepLimit: 0 }),
    /Canonical journal did not reach workload inspection target/
  );
});

test("initial Attestation inspection opens successful fresh-install Setup while deferred and eligible targets stay non-Ready", () => {
  const attestationReview = buildWorkloadInspectionJourney("initialAttestation");
  assert.equal(attestationReview.plan.scenarioId, "freshInstall");
  assert.equal(attestationReview.state.phone.page, "firstInstallSetup");
  assert.equal(attestationReview.state.workloads.initialAttestation, "succeeded");
  assert.equal(attestationReview.state.machines.appAttestCredential, "bootstrapReady");
  assert.deepEqual(attestationReview.state.log.map(({ event }) => event.type), [
    "SCENARIO_SELECTED",
    "ACTIVATION_REQUESTED",
    "APP_FIRST_FRAME_COMMITTED",
    "INITIAL_ROUTE_COMMITTED",
    "SETUP_ATTESTATION_TAPPED",
    "SETUP_ATTESTATION_COMPLETED"
  ]);
  assert.ok(attestationReview.state.log.at(-1).effects.workloads.includes("initialAttestation"));
  const laterSetupState = reduce(attestationReview.state, nextEvent(attestationReview.state));
  assert.equal(workloadInspectionReached(laterSetupState, "initialAttestation"), false);
  assert.equal(workloadInspectionReached(attestationReview.state, "initialAttestation"), true);

  for (const workloadId of ["viewfinderControls", "viewer2D", "viewer3D"]) {
    const journey = buildWorkloadInspectionJourney(workloadId);
    assert.equal(journey.plan.status, "skipped", workloadId);
    assert.equal(journey.state.workloads[workloadId], "skipped", workloadId);
    assert.notEqual(journey.state.workloads[workloadId], "succeeded", workloadId);
  }
  const viewfinderControls = buildWorkloadInspectionJourney("viewfinderControls");
  assert.equal(viewfinderControls.plan.scenarioId, "inPlaceUpdate");
  assert.equal(viewfinderControls.state.phone.page, "viewfinder");
  assert.equal(viewfinderControls.state.log.at(-1).event.type, "CAMERA_INTERACTION_READY");
  assert.ok(viewfinderControls.state.log.at(-1).effects.workloads.includes("viewfinderControls"));
  for (const workloadId of ["appAttestMaintenance", "pendingRecovery", "videoPosterBackfill", "recentLibraryCover"]) {
    const journey = buildWorkloadInspectionJourney(workloadId);
    assert.equal(journey.plan.status, "eligible", workloadId);
    assert.equal(journey.state.workloads[workloadId], "eligible", workloadId);
    assert.notEqual(journey.state.workloads[workloadId], "succeeded", workloadId);
  }
  const runningAnalysis = buildWorkloadInspectionJourney("viewerFullAnalysis");
  assert.equal(runningAnalysis.plan.status, "running");
  assert.equal(runningAnalysis.state.workloads.viewerFullAnalysis, "running");
  assert.notEqual(runningAnalysis.state.workloads.viewerFullAnalysis, "succeeded");
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
