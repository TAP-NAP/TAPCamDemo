import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";

const html = fs.readFileSync(new URL("index.html", import.meta.url), "utf8");
const script = fs.readFileSync(new URL("prototype.js", import.meta.url), "utf8");
const css = fs.readFileSync(new URL("prototype.css", import.meta.url), "utf8");
const manifest = JSON.parse(fs.readFileSync(new URL("manifest.json", import.meta.url), "utf8"));
const states = JSON.parse(fs.readFileSync(new URL("states/tap-share-local-integrity.json", import.meta.url), "utf8"));
const startupStates = JSON.parse(fs.readFileSync(new URL("states/first-install-resource-initialization.json", import.meta.url), "utf8"));
const sha256 = (relativePath) => crypto
  .createHash("sha256")
  .update(fs.readFileSync(new URL(relativePath, import.meta.url)))
  .digest("hex");

assert.equal(manifest.revision, "TAP-0081-r2-TAP-0009-r1-candidate");
assert.equal(manifest.baseRevision, "TAP-0081-r1");
assert.deepEqual(manifest.taskIds, ["TAP-0006", "TAP-0009", "TAP-0081"]);
assert.deepEqual(manifest.coveredFirstInstallStates, ["resourcePreparing", "cameraReadyCatalogPending", "catalogReadyCameraPending", "cameraAndCatalogReadyHandoff"]);
assert.equal(manifest.firstInstallInitializationBoundary.approvalStatus, "ownerApproved");
assert.equal(manifest.firstInstallInitializationBoundary.ownerApproval.ownerStatement, "原型我检查了 没有问题");
assert.match(manifest.firstInstallInitializationBoundary.trigger, /installation, reinstallation, or app update/);
assert.equal(manifest.firstInstallInitializationBoundary.retryAction, false);
assert.equal(manifest.firstInstallInitializationBoundary.degradedContinuation, false);
assert.equal(manifest.slices.firstInstallResourceInitialization.revision, "TAP-0009-r1-candidate");
assert.equal(manifest.slices.firstInstallResourceInitialization.approvalStatus, "ownerApproved");
assert.equal(manifest.slices.tapShare.ownerStatement, "已确认没有问题 请继续实施 Swift UI");
assert.equal(manifest.slices.firstInstallResourceInitialization.ownerStatement, "原型我检查了 没有问题");
assert.ok(manifest.firstInstallInitializationBoundary.neverWaitsFor.includes("iCloud originals"));
assert.ok(manifest.firstInstallInitializationBoundary.neverWaitsFor.includes("App Attest network work"));
assert.ok(manifest.firstInstallInitializationBoundary.neverWaitsFor.includes("TAP Share preparation or prewarming"));
assert.equal(startupStates.revision, "TAP-0009-r1-candidate");
assert.match(startupStates.trigger, /installation, reinstallation, or app update/);
assert.equal(startupStates.fixtures.readyHandoff.advances, true);
assert.equal(startupStates.invariantPolicy.retryAction, false);
assert.equal(startupStates.invariantPolicy.degradedContinuation, false);
assert.ok(startupStates.neverBlocksOn.includes("iCloud originals"));
assert.equal(startupStates.approvalStatus, "ownerApproved");
assert.equal(startupStates.ownerStatement, "原型我检查了 没有问题");
assert.equal(manifest.policy.progressRevealDelayMs, 50);
assert.equal(manifest.policy.minimumVisibleDurationMs, 400);
assert.equal(manifest.policy.persistentShareCache, false);
assert.equal(manifest.policy.packagePreGeneration, false);
assert.equal(manifest.policy.backendVerifyDuringShare, false);
assert.equal(manifest.policy.appAttestVerifyDuringShare, false);
assert.equal(manifest.policy.needsRetrySource, "pendingCaptureQueueOnly");
assert.equal(manifest.policy.missingExportedQueueRecordIsFailure, false);
assert.equal(manifest.approval.status, "ownerApproved");
assert.equal(manifest.approval.approvedAt, "2026-08-13");
assert.equal(manifest.approval.approvedRevision, "TAP-0081-r2-TAP-0009-r1-candidate");
assert.equal(manifest.approval.behaviorAuthority.status, "ownerApproved");
assert.equal(manifest.approval.baseRevisionApproval.revision, "TAP-0081-r1");
assert.equal(manifest.approval.sourceCommit, null);
assert.match(manifest.approval.sourceCommitNote, /sourceCommit field is synchronized immediately after/);
assert.deepEqual(manifest.coveredMedia, ["photo", "livePhoto", "video"]);
assert.deepEqual(manifest.coveredResourceStates, ["localReady", "iCloudLoading", "iCloudReady", "iCloudUnavailable", "privateQueue"]);
assert.deepEqual(manifest.coveredCredentialStates, ["verified", "retryPending", "failed"]);
assert.deepEqual(manifest.coveredIntegrityStates, ["textFreeResolvingSkeleton", "passed", "mismatch"]);
assert.equal(states.revision, manifest.baseRevision.replace("r1", "r2-candidate"));
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

for (const id of ["share-button", "delete-button", "share-popover", "share-options", "progress-bar", "cancel-button", "retry-button", "return-button", "resource-overlay", "resource-progress", "resolve-integrity-button", "startup-initialization", "startup-entry-boundary", "startup-title", "startup-subtitle", "startup-announcement", "startup-camera-check", "startup-library-check"]) {
  assert.match(html, new RegExp(`id="${id}"`));
}

for (const state of ["integrityChecking", "selector", "preparing", "failure", "boundary"]) {
  assert.match(html, new RegExp(`data-panel="${state}"`));
}

assert.match(script, /revealDelayMs:\s*50/);
assert.match(script, /minimumVisibleMs:\s*400/);
assert.match(script, /threshold:\s*120/);
assert.match(script, /Math\.max\(state\.progress/);
assert.match(script, /state\.fixture === "fast"/);
assert.match(script, /showPanel\("boundary"\)/);
assert.match(script, /readyResources = new Set\(\["localReady", "iCloudReady", "privateQueue"\]\)/);
assert.match(script, /retryButton\.disabled = !queueOnly/);
assert.match(script, /showPanel\("integrityChecking"\)/);
assert.match(script, /本地完整性检查未通过/);
assert.match(script, /无法保证可验证性/);
assert.match(script, /renderStartupState/);
assert.match(script, /ordinary repeated launches skip it/);
assert.match(script, /资源初始化/);
assert.match(script, /首个媒体目录已建立/);
assert.match(script, /shareFlowScreen\.hidden = isStartup/);
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
