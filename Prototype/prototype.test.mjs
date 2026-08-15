import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";

const html = fs.readFileSync(new URL("index.html", import.meta.url), "utf8");
const script = fs.readFileSync(new URL("prototype.js", import.meta.url), "utf8");
const css = fs.readFileSync(new URL("prototype.css", import.meta.url), "utf8");
const manifest = JSON.parse(fs.readFileSync(new URL("manifest.json", import.meta.url), "utf8"));
const states = JSON.parse(fs.readFileSync(new URL("states/tap-share-local-integrity.json", import.meta.url), "utf8"));
const setupStates = JSON.parse(fs.readFileSync(new URL("states/first-install-setup.json", import.meta.url), "utf8"));
const startupStates = JSON.parse(fs.readFileSync(new URL("states/first-install-resource-initialization.json", import.meta.url), "utf8"));
const sha256 = (relativePath) => crypto
  .createHash("sha256")
  .update(fs.readFileSync(new URL(relativePath, import.meta.url)))
  .digest("hex");

assert.equal(manifest.revision, "TAP-0008-r2-TAP-0009-r1-TAP-0081-r3-candidate");
assert.equal(manifest.baseRevision, "TAP-0081-r1");
assert.deepEqual(manifest.taskIds, ["TAP-0006", "TAP-0008", "TAP-0009", "TAP-0081"]);
assert.deepEqual(manifest.coveredFirstInstallStates, [
  "setupUntouched",
  "explicitCameraRequest",
  "networkFailed",
  "requiredSetupReady",
  "resourcePreparing",
  "cameraReadyCatalogPending",
  "catalogReadyCameraPending",
  "cameraAndCatalogReadyHandoff",
]);
assert.equal(manifest.slices.firstInstallSetup.revision, "TAP-0008-r2-candidate");
assert.equal(manifest.slices.firstInstallSetup.approvalStatus, "ownerApproved");
assert.equal(manifest.slices.firstInstallSetup.ownerStatement, "现在原型已经确认没有问题");
assert.deepEqual(manifest.firstInstallSetupBoundary.continueRequires, ["network preflight", "camera authorization", "photo-library authorization"]);
assert.deepEqual(manifest.firstInstallSetupBoundary.optionalRowsDoNotBlockContinue, ["location", "microphone"]);
assert.equal(setupStates.revision, "TAP-0008-r2-candidate");
assert.equal(setupStates.approvalStatus, "ownerApproved");
assert.equal(setupStates.ownerApproval.ownerStatement, "现在原型已经确认没有问题");
assert.match(setupStates.transition.continueCondition, /location and microphone do not block Continue/);
assert.match(setupStates.systemOwnedBoundary, /never imitates/);
assert.equal(sha256(manifest.firstInstallBrandAsset.path), manifest.firstInstallBrandAsset.sha256);
for (const symbol of Object.values(manifest.firstInstallSetupSymbolSpec.symbols)) {
  assert.equal(sha256(symbol.path), symbol.sha256);
}
assert.equal(manifest.firstInstallInitializationBoundary.approvalStatus, "ownerApproved");
assert.equal(manifest.firstInstallInitializationBoundary.ownerApproval.ownerStatement, "原型我检查了 没有问题");
assert.match(manifest.firstInstallInitializationBoundary.trigger, /installation or reinstallation/);
assert.match(manifest.firstInstallInitializationBoundary.trigger, /initialization-schema change/);
assert.equal(manifest.firstInstallInitializationBoundary.completionMarker.separateFromSetupAndPermissions, true);
assert.deepEqual(manifest.firstInstallInitializationBoundary.completionMarker.identity, ["current installed app update", "initialization-schema generation"]);
assert.match(manifest.firstInstallInitializationBoundary.completionMarker.write, /atomic/);
assert.equal(manifest.firstInstallInitializationBoundary.retryAction, false);
assert.equal(manifest.firstInstallInitializationBoundary.degradedContinuation, false);
assert.equal(manifest.slices.firstInstallResourceInitialization.revision, "TAP-0009-r1-candidate");
assert.equal(manifest.slices.firstInstallResourceInitialization.approvalStatus, "ownerApproved");
assert.equal(manifest.slices.tapShare.revision, "TAP-0081-r3-candidate");
assert.equal(manifest.slices.tapShare.approvalStatus, "ownerApproved");
assert.equal(manifest.slices.tapShare.ownerStatement, "对的 现在原型是我想要的");
assert.equal(manifest.slices.tapShare.supersedesApprovedRevision, "TAP-0081-r2-candidate");
assert.equal(manifest.slices.firstInstallResourceInitialization.ownerStatement, "原型我检查了 没有问题");
assert.ok(manifest.firstInstallInitializationBoundary.neverWaitsFor.includes("iCloud originals"));
assert.ok(manifest.firstInstallInitializationBoundary.neverWaitsFor.includes("App Attest network work"));
assert.ok(manifest.firstInstallInitializationBoundary.neverWaitsFor.includes("TAP Share preparation or prewarming"));
assert.equal(startupStates.revision, "TAP-0009-r1-candidate");
assert.match(startupStates.trigger, /installation or reinstallation/);
assert.match(startupStates.trigger, /initialization-schema change/);
assert.equal(startupStates.completionMarker.separateFromSetupAndPermissions, true);
assert.match(startupStates.completionMarker.write, /atomic/);
assert.equal(startupStates.fixtures.readyHandoff.advances, true);
assert.equal(startupStates.invariantPolicy.retryAction, false);
assert.equal(startupStates.invariantPolicy.degradedContinuation, false);
assert.ok(startupStates.neverBlocksOn.includes("iCloud originals"));
assert.equal(startupStates.approvalStatus, "ownerApproved");
assert.equal(startupStates.ownerStatement, "原型我检查了 没有问题");
assert.equal(manifest.policy.preparationProgressPresentation, "immediateAfterImplementedOptionSelection");
assert.equal(manifest.policy.preparationProgressPlacement, "replacesSubtitleTextWithinSameSlot");
assert.equal(manifest.policy.nonSelectedOptionBehaviorDuringPreparation, "visibleDisabled");
assert.equal(manifest.policy.preparationProgressPercentageVisible, false);
assert.equal(manifest.policy.preparationCancelVisible, false);
assert.equal(manifest.policy.preparationGeometryMutation, false);
assert.equal(manifest.policy.artificialProgressRevealDelay, false);
assert.equal(manifest.policy.minimumProgressHold, false);
assert.equal(manifest.policy.payloadReadyBehavior, "endAppOwnedPopover");
assert.equal(manifest.policy.systemActivitySimulation, false);
assert.equal(manifest.policy.persistentShareCache, false);
assert.equal(manifest.policy.packagePreGeneration, false);
assert.equal(manifest.policy.backendVerifyDuringShare, false);
assert.equal(manifest.policy.appAttestVerifyDuringShare, false);
assert.equal(manifest.policy.needsRetrySource, "pendingCaptureQueueOnly");
assert.equal(manifest.policy.missingExportedQueueRecordIsFailure, false);
assert.equal(manifest.prototypeGeometryValidation.tapnapPackageBeforeEqualsPreparing, true);
assert.equal(manifest.prototypeGeometryValidation.shareImageBeforeEqualsPreparing, true);
assert.equal(manifest.prototypeGeometryValidation.percentageTextPresent, false);
assert.equal(manifest.prototypeGeometryValidation.cancelControlPresent, false);
assert.equal(manifest.approval.status, "composedFromIndependentlyOwnerApprovedSlices");
assert.equal(manifest.approval.compositionRecordedAt, "2026-08-14");
assert.equal(manifest.approval.composedRevision, "TAP-0008-r2-TAP-0009-r1-TAP-0081-r3-candidate");
assert.equal(manifest.approval.wholeCompositionApproval, "not separately claimed");
assert.match(manifest.approval.composition, /independently recorded owner approval/);
assert.equal(manifest.approval.firstInstallSetupApproval.revision, "TAP-0008-r2-candidate");
assert.equal(manifest.approval.candidateDirection.status, "ownerApproved");
assert.equal(manifest.approval.behaviorAuthority.status, "ownerApproved");
assert.equal(manifest.approval.baseRevisionApproval.revision, "TAP-0081-r1");
assert.equal(manifest.approval.sourceCommit, null);
assert.match(manifest.approval.sourceCommitNote, /attended device acceptance/);
assert.equal(manifest.approval.inheritedFoundationCommit, "70e8b60d4e20486a6d4847d726b393a50e22c7ba");
const startupLifecycleCandidate = manifest.independentCandidates.startupLifecycle;
assert.equal(startupLifecycleCandidate.status, "ownerReviewRequired");
assert.equal(startupLifecycleCandidate.qaRefresh.verificationRevision, "v17");
assert.deepEqual(startupLifecycleCandidate.qaEvidence, [
  "design-qa.md",
  "evidence/TAP-0087-r1-v17-fix0809-outcome-cards.png",
  "evidence/TAP-0087-r1-v17-fix0809-outcome-workload.png",
]);
assert.ok(startupLifecycleCandidate.staleQaEvidence.includes("evidence/TAP-0087-r1-v16b-fix0809-dispositions.png"));
assert.ok(startupLifecycleCandidate.staleQaEvidence.includes("evidence/TAP-0087-r1-v16b-fix0809-timing-workload.png"));
assert.equal(startupLifecycleCandidate.qaRefresh.v17Fix0809OutcomeOverlay.resourceInitializationSeq10.lifecycleCards, 6);
assert.equal(startupLifecycleCandidate.qaRefresh.v17Fix0809OutcomeOverlay.resourceInitializationSeq10.workloadActualAnnotations, 9);
assert.equal(startupLifecycleCandidate.qaRefresh.v17Fix0809OutcomeOverlay.resourceInitializationSeq10.existingBlueTargets, 5);
assert.match(startupLifecycleCandidate.qaRefresh.closureRequires[0], /exact v17 composition/);
for (const relativePath of startupLifecycleCandidate.qaRefresh.browserEnvironment.screenshotFiles) {
  const bytes = fs.readFileSync(new URL(relativePath, import.meta.url));
  assert.deepEqual([...bytes.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
}
assert.deepEqual(manifest.coveredMedia, ["photo", "livePhoto", "video"]);
assert.deepEqual(manifest.coveredResourceStates, ["localReady", "iCloudLoading", "iCloudReady", "iCloudUnavailable", "privateQueue"]);
assert.deepEqual(manifest.coveredCredentialStates, ["verified", "retryPending", "failed"]);
assert.deepEqual(manifest.coveredIntegrityStates, ["textFreeResolvingSkeleton", "passed", "mismatch"]);
assert.equal(states.revision, manifest.slices.tapShare.revision);
assert.equal(states.resourceStates.iCloudLoading.shareEnabled, false);
assert.equal(states.resourceStates.iCloudLoading.viewerLoadingVisible, true);
assert.equal(states.resourceStates.iCloudReady.shareEnabled, true);
assert.equal(states.credentialStates.retryPending.source, "pendingCaptureQueueOnly");
assert.equal(states.credentialStates.failed.tapnapEnabled, false);
assert.equal(states.credentialStates.failed.ordinaryMediaEnabled, true);
assert.equal(states.credentialStates.failed.ordinaryMediaWarning, "无法保证可验证性");
assert.equal(states.integrityStates.checking.publicCredentialLabel, null);
assert.equal(states.trustBoundary.backendVerifyAllowed, false);
assert.equal(states.trustBoundary.appAttestVerifyAllowed, false);
assert.equal(states.preparationPolicy.progressVisibleImmediatelyAfterSelection, true);
assert.equal(states.preparationPolicy.progressPlacement, "replacesSubtitleTextWithinSameSlot");
assert.equal(states.preparationPolicy.nonSelectedOptionsDuringPreparation, "visibleDisabled");
assert.equal(states.preparationPolicy.independentPreparationPanelAllowed, false);
assert.equal(states.preparationPolicy.percentageVisible, false);
assert.equal(states.preparationPolicy.cancelVisible, false);
assert.equal(states.preparationPolicy.selectedSubtitleTextReplacedDuringPreparation, true);
assert.equal(states.preparationPolicy.selectedTitleIconBadgeMutationAllowed, false);
assert.equal(states.preparationPolicy.selectedRowGeometryMutationAllowed, false);
assert.equal(states.preparationPolicy.popoverGeometryMutationAllowed, false);
assert.equal(states.preparationPolicy.artificialRevealDelayAllowed, false);
assert.equal(states.preparationPolicy.minimumVisibleHoldAllowed, false);
assert.equal(states.preparationPolicy.payloadReadyEndsAppPopover, true);
assert.equal(states.preparationPolicy.systemActivityControllerSimulated, false);

const toolbar = manifest.viewerToolbarVisualSpec;
assert.equal(toolbar.toolbar.sideInsetPx, 16);
assert.equal(toolbar.toolbar.bottomInsetPx, 25);
assert.equal(toolbar.toolbar.modeCapsuleWidthPx, 140);
assert.equal(toolbar.roundControl.diameterPx, 42);
assert.equal(toolbar.roundControl.backReferenceDiameterPx, 42);
assert.equal(toolbar.roundControl.iconBoxPx, 20);
assert.deepEqual(toolbar.roundControl.iconBoxCenterOffsetPx, { x: 0, y: 0 });
assert.equal(toolbar.share.iconIdentity, "share-network");
assert.equal(toolbar.share.assetSha256, "e6923db3591f797c89c36671aad3e20effd7b06e6eb400b2a7ffb6daaed0474a");
assert.equal(sha256(toolbar.share.assetPath), toolbar.share.assetSha256);
assert.deepEqual(toolbar.share.cssOpticalTranslationPx, { x: 0, y: 0 });
assert.deepEqual(toolbar.share.intrinsicArtworkCenterOffsetAt20Px, { x: -0.625, y: 0 });
assert.equal(toolbar.delete.iconIdentity, "trash");
assert.equal(toolbar.delete.assetSha256, "e6a830c0409f9e101e3695c981eef98427d39fd01f502b9cbd6900930b01f19c");
assert.equal(sha256(toolbar.delete.assetPath), toolbar.delete.assetSha256);
assert.deepEqual(toolbar.delete.cssOpticalTranslationPx, { x: 0, y: 0 });
assert.deepEqual(toolbar.delete.intrinsicArtworkCenterOffsetAt20Px, { x: 0, y: -0.625 });

for (const id of ["share-button", "delete-button", "share-popover", "share-options", "retry-button", "resource-overlay", "resource-progress", "resolve-integrity-button", "first-install-setup", "setup-continue", "setup-guidance", "setup-announcement", "system-boundary-note", "startup-initialization", "startup-entry-boundary", "startup-title", "startup-subtitle", "startup-announcement", "startup-camera-check", "startup-library-check"]) {
  assert.match(html, new RegExp(`id="${id}"`));
}

for (const state of ["integrityChecking", "selector", "failure"]) {
  assert.match(html, new RegExp(`data-panel="${state}"`));
}

assert.match(html, /细进度条在完全相同的副标题槽内替换原文字；标题、图标、推荐标记和全部布局不动/);
assert.match(html, /iOS 系统分享面板只作为文案边界，本原型不伪造/);
assert.match(html, /在使用之前请先容许我们使用必要的权限/);
assert.match(html, /位置访问\(可选\)/);
assert.match(html, /麦克风访问\(可选\)/);
for (const asset of ["setup-wifi.png", "setup-camera.png", "setup-photos.png", "setup-location.png", "setup-microphone.png"]) {
  assert.match(html, new RegExp(asset.replace(".", "\\.")));
}
assert.doesNotMatch(html, /id="return-button"|data-panel="boundary"|data-panel="preparing"|资料已准备完成|模拟系统页关闭/);
assert.match(script, /progressPresentation:\s*"immediate"/);
assert.match(script, /minimumVisibleHold:\s*false/);
assert.match(script, /payloadReadyBehavior:\s*"closeAppPopover"/);
assert.match(script, /systemActivitySimulation:\s*false/);
assert.match(script, /fixtureDurations = Object\.freeze\(\{ success: 1400, failure: 720 \}\)/);
assert.match(script, /Math\.max\(state\.progress/);
assert.match(script, /const visiblePanel = name === "preparing" \? "selector" : name/);
assert.match(script, /const preparing = state\.panel === "preparing"/);
assert.match(script, /button\.disabled = preparing \|\| Boolean\(option\.disabled\)/);
assert.match(script, /row\.className = `share-option-row\$\{selected \? " is-preparing" : ""\}`/);
assert.match(script, /const subtitleContent = selected[\s\S]*id="progress-bar" class="subtitle-progress-track"[\s\S]*: option\.subtitle/);
assert.match(script, /<small>\$\{subtitleContent\}<\/small>/);
assert.doesNotMatch(script, /id="progress-label"|id="cancel-button"/);
assert.match(script, /function prepare\(option\)[\s\S]*showPanel\("preparing"\);\s*renderSelector\(\{ preservePanel: true \}\);\s*setProgress\(0\);[\s\S]*const duration = fixtureDurations\[state\.fixture\]/);
assert.match(script, /function complete\(attempt\)[\s\S]*setProgress\(1\);[\s\S]*state\.systemActivityBoundaryReached = true;\s*showPanel\("closed"\);/);
assert.doesNotMatch(script, /revealDelayMs|minimumVisibleMs|progressVisibleAt|showPanel\("boundary"\)|return-button/);
assert.match(css, /\.share-option-row\.is-preparing \.share-option\[disabled\] \{ opacity: 1; \}/);
assert.match(css, /\.share-option small \{ position: relative; display: block; height: 14px;[\s\S]*line-height: 14px; \}/);
assert.match(css, /\.subtitle-progress-track \{ position: absolute; left: 0; right: 0; top: 50%;[\s\S]*height: 2px;[\s\S]*pointer-events: none; \}/);
assert.match(script, /readyResources = new Set\(\["localReady", "iCloudReady", "privateQueue"\]\)/);
assert.match(script, /retryButton\.disabled = !queueOnly/);
assert.match(script, /showPanel\("integrityChecking"\)/);
assert.match(script, /本地完整性检查未通过/);
assert.match(script, /无法保证可验证性/);
assert.match(script, /renderStartupState/);
assert.match(script, /function setupRequiredReady\(\)[\s\S]*\["network", "camera", "photos"\]/);
assert.match(script, /shareFlowScreen\.hidden = isSetup \|\| isStartup/);
assert.match(script, /state\.flow = "startup";[\s\S]*renderFlow\(\);/);
assert.match(script, /setupStatuses\[key\] = "requesting"/);
assert.match(script, /state\.setupStatuses\[key\] = "skipped"/);
assert.match(script, /ordinary repeated launches skip it/);
assert.match(script, /资源初始化/);
assert.match(script, /首个媒体目录已建立/);
assert.match(script, /catalogReadyCameraPending/);
assert.match(script, /startupEntryBoundary\.hidden = false/);
assert.doesNotMatch(script, /startupRetry|cameraFailed|catalogTimedOut/);
assert.doesNotMatch(script, /fetch\s*\(/);
assert.doesNotMatch(script, /XMLHttpRequest|WebSocket|\/tapcam\/capture-signatures\/verify/);
assert.doesNotMatch(script, /localStorage|sessionStorage|indexedDB/);
for (const token of [
  "--viewer-toolbar-side-inset: 16px",
  "--viewer-toolbar-bottom-inset: 25px",
  "--viewer-toolbar-control-diameter: 42px",
  "--viewer-toolbar-icon-box: 20px",
  "--viewer-toolbar-mode-width: 140px"
]) {
  assert.match(css, new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
}
assert.match(css, /place-items:\s*center/);
assert.match(css, /grid-template-columns:\s*var\(--viewer-toolbar-control-diameter\) var\(--viewer-toolbar-mode-width\) var\(--viewer-toolbar-control-diameter\)/);
assert.match(css, /justify-content:\s*space-between/);
assert.match(css, /\.share-button, \.delete-button \{ --icon-box-offset-x: 0px; --icon-box-offset-y: 0px; \}/);

console.log(`${manifest.revision} static contract tests passed`);
