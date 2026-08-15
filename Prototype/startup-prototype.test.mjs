import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import test from "node:test";

const read = (path) => fs.readFileSync(new URL(path, import.meta.url), "utf8");
const sha256 = (path) => crypto
  .createHash("sha256")
  .update(fs.readFileSync(new URL(path, import.meta.url)))
  .digest("hex");

const html = read("startup-lifecycle.html");
const css = read("startup-lifecycle.css");
const controller = read("startup-prototype.mjs");
const model = read("startup-model.mjs");
const shareModule = read("tap-share-slice.mjs");
const manifest = JSON.parse(read("manifest.json"));
const candidate = manifest.independentCandidates.startupLifecycle;

const sourceBetween = (source, start, end) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(startIndex, -1, `missing source boundary: ${start}`);
  assert.notEqual(endIndex, -1, `missing source boundary: ${end}`);
  return source.slice(startIndex, endIndex);
};

test("TAP-0087 has a separate candidate entry and does not rewrite prior approvals", () => {
  assert.equal(candidate.revision, "TAP-0087-r1-candidate");
  assert.equal(candidate.entry, "startup-lifecycle.html");
  assert.equal(candidate.status, "ownerReviewRequired");
  assert.deepEqual(candidate.prerequisiteFor, ["TAP-0008", "TAP-0009", "TAP-0083"]);
  assert.equal(manifest.slices.firstInstallSetup.approvalStatus, "ownerApproved");
  assert.equal(manifest.slices.firstInstallResourceInitialization.approvalStatus, "ownerApproved");
  assert.equal(manifest.approval.wholeCompositionApproval, "not separately claimed");
  assert.deepEqual(
    candidate.qaRefresh.notClaimed.includes("owner approval of the complete TAP-0087 v17 composition"),
    true
  );
});

test("the dedicated lifecycle page contains every requested surface and the reviewer inspector", () => {
  for (const page of [
    "dormant",
    "systemLaunchScreen",
    "firstAppFrame",
    "firstInstallSetup",
    "requiredPermissionCheck",
    "resourceInitialization",
    "viewfinder",
    "library",
    "photoViewer"
  ]) {
    assert.match(html, new RegExp(`data-phone-page="${page}"`));
  }
  for (const id of [
    "timeline",
    "journey-spans",
    "machine-list",
    "workload-list",
    "event-log",
    "route-facts",
    "debugger-toggle",
    "focused-event-label",
    "edge-effect-list",
    "marker-effect-list",
    "marker-snapshot"
  ]) {
    assert.match(html, new RegExp(`id="${id}"`));
  }
  assert.match(controller, /iOS system-owned reference/);
  assert.match(html, /393 × 852 review viewport/);
});

test("TAP-0008/TAP-0009 code truth uses JSON outcome cards with one dashed connector per visible mismatch", () => {
  assert.match(html, /id="lifecycle-difference-connectors"[^>]*aria-hidden="true"/);
  assert.match(html, /data-workload-filter="truth" aria-pressed="true">08 \/ 09 真值/);
  assert.match(html, /黄色=本轮已改（黄边：log 已验收；红边：log 未覆盖）· 红底红边=冻结未处理 · 绿色=原本一致/);
  assert.match(html, /生命周期卡 → 虚线 → 红色实际阶段圆点 · Workload 实际 → 虚线 → 蓝色原型/);
  assert.match(controller, /lifecycleTruthRegistry/);
  assert.match(controller, /label\.dataset\.lifecycleAnchorId = item\.id/);
  assert.match(controller, /card\.classList\.toggle\("is-lifecycle-mismatch", truth\.mismatch\)/);
  assert.match(controller, /\.filter\(\(truth\) => !truth\.mismatch \|\| lifecycleTimingLaneRecordIDSet\.has\(truth\.id\)\)/);
  assert.match(controller, /if \(truth\.mismatch\) \{[\s\S]*card\.dataset\.lifecycleDifferenceId = truth\.id/);
  assert.match(controller, /card\.dataset\.fix0809Disposition = truth\.fix0809Disposition/);
  assert.match(controller, /card\.dataset\.fix0809Outcome = truth\.fix0809Outcome/);
  assert.match(controller, /makeFix0809OutcomeBadge\(truth\)/);
  assert.match(controller, /path\.dataset\.connectorId = card\.dataset\.lifecycleDifferenceId/);
  assert.match(controller, /path\.dataset\.targetAnchorId = card\.dataset\.lifecycleActualAnchor/);
  assert.match(controller, /visibleBottom <= visibleTop/);
  assert.match(controller, /addEventListener\("scroll", scheduleLifecycleDifferenceConnectors/);
  assert.match(controller, /addEventListener\("resize", scheduleLifecycleDifferenceConnectors/);
  assert.match(controller, /new ResizeObserver\(scheduleLifecycleDifferenceConnectors\)/);
  assert.match(css, /\.lifecycle-truth-card\.is-lifecycle-mismatch[\s\S]*background: linear-gradient/);
  assert.match(css, /\.fix0809-outcome\[data-fix0809-outcome="deferredFrozen"\]/);
  assert.match(css, /\.lifecycle-truth-card\.is-lifecycle-mismatch\[data-fix0809-outcome="implementedLogAccepted"\]/);
  assert.match(css, /\.lifecycle-truth-card\.is-lifecycle-mismatch\[data-fix0809-outcome="implementedNotLogVerified"\]/);
  assert.match(css, /\.lifecycle-truth-card\.is-lifecycle-mismatch\[data-fix0809-outcome="deferredFrozen"\]/);
  const acceptedOutcomeCSS = sourceBetween(
    css,
    '.lifecycle-truth-card.is-lifecycle-mismatch[data-fix0809-outcome="implementedLogAccepted"]',
    '.lifecycle-truth-card.is-lifecycle-mismatch[data-fix0809-outcome="implementedNotLogVerified"]'
  );
  const unverifiedOutcomeCSS = sourceBetween(
    css,
    '.lifecycle-truth-card.is-lifecycle-mismatch[data-fix0809-outcome="implementedNotLogVerified"]',
    '.lifecycle-truth-card.is-lifecycle-mismatch[data-fix0809-outcome="deferredFrozen"]'
  );
  const frozenOutcomeCSS = sourceBetween(
    css,
    '.lifecycle-truth-card.is-lifecycle-mismatch[data-fix0809-outcome="deferredFrozen"]',
    '.lifecycle-truth-card.is-lifecycle-aligned'
  );
  assert.match(acceptedOutcomeCSS, /background: linear-gradient/);
  assert.match(acceptedOutcomeCSS, /border-color: rgba\(255,214,10,\.9\)/);
  assert.match(acceptedOutcomeCSS, /\.timing-lifecycle-difference\[data-fix0809-outcome="implementedLogAccepted"\]/);
  assert.match(acceptedOutcomeCSS, /\.timing-workload-actual\[data-fix0809-outcome="implementedLogAccepted"\]/);
  assert.match(unverifiedOutcomeCSS, /background: linear-gradient/);
  assert.match(unverifiedOutcomeCSS, /border-color: rgba\(255,69,58,\.9\)/);
  assert.match(frozenOutcomeCSS, /rgba\(126,29,33,\.9\)/);
  assert.match(frozenOutcomeCSS, /border-color: rgba\(255,69,58,\.82\)/);
  assert.match(css, /\.lifecycle-difference-connector[\s\S]*stroke-dasharray: 5 5/);
  assert.match(css, /\.lifecycle-difference-connector[\s\S]*stroke: rgba\(255, 69, 58, \.92\)/);
  assert.match(css, /\.timeline li \.timeline-anchor[\s\S]*border-radius: 50%/);
  assert.match(css, /html\[data-workload-filter="truth"\] \.timeline[\s\S]*grid-template-columns: 1fr/);
  assert.equal(candidate.workbench.revision, "v17");
  assert.equal(candidate.workbench.right.tap0008Tap0009CodeTruth.recordCount, 14);
  assert.equal(candidate.workbench.right.tap0008Tap0009CodeTruth.mismatchCount, 12);
  for (const evidencePath of candidate.qaEvidence.filter((path) => path.endsWith(".png"))) {
    assert.ok(fs.existsSync(new URL(evidencePath, import.meta.url)), evidencePath);
  }
});

test("Timing keeps only non-workload truth in the lifecycle lane and links it to actual anchors", () => {
  assert.match(controller, /makeTimingLane\("08\/09 生命周期", "difference"/);
  assert.match(controller, /lifecycleTimingLaneRecordIDSet\.has\(truth\.id\)/);
  assert.match(controller, /reached\.has\(truth\.actual\.anchor\)/);
  assert.match(controller, /card\.dataset\.timingDifferenceId = truth\.id/);
  assert.match(controller, /card\.dataset\.fix0809Outcome = truth\.fix0809Outcome/);
  assert.match(controller, /anchor\.dataset\.timingLifecycleAnchorId = milestoneID/);
  assert.match(controller, /path\.dataset\.timingConnectorId = card\.dataset\.timingDifferenceId/);
  assert.match(controller, /path\.dataset\.targetAnchorId = anchorID/);
  assert.match(controller, /svg\.dataset\.connectorCount = String\(svg\.childElementCount\)/);
  assert.match(controller, /if \(!grid \|\| !svg \|\| timingView\.hidden\) return/);
  assert.match(css, /\.timing-milestone-anchor[\s\S]*border-radius: 50%/);
  assert.match(css, /\.timing-milestone-anchor\.has-lifecycle-difference[\s\S]*background: #721f22[\s\S]*border-color: var\(--red\)/);
  assert.match(css, /\.timing-lifecycle-difference[\s\S]*background: linear-gradient/);
  assert.match(css, /\.timing-difference-connector[\s\S]*stroke-dasharray: 4 4/);
  assert.match(css, /\.timing-difference-connectors[\s\S]*pointer-events: none/);
});

test("Timing decorates the existing Workload trace with scenario-bound JSON outcome differences", () => {
  const comparisonManifest = candidate.workbench.right.tap0008Tap0009CodeTruth.workloadDifferenceComparison;
  const truthManifest = candidate.workbench.right.tap0008Tap0009CodeTruth;
  assert.equal(truthManifest.schemaVersion, 3);
  assert.equal(comparisonManifest.schemaVersion, 4);
  assert.equal(comparisonManifest.recordCount, 13);
  assert.equal(comparisonManifest.recordCount, comparisonManifest.records.length);
  assert.equal(comparisonManifest.mismatchCount, comparisonManifest.records.filter(({ mismatch }) => mismatch).length);
  assert.equal(comparisonManifest.timingMismatchCount, 10);
  assert.equal(comparisonManifest.semanticMismatchCount, 3);
  assert.equal(truthManifest.fix0809DispositionSummary.approvedToFixMismatchCount, 11);
  assert.equal(truthManifest.fix0809DispositionSummary.deferredFrozenMismatchCount, 1);
  assert.equal(truthManifest.records.find(({ id }) => id === "networkBootstrap").fix0809Disposition, "deferredFrozen");
  assert.deepEqual(
    comparisonManifest.records
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
  assert.equal(comparisonManifest.fix0809DispositionSummary.approvedToFixMismatchCount, 9);
  assert.equal(comparisonManifest.fix0809DispositionSummary.deferredFrozenMismatchCount, 4);
  assert.equal(truthManifest.fix0809OutcomeSummary.implementedLogAcceptedMismatchCount, 3);
  assert.equal(truthManifest.fix0809OutcomeSummary.implementedNotLogVerifiedMismatchCount, 8);
  assert.equal(truthManifest.fix0809OutcomeSummary.deferredFrozenMismatchCount, 1);
  assert.equal(comparisonManifest.fix0809OutcomeSummary.implementedLogAcceptedMismatchCount, 5);
  assert.equal(comparisonManifest.fix0809OutcomeSummary.implementedNotLogVerifiedMismatchCount, 4);
  assert.equal(comparisonManifest.fix0809OutcomeSummary.deferredFrozenMismatchCount, 4);
  const targetBindingKeys = new Set();
  for (const difference of comparisonManifest.records) {
    const binding = difference.traceBinding;
    const scenarioIDs = comparisonManifest.scenarioGroups[binding.scenarioGroupID];
    assert.ok(Array.isArray(scenarioIDs) && scenarioIDs.length > 0, `${difference.id} scenario binding`);
    assert.ok(binding.actualVisibleAfter.eventTypes.length > 0, `${difference.id} visibility binding`);
    assert.ok(binding.targetEffect.eventTypes.length > 0, `${difference.id} target event binding`);
    assert.equal(binding.targetEffect.workloadID, difference.target.workloadID, `${difference.id} target workload`);
    assert.ok(Number.isInteger(binding.actualVisibleAfter.occurrence) && binding.actualVisibleAfter.occurrence > 0);
    assert.ok(Number.isInteger(binding.targetEffect.occurrence) && binding.targetEffect.occurrence > 0);
    for (const scenarioID of scenarioIDs) {
      const targetKey = [
        scenarioID,
        [...binding.targetEffect.eventTypes].sort().join(","),
        binding.targetEffect.workloadID,
        binding.targetEffect.status,
        binding.targetEffect.occurrence
      ].join("|");
      assert.equal(targetBindingKeys.has(targetKey), false, `${difference.id} one-to-one target binding`);
      targetBindingKeys.add(targetKey);
    }
  }
  assert.match(model, /loadPrototypeManifest\(\)/);
  assert.match(model, /workloadDifferenceRegistry = Object\.freeze\(clone\(workloadDifferenceManifest\.records\)\)/);
  assert.match(model, /fix0809DispositionRegistry = Object\.freeze\(clone\(fix0809DispositionCatalog\)\)/);
  assert.match(model, /fix0809OutcomeRegistry = Object\.freeze\(clone\(fix0809OutcomeCatalog\)\)/);
  assert.match(model, /workloadDifferenceScenarioRegistry = Object\.freeze/);
  assert.match(model, /export function resolveWorkloadDifferenceTraceBinding/);
  assert.match(model, /lifecycleTimingLaneRecordIDs = Object\.freeze/);
  assert.doesNotMatch(model, /id:\s*"libraryObserverStartsPreFrame"/);

  const projectionSource = sourceBetween(
    controller,
    "function buildTimingWorkloadDifferenceProjection(",
    "function makeTimingWorkloadActual("
  );
  assert.match(projectionSource, /resolveWorkloadDifferenceTraceBinding\(difference, state\.scenarioId, columns\)/);
  assert.match(projectionSource, /if \(!resolved\.visible\) continue/);
  assert.match(projectionSource, /actualBySequence\.get\(visibilityColumn\.entry\.seq\)/);
  assert.match(projectionSource, /targetByEffect\.set/);
  assert.doesNotMatch(projectionSource, /scope\.(?:path|trigger)|actual\.anchor ===|target\.anchor ===/);

  const workloadLaneSource = sourceBetween(
    controller,
    'grid.append(makeTimingLane("Workload", "workload"',
    'grid.append(makeTimingLane("Marker", "marker"'
  );
  assert.match(workloadLaneSource, /const traceWorkloadIds = entry\.effects\.workloads \|\| \[\]/);
  assert.match(workloadLaneSource, /\.\.\.traceWorkloadIds\.map\(\(workloadId, effectIndex\) => makeTimingWorkloadTraceEffect/);
  assert.match(workloadLaneSource, /workloadDifferenceProjection\.targetByEffect\.get\(timingWorkloadEffectKey/);
  assert.match(workloadLaneSource, /\.\.\.differences\.map\(makeTimingWorkloadActual\)/);
  assert.doesNotMatch(workloadLaneSource, /traceWorkloadIds[\s\S]*?\.filter\(/);
  assert.doesNotMatch(workloadLaneSource, /\breduce\(|\bdispatch\(|\breach\(|\bwork\(/);

  assert.equal((controller.match(/makeTimingLane\("Workload", "workload"/g) || []).length, 1);
  assert.doesNotMatch(controller, /renderWorkloadTimingComparison|workload-timing-comparison|workloadTimingConnectorFrame/);
  assert.match(controller, /actual\.dataset\.workloadDifferenceActualId = difference\.id/);
  assert.match(controller, /actual\.dataset\.scenarioGroupId = difference\.traceBinding\.scenarioGroupID/);
  assert.match(controller, /actual\.dataset\.actualAnchorReached = String\(actualColumn != null\)/);
  assert.match(controller, /actual\.dataset\.actualAnchorSeq = actualColumn \? String\(actualColumn\.entry\.seq\) : ""/);
  assert.match(controller, /actual\.dataset\.focusSeq = String\(visibilityColumn\.entry\.seq\)/);
  assert.match(controller, /actual\.dataset\.targetElementId = timingWorkloadEffectDOMID/);
  assert.match(controller, /actual\.dataset\.targetEffectReached = String\(targetEffectReached\)/);
  assert.match(controller, /actual\.dataset\.targetAnchorReached = String\(targetAnchorReached\)/);
  assert.match(controller, /actual\.dataset\.fix0809Disposition = difference\.fix0809Disposition/);
  assert.match(controller, /actual\.dataset\.fix0809Outcome = difference\.fix0809Outcome/);
  assert.match(controller, /makeFix0809OutcomeBadge\(difference\)/);
  assert.match(controller, /targetStatus\.textContent = `对应原型 Workload · \$\{difference\.target\.label\} · 既有 trace effect \$\{targetEffectReached \? "已出现" : "尚未出现"\}`/);
  const actualAnnotationSource = sourceBetween(
    controller,
    "function makeTimingWorkloadActual(",
    "function makeTimingWorkloadTraceEffect("
  );
  assert.match(actualAnnotationSource, /差异：\$\{kindLabel\}；检查点：\$\{difference\.checkpoint\}/);
  assert.match(actualAnnotationSource, /outcome\.accessibleLabel/);
  assert.match(actualAnnotationSource, /真实来源范围：\$\{difference\.scope\.path\}；真实触发：\$\{difference\.scope\.trigger\}/);
  assert.match(actualAnnotationSource, /审阅投影点：事件 #\$\{visibilityColumn\.entry\.seq\}/);
  assert.match(actualAnnotationSource, /该点只控制差异何时显示，不代表真实 workload 在此执行/);
  assert.match(actualAnnotationSource, /实际阶段：\$\{difference\.actual\.anchor\}，\$\{difference\.actual\.phase\}/);
  assert.match(actualAnnotationSource, /既有原型 Workload effect \$\{targetEffectReached \? "已出现" : "尚未出现"\}/);
  assert.match(actualAnnotationSource, /目标生命周期：\$\{difference\.target\.anchor\} \$\{targetAnchorReached \? "已到达" : "尚未到达"\}/);
  assert.match(actualAnnotationSource, /sourceScope\.textContent = `真实触发 · \$\{difference\.scope\.path\} · \$\{difference\.scope\.trigger\}`/);
  assert.match(actualAnnotationSource, /projectionScope\.textContent = `审阅投影 · after #\$\{visibilityColumn\.entry\.seq\}/);
  assert.match(actualAnnotationSource, /targetPhase\.textContent = `目标生命周期 · \$\{difference\.target\.anchor\} \$\{targetAnchorReached \? "已到达" : "尚未到达"\} · \$\{difference\.target\.phase\}`/);
  assert.doesNotMatch(actualAnnotationSource, /aria-controls/);
  assert.match(controller, /button\.id = timingWorkloadEffectDOMID\(entry\.seq, workloadId, effectIndex\)/);
  assert.match(controller, /button\.classList\.add\("is-workload-difference-target"\)/);
  assert.match(controller, /button\.dataset\.workloadDifferenceTargetId = difference\.id/);
  assert.match(controller, /button\.dataset\.fix0809Disposition = difference\.fix0809Disposition/);
  assert.doesNotMatch(controller, /button\.dataset\.fix0809Outcome = difference\.fix0809Outcome/);
  assert.match(controller, /disposition\.visibleLabel/);
  assert.match(controller, /targetBadge\.textContent = `原型 Workload effect · 目标 \$\{difference\.target\.anchor\}`/);
  assert.match(controller, /button\.setAttribute\(\s*"aria-label"/);
  assert.doesNotMatch(controller, /workloadDifferenceWorkloadIDSet|makeTimingWorkloadDifference\(/);
  assert.doesNotMatch(controller, /className = "timing-workload-target"|timing-workload-inline-connector/);

  const connectorSource = sourceBetween(
    controller,
    "function renderTimingDifferenceConnectors()",
    "function scheduleTimingDifferenceConnectors()"
  );
  assert.match(connectorSource, /grid\.querySelectorAll\("\[data-workload-difference-actual-id\]"\)/);
  assert.match(connectorSource, /const targetID = actual\.dataset\.targetElementId/);
  assert.match(connectorSource, /if \(!target \|\| !grid\.contains\(target\)\) return/);
  assert.match(connectorSource, /path\.dataset\.workloadDifferenceConnectorId = actual\.dataset\.workloadDifferenceActualId/);
  assert.match(connectorSource, /path\.dataset\.actualElementId = actual\.id/);
  assert.match(connectorSource, /path\.dataset\.targetElementId = target\.id/);
  assert.match(connectorSource, /path\.classList\.add\("timing-workload-difference-connector"\)/);
  assert.match(connectorSource, /svg\.dataset\.workloadConnectorCount = String\(workloadConnectorCount\)/);
  assert.match(controller, /addEventListener\("scroll", scheduleTimingDifferenceConnectors/);
  assert.match(controller, /timingView\.replaceChildren\(grid\)/);
  assert.doesNotMatch(controller, /replaceChildren\(grid, comparison\)/);

  assert.match(css, /\.timing-workload-actual\[data-fix0809-outcome="implementedLogAccepted"\]/);
  assert.match(css, /\.timing-workload-actual\[data-fix0809-outcome="implementedNotLogVerified"\]/);
  assert.match(css, /\.timing-workload-actual\[data-fix0809-outcome="deferredFrozen"\]/);
  assert.match(css, /\.timing-workload-trace-effect\.is-workload-difference-target[\s\S]*background: linear-gradient/);
  assert.match(css, /\.timing-workload-trace-effect\.is-workload-difference-target[\s\S]*border-color: rgba\(10,132,255,\.78\)/);
  assert.match(css, /\.timing-workload-difference-connector[\s\S]*stroke-dasharray: 4 4/);
  assert.match(css, /\.timing-workload-difference-connector[\s\S]*stroke: rgba\(255,91,82,\.96\)/);
  assert.match(css, /\.timing-difference-connectors[\s\S]*pointer-events: none/);
  assert.doesNotMatch(css, /\.timing-workload-difference\s*\{|\.timing-workload-inline-connector\s*\{/);
  assert.doesNotMatch(css, /\.workload-timing-comparison|\.workload-timing-pair|\.workload-timing-connectors/);
  assert.match(html, /workbench-v17/);
});

test("the workbench catalogs approved UI surfaces and keeps Settings visibly Pending without inventing a phone page", () => {
  assert.doesNotMatch(html, /class="prototype-switcher"|class="panel-heading"/);
  assert.doesNotMatch(css, /\.prototype-switcher|\.panel-heading/);
  const catalogSection = sourceBetween(
    html,
    '<section class="surface-catalog"',
    '<section class="surface-operation-card"'
  );
  assert.match(
    catalogSection,
    /<div class="surface-catalog-heading">[\s\S]*?<h1 id="surface-catalog-title">UI 页面<\/h1>[\s\S]*?<span>视觉真相目录<\/span>[\s\S]*?<p class="supporting-copy">从同一目录选择页面；操作、模拟 UI、业务与生命周期会同步切换。<\/p>/
  );
  assert.doesNotMatch(catalogSection, /class="eyebrow"|TAP-0087 · UI Lifecycle Workbench/);
  const surfaceCatalogHTML = sourceBetween(
    html,
    '<div class="surface-grid" id="surface-catalog">',
    "</div>"
  );
  const catalogSurfaceIds = [...surfaceCatalogHTML.matchAll(/data-review-surface="([^"]+)"/g)]
    .map((match) => match[1]);
  assert.deepEqual(catalogSurfaceIds, [
    "systemLaunchScreen",
    "firstInstallSetup",
    "requiredPermissionCheck",
    "resourceInitialization",
    "viewfinder",
    "library",
    "photoViewer",
    "settings"
  ]);
  assert.match(
    surfaceCatalogHTML,
    /data-review-surface="settings" data-surface-pending disabled>[\s\S]*?<strong>设置页<\/strong>[\s\S]*?待独立视觉切片/
  );
  assert.doesNotMatch(html, /data-phone-page="settings"/);

  const surfaceRegistry = sourceBetween(
    controller,
    "const reviewSurfaceCatalog = Object.freeze({",
    "const surfaceFixturePlans = Object.freeze({"
  );
  assert.doesNotMatch(surfaceRegistry, /\bsettings\s*:/);
  assert.match(controller, /document\.querySelectorAll\("\[data-review-surface\]"\)[\s\S]*if \(button\.disabled\) return;[\s\S]*openSurface\(button\.dataset\.reviewSurface\)/);

  for (const id of [
    "surface-operation-title",
    "surface-operation-state",
    "surface-operation-summary",
    "surface-operation-actions",
    "surface-business-title",
    "surface-business-owner",
    "surface-business-summary",
    "surface-business-machines"
  ]) assert.match(html, new RegExp(`id="${id}"`));
});

test("surface shortcuts reach fixtures only through reset, nextEvent, dispatch, and the reducer journal", () => {
  const dispatchSource = sourceBetween(controller, "function dispatch(event", "function reset(");
  assert.match(dispatchSource, /state = reduce\(state, event\)/);
  assert.match(dispatchSource, /playbackHistory\.push\(clone\(state\)\)/);
  assert.doesNotMatch(dispatchSource, /playbackEvents/);

  const resetSource = sourceBetween(controller, "function reset(", "function snapshot()");
  assert.match(resetSource, /const base = createState\(scenarioId\)/);
  assert.match(resetSource, /const selection = \{ type: "SCENARIO_SELECTED", scenarioId \}/);
  assert.match(resetSource, /state = reduce\(base, selection\)/);
  assert.match(resetSource, /playbackHistory = \[clone\(base\), clone\(state\)\]/);
  assert.doesNotMatch(resetSource, /playbackEvents/);

  const shortcutSource = sourceBetween(controller, "function openSurface(surfaceId)", "function projectedRoute()");
  assert.match(shortcutSource, /reset\(scenarioId\)/);
  assert.match(shortcutSource, /while \(!reviewSurfaceReached\(surfaceId\) && steps < 64\)/);
  assert.match(shortcutSource, /const event = nextEvent\(state\)/);
  assert.match(shortcutSource, /!event \|\| !canReduce\(state, event\)/);
  assert.match(shortcutSource, /dispatch\(event, \{ announce: false \}\)/);
  assert.match(shortcutSource, /reducer journal/);
  assert.doesNotMatch(shortcutSource, /\bstate\s*=/);
  assert.doesNotMatch(shortcutSource, /state\.phone(?:\.[A-Za-z0-9_$]+)?\s*=(?!=)/);
  assert.doesNotMatch(shortcutSource, /state\.machines(?:\.[A-Za-z0-9_$]+)?\s*=(?!=)/);
  assert.doesNotMatch(shortcutSource, /state\.log\.(?:push|splice|unshift)\s*\(/);

  const operationSource = sourceBetween(controller, "function renderSurfaceOperations()", "function renderSurfaceBusiness()");
  assert.match(operationSource, /\(\) => control\.click\(\)/);
  assert.doesNotMatch(operationSource, /\bstartScenario\b|\badvance\b|\bstepBack\b|\breset\s*\(/);
  assert.doesNotMatch(operationSource, /\bstate\s*=/);
  assert.doesNotMatch(operationSource, /state\.(?:phone|machines)(?:\.[A-Za-z0-9_$]+)?\s*=(?!=)/);
});

test("Previous, Next, and Reset are the single fixed playback row and are not duplicated as contextual operations", () => {
  const playbackHTML = sourceBetween(
    html,
    '<section class="journey-controls" aria-label="Scenario playback">',
    "</section>"
  );
  assert.match(
    playbackHTML,
    /id="previous-button"[^>]*disabled>上一个事件<\/button>[\s\S]*?id="next-button"[^>]*hidden>下一个事件<\/button>[\s\S]*?id="reset-button"[^>]*>重置<\/button>/
  );
  assert.equal((html.match(/id="previous-button"/g) || []).length, 1);
  assert.equal((html.match(/id="next-button"/g) || []).length, 1);
  assert.equal((html.match(/id="reset-button"/g) || []).length, 1);
  assert.ok(html.indexOf('<section class="journey-controls"') < html.indexOf('id="launch-scenario-card"'));
  assert.doesNotMatch(html, /上一步逻辑事件|下一逻辑事件/);
  assert.match(css, /\.journey-controls \{ display: grid; grid-template-columns: repeat\(3, minmax\(0, 1fr\)\); gap: 6px; \}/);
  assert.match(css, /\.journey-controls > button \{ min-width: 0;/);

  const operationSource = sourceBetween(controller, "function renderSurfaceOperations()", "function renderSurfaceBusiness()");
  assert.doesNotMatch(operationSource, /启动本场景|推进(?: ·)?|上一个事件|下一个事件|重置|\bstartScenario\b|\badvance\b|\bstepBack\b|\breset\s*\(/);
  assert.match(controller, /byID\("previous-button"\)\.addEventListener\("click", stepBack\)/);
  assert.match(controller, /byID\("next-button"\)\.addEventListener\("click", advance\)/);
  assert.match(controller, /byID\("reset-button"\)\.addEventListener\("click", \(\) => reset\(\)\)/);
});

test("the state-machine diagram draws only executed reducer edges and treats registry nodes as an unvisited vocabulary", () => {
  assert.match(html, /id="machine-flow-select"/);
  assert.match(html, /id="machine-flow-diagram"[^>]*aria-label="状态机流程图"/);
  assert.match(html, /id="machine-list" hidden/);

  const flowSource = sourceBetween(controller, "function renderMachines()", "function compactEffectValue(");
  assert.match(flowSource, /const journalEdges = state\.log\.flatMap\(\(entry\) => entry\.effects\.edges/);
  assert.match(flowSource, /\.filter\(\(edge\) => edge\.machineId === selectedMachineId\)/);
  assert.match(flowSource, /for \(const edge of journalEdges\)/);
  assert.match(flowSource, /arrow\.dataset\.focusSeq = String\(edge\.seq\)/);
  assert.match(flowSource, /appendNode\(edge\.from/);
  assert.match(flowSource, /appendNode\(edge\.to/);

  const executedPathSource = sourceBetween(flowSource, "const journalEdges", "const visited = new Set(");
  assert.doesNotMatch(executedPathSource, /registry\.nodes/);
  assert.doesNotMatch(executedPathSource, /is-next|next legal|legal next/i);

  const vocabularyLegendSource = sourceBetween(flowSource, "const visited = new Set(", "const diagram = byID(");
  assert.match(vocabularyLegendSource, /const unvisited = registry\.nodes\.filter\(\(node\) => !visited\.has\(node\)\)/);
  assert.match(vocabularyLegendSource, /本次 journal 尚未经过/);
  assert.doesNotMatch(vocabularyLegendSource, /machine-flow-arrow/);
});

test("workload buttons install or restore one canonical reviewer snapshot for phone, machine, focus, and timing", () => {
  const renderSource = sourceBetween(controller, "function renderWorkloads()", "function focusWorkload(");
  assert.match(renderSource, /const card = document\.createElement\("button"\)/);
  assert.match(renderSource, /card\.dataset\.workloadId = id/);
  assert.match(renderSource, /跳转到对应 UI 与生命周期审阅时刻/);
  assert.match(renderSource, /registry\.observed\.earliest/);
  assert.match(renderSource, /registry\.observed\.trigger/);
  assert.match(renderSource, /registry\.observed\.owner/);
  assert.match(renderSource, /registry\.target\.earliest/);
  assert.match(renderSource, /registry\.target\.trigger/);
  assert.match(renderSource, /registry\.target\.owner/);
  assert.match(renderSource, /registry\.observed\.evidence/);
  assert.match(renderSource, /registry\.alignment/);

  assert.match(controller, /buildWorkloadInspectionJourney/);
  assert.match(controller, /workloadInspectionReached/);
  const reachedSource = sourceBetween(
    model,
    "export function workloadInspectionReached(",
    "export function buildWorkloadInspectionJourney("
  );
  assert.match(reachedSource, /trace\?\.event\.type === plan\.eventType/);
  assert.match(reachedSource, /trace\.effects\.workloads\.includes\(workloadId\)/);
  assert.match(reachedSource, /state\.phone\.page === plan\.page/);
  assert.match(reachedSource, /state\.workloads\[workloadId\] === plan\.status/);
  const builderSource = sourceBetween(
    model,
    "export function buildWorkloadInspectionJourney(",
    "export function publicSnapshot("
  );
  assert.match(builderSource, /const base = createState\(plan\.scenarioId\)/);
  assert.match(builderSource, /let state = reduce\(base, \{ type: "SCENARIO_SELECTED", scenarioId: plan\.scenarioId \}\)/);
  assert.match(builderSource, /const history = \[clone\(base\), clone\(state\)\]/);
  assert.match(builderSource, /const event = nextEvent\(state\)/);
  assert.match(builderSource, /if \(!event \|\| !canReduce\(state, event\)\) break/);
  assert.match(builderSource, /state = reduce\(state, event\)/);
  assert.match(builderSource, /history\.push\(clone\(state\)\)/);
  assert.match(builderSource, /throw new Error\(`Canonical journal did not reach workload inspection target/);
  assert.doesNotMatch(builderSource, /state\.(?:phone|machines|workloads)(?:\.[A-Za-z0-9_$]+|\[[^\]]+\])?\s*=(?!=)/);
  assert.doesNotMatch(builderSource, /state\.log\.(?:push|splice|unshift)\s*\(/);

  const historyLookupSource = sourceBetween(
    controller,
    "function workloadInspectionHistoryIndex(",
    "function focusWorkload("
  );
  assert.match(historyLookupSource, /for \(let index = playbackHistory\.length - 1; index >= 0; index -= 1\)/);
  assert.match(historyLookupSource, /workloadInspectionReached\(playbackHistory\[index\], workloadId\)/);

  const focusSource = sourceBetween(controller, "function focusWorkload(", "function renderEventLog()");
  assert.match(focusSource, /if \(!registry \|\| !machineRegistry\[registry\.machineId\]\) return snapshot\(\)/);
  assert.match(focusSource, /const historyIndex = workloadInspectionHistoryIndex\(workloadId\)/);
  assert.match(focusSource, /const usedCanonicalFixture = historyIndex < 0/);
  assert.match(focusSource, /const journey = buildWorkloadInspectionJourney\(workloadId\)/);
  assert.match(focusSource, /playbackHistory = journey\.history\.map\(clone\)/);
  assert.match(focusSource, /state = clone\(journey\.state\)/);
  assert.match(focusSource, /playbackHistory = playbackHistory\.slice\(0, historyIndex \+ 1\)\.map\(clone\)/);
  assert.match(focusSource, /state = clone\(playbackHistory\.at\(-1\)\)/);
  assert.match(focusSource, /const trace = state\.log\.at\(-1\) \|\| null/);
  assert.match(focusSource, /selectedMachineId = registry\.machineId/);
  assert.match(focusSource, /focusSeq = trace\?\.seq \?\? null/);
  assert.match(focusSource, /selectedMachineFocusSeq = focusSeq \?\? `page:\$\{state\.phone\.page\}:\$\{state\.seq\}`/);
  assert.match(focusSource, /renderAll\(\)/);
  assert.doesNotMatch(focusSource, /state\.(?:phone|machines|workloads)(?:\.[A-Za-z0-9_$]+|\[[^\]]+\])?\s*=(?!=)/);
  assert.doesNotMatch(focusSource, /state\.log\.(?:push|splice|unshift)\s*\(/);

  const snapshotSource = sourceBetween(controller, "function snapshot()", "function stepBack()");
  assert.match(snapshotSource, /\.\.\.publicSnapshot\(state\)/);
  assert.match(snapshotSource, /focusedTrace: clone\(focusedTrace\(\)\)/);
  assert.match(snapshotSource, /currentSurface: currentReviewSurface\(\)/);
  assert.match(snapshotSource, /currentPhonePage: state\.phone\.page/);
  assert.match(snapshotSource, /selectedMachineId/);
  assert.match(snapshotSource, /selectedWorkloadId/);

  const timingColumnSource = sourceBetween(controller, "function timingColumns()", "function makeCausalEvent(");
  assert.match(timingColumnSource, /\[\.\.\.state\.log\]\.sort/);
  assert.match(timingColumnSource, /stateAfter: stateSnapshotAtSequence\(entry\.seq\)/);

  const workloadListener = sourceBetween(
    controller,
    'byID("workload-list").addEventListener("click"',
    'byID("follow-latest").addEventListener("click"'
  );
  assert.match(workloadListener, /event\.target\.closest\("\[data-workload-id\]"\)/);
  assert.match(workloadListener, /focusWorkload\(card\.dataset\.workloadId\)/);
});

test("timing is the primary t0…tn projection with four causal lanes and Ordered log shares one focus", () => {
  assert.match(html, /data-event-view="timing" aria-pressed="true">Timing 时序<\/button>/);
  assert.match(html, /data-event-view="log" aria-pressed="false">顺序日志<\/button>/);
  assert.match(html, /id="timing-event-view"[^>]*aria-label="t0 到 tn 事件时序图"/);
  assert.match(html, /id="event-log"[^>]*role="log"/);

  const initialReviewSource = sourceBetween(controller, "function makeInitialReviewEntry()", "const initialReviewEntry = makeInitialReviewEntry()");
  assert.match(initialReviewSource, /eventViewMode: "timing"/);
  assert.doesNotMatch(initialReviewSource, /payload|URLSearchParams|sessionStorage|resumeKey/);

  const timingColumnSource = sourceBetween(controller, "function timingColumns()", "function makeCausalEvent(");
  assert.match(timingColumnSource, /let interval = "pre-t0"/);
  assert.match(timingColumnSource, /\[\.\.\.state\.log\]\.sort\(\(left, right\) => left\.seq - right\.seq\)/);
  assert.match(timingColumnSource, /const reached = entry\.effects\.milestones \|\| \[\]/);
  assert.match(timingColumnSource, /timelineRegistry\.find\(\(item\) => item\.id === milestone\)\?\.interval \|\| interval/);

  const timingSource = sourceBetween(controller, "function renderTimingEventView()", "function renderEventViews()");
  for (const [label, id] of [
    ["UI", "ui"],
    ["Reducer", "reducer"],
    ["Workload", "workload"],
    ["Marker", "marker"]
  ]) assert.match(timingSource, new RegExp(`makeTimingLane\\("${label}", "${id}"`));
  assert.match(timingSource, /entry\.pageBefore === entry\.pageAfter/);
  assert.match(timingSource, /entry\.event\.type/);
  assert.match(timingSource, /entry\.effects\.workloads \|\| \[\]/);
  assert.match(timingSource, /entry\.effects\.markers \|\| \[\]/);
  const causalEventSource = sourceBetween(controller, "function makeCausalEvent(", "function makeTimingLane(");
  assert.match(causalEventSource, /button\.dataset\.focusSeq = String\(seq\)/);

  const eventViewSource = sourceBetween(controller, "function renderEventViews()", "function renderAll()");
  assert.match(eventViewSource, /timing\.hidden = eventViewMode !== "timing"/);
  assert.match(eventViewSource, /log\.hidden = eventViewMode !== "log"/);
  assert.doesNotMatch(eventViewSource, /focusSeq\s*=/);

  const logListener = sourceBetween(
    controller,
    'byID("event-log").addEventListener("click"',
    'byID("timing-event-view").addEventListener("click"'
  );
  const timingListener = sourceBetween(
    controller,
    'byID("timing-event-view").addEventListener("click"',
    'byID("machine-flow-diagram").addEventListener("click"'
  );
  assert.match(logListener, /focusTraceSequence\(button\.dataset\.focusSeq\)/);
  assert.match(timingListener, /focusTraceSequence\(button\.dataset\.focusSeq\)/);
  assert.match(controller, /snapshot\(\)[\s\S]*eventViewMode,[\s\S]*currentSurface: currentReviewSurface\(\)/);
});

test("initial App Attest is a required Setup row while permission recovery remains Camera and Photos only", () => {
  assert.match(html, /用于首次完成设备凭据注册与验证/);
  assert.match(html, /App Attest、相机与照片图库/);
  assert.match(controller, /setupRequiredReady\(state\)/);
  assert.match(controller, /for \(const permission of \["camera", "photos"\]\)/);
  assert.match(model, /Setup Continue requires App Attest, Camera, and Photos/);
  assert.match(model, /return permissions\.camera === "authorized" && photosUsable\(permissions\.photos\)/);
  assert.match(controller, /SETUP_PERMISSION_RECOVERY_TAPPED/);
  assert.match(controller, /restricted\.disabled = true/);
  assert.match(controller, /前往设置/);

  const setupRenderSource = sourceBetween(controller, "function renderSetup()", "function renderPermissionCheck()");
  assert.match(setupRenderSource, /const event = prototypeEventForControl\(control\)/);
  assert.match(setupRenderSource, /control\.disabled = !event \|\| !canReduce\(state, event\)/);
  const phoneAvailabilitySource = sourceBetween(controller, "function phoneControlIsAvailable(", "function renderSurfaceOperations()");
  assert.match(phoneAvailabilitySource, /return prototypeEvent == null \|\| canReduce\(state, prototypeEvent\)/);
  const phoneClickSource = sourceBetween(
    controller,
    'byID("phone-surface").addEventListener("click"',
    "tapShareSlice = mountTapShareSlice("
  );
  assert.match(phoneClickSource, /if \(prototypeEvent\) \{[\s\S]*if \(canReduce\(state, prototypeEvent\)\) dispatch\(prototypeEvent\)/);
});

test("Viewfinder mirrors the current native hierarchy tokens while deferred controls remain inert", () => {
  const viewfinderHTML = sourceBetween(
    html,
    '<section class="phone-page viewfinder-page"',
    '<section class="phone-page library-page"'
  );
  assert.match(
    viewfinderHTML,
    /class="viewfinder-shoulder-row">[\s\S]*?class="basic-ev-control"[^>]*>[\s\S]*?<span>EV<\/span><span>0\.0<\/span>[\s\S]*?class="viewfinder-round-control settings-control"[^>]*aria-label="Settings"/
  );
  assert.match(
    viewfinderHTML,
    /class="viewfinder-toolbar"[^>]*>[\s\S]*?aria-label="Flash off"[\s\S]*?aria-label="Live Photo off"[\s\S]*?<span><\/span>[\s\S]*?class="viewfinder-round-control pro-control"[^>]*>PRO<\/button>/
  );
  assert.match(viewfinderHTML, /class="focal-length-selector"[\s\S]*?<strong>13<\/strong>[\s\S]*?<strong>24<\/strong>[\s\S]*?<strong>48<\/strong>/);
  assert.match(viewfinderHTML, /class="viewfinder-capture-controls">[\s\S]*?class="professional-toolbar-slot"[\s\S]*?class="capture-row"[\s\S]*?class="mode-strip"/);
  assert.match(viewfinderHTML, /<button type="button" disabled class="selected">PHOTO<\/button>[\s\S]*?<button type="button" disabled>VIDEO<\/button>/);
  assert.match(viewfinderHTML, /class="shutter" disabled/);
  assert.doesNotMatch(viewfinderHTML, /Controls · TAP-0088|viewfinder-mock-badge|class="mock-badge"/);

  assert.match(css, /\.camera-preview-stage \{[^}]*padding: 0 8px;/);
  assert.match(css, /\.camera-preview-viewport \{[^}]*border-radius: 10px;/);
  assert.match(css, /\.focal-length-selector \{[^}]*width: min\(232px, calc\(100% - 20px\)\);/);
  assert.match(css, /\.focal-length-selector button \{ width: 48px; height: 42px;/);
  assert.match(css, /\.viewfinder-capture-controls \{[^}]*grid-template-rows: 38px 78px 50px;/);

  assert.match(html, /2D \/ 3D · TAP-0089/);
  assert.match(html, />2D<\/button>/);
  assert.match(html, />3D<\/button>/);
  assert.doesNotMatch(controller, /VIEWFINDER_CAPTURE|VIEWER_2D|VIEWER_3D/);
});

test("TAP-0081 Share mounts inside the same Photo Viewer without URL, journal, or startup-state bridging", () => {
  const viewerHTML = sourceBetween(
    html,
    '<section class="phone-page viewer-page"',
    "</section>\n          </div>"
  );
  assert.match(viewerHTML, /data-phone-page="photoViewer" data-tap0081-share/);
  assert.equal(viewerHTML.match(/\bdata-existing-share-boundary\b/g)?.length, 1);
  const shareButtonHTML = sourceBetween(
    viewerHTML,
    '<button type="button" class="round-control viewer-share-control share-button" data-existing-share-boundary',
    "</button>"
  );
  assert.match(shareButtonHTML, /aria-controls="tap-share-popover"/);
  assert.match(shareButtonHTML, /assets\/icons\/share-network\.svg/);
  assert.doesNotMatch(shareButtonHTML, /\bhref\s*=|data-url|data-route/);
  assert.match(viewerHTML, /id="tap-share-popover" data-tap-share-popover/);
  assert.match(html, /id="tap-share-local-inspector"[\s\S]*?TAP-0081 · local Share presentation/);

  assert.match(controller, /import \{ mountTapShareSlice \} from "\.\/tap-share-slice\.mjs"/);
  const mountSource = sourceBetween(
    controller,
    "tapShareSlice = mountTapShareSlice({",
    "window.__tapCamStartupPrototype = Object.freeze({"
  );
  assert.match(mountSource, /root: document\.querySelector\("\[data-tap0081-share\]"\)/);
  assert.match(mountSource, /trigger: document\.querySelector\("\[data-existing-share-boundary\]"\)/);
  assert.match(mountSource, /TAP-0087 seq \$\{state\.seq\} 未改变/);
  assert.doesNotMatch(mountSource, /\bdispatch\s*\(|\breduce\s*\(|\bstate\s*=|\bfocusSeq\s*=|\bplaybackHistory\b/);
  assert.match(controller, /share: \(\) => tapShareSlice\.snapshot\(\)/);

  for (const source of [controller, shareModule]) {
    assert.doesNotMatch(source, /sessionStorage|resumeKey|URLSearchParams|window\.location|location\.(?:assign|replace)|history\.(?:pushState|replaceState)/);
  }
  assert.doesNotMatch(controller, /\bSHARE_[A-Z0-9_]+\b/);
  assert.doesNotMatch(model, /\bSHARE_[A-Z0-9_]+\b/);

  for (const forbidden of ["AirDrop", "Locked Camera", "UIActivityViewController"]) {
    for (const source of [html, controller, model, shareModule]) {
      assert.doesNotMatch(source, new RegExp(forbidden, "i"));
    }
  }
});

test("review playback can move backward by restoring the previous reducer snapshot", () => {
  assert.match(html, /id="previous-button"[^>]*disabled[^>]*>上一个事件<\/button>/);
  assert.match(controller, /let playbackHistory = initialReviewEntry\.history/);
  assert.match(controller, /playbackHistory\.push\(clone\(state\)\)/);
  assert.doesNotMatch(controller, /\bplaybackEvents\b/);

  const stepBack = sourceBetween(controller, "function stepBack()", "function scheduleStartupTransitionIfNeeded()");
  assert.match(stepBack, /clearLaunchTransition\(\)/);
  assert.match(stepBack, /playbackHistory\.pop\(\)/);
  assert.match(stepBack, /state = clone\(playbackHistory\.at\(-1\)\)/);
  assert.match(stepBack, /focusSeq = state\.log\.at\(-1\)\?\.seq \?\? null/);
  assert.doesNotMatch(stepBack, /\breduce\s*\(|\bdispatch\s*\(/);

  assert.match(controller, /previousButton\.disabled = playbackHistory\.length <= 1/);
  assert.match(controller, /byID\("previous-button"\)\.addEventListener\("click", stepBack\)/);
  assert.match(controller, /\bback: stepBack\b/);
  assert.doesNotMatch(model, /\b(?:STEP_BACK|PREVIOUS_EVENT|REVIEW_BACK)\b/);
});

test("same-page Share follows local integrity to selector to preparation, then closes at the system boundary", () => {
  const localFlowHTML = sourceBetween(
    html,
    '<div class="tap-share-local-flow"',
    '<p id="tap-share-local-effect"'
  );
  assert.match(localFlowHTML, /data-tap-share-node="closed"[\s\S]*?data-tap-share-node="integrityChecking"[\s\S]*?data-tap-share-node="selector"[\s\S]*?data-tap-share-node="preparing"[\s\S]*?data-tap-share-node="failure"/);

  const selectorSource = sourceBetween(shareModule, "function renderSelector(", "function resolveIntegrity(");
  const resolveSource = sourceBetween(shareModule, "function resolveIntegrity(", "function beginIntegrityCheck()");
  const integritySource = sourceBetween(shareModule, "function beginIntegrityCheck()", "function complete(");
  const completeSource = sourceBetween(shareModule, "function complete(", "function prepare(");
  const prepareSource = sourceBetween(shareModule, "function prepare(", "function bind(");
  assert.match(integritySource, /showPanel\("integrityChecking", "integrity\.started"\)/);
  assert.match(integritySource, /later\(\(\) => resolveIntegrity\(attempt\)/);
  assert.match(resolveSource, /renderSelector\(\)/);
  assert.match(selectorSource, /showPanel\("selector", "integrity\.resolved"\)/);
  assert.match(prepareSource, /showPanel\("preparing", "preparation\.started"\)/);
  assert.match(prepareSource, /renderSelector\(\{ preservePanel: true \}\)/);
  assert.match(prepareSource, /else complete\(attempt\)/);
  assert.match(completeSource, /state\.systemActivityBoundaryReached = true/);
  assert.match(completeSource, /showPanel\("closed", "payload\.ready\.systemBoundaryReached"\)/);

  const dismissSource = sourceBetween(controller, "function dismissTapSharePresentation(", "function currentReviewSurface()");
  assert.match(dismissSource, /snapshot\(\)\.panel === "closed"\) return false/);
  assert.match(dismissSource, /tapShareSlice\.close\(\)/);
  assert.match(dismissSource, /return true/);
  const phoneClickSource = sourceBetween(
    controller,
    'byID("phone-surface").addEventListener("click"',
    "tapShareSlice = mountTapShareSlice("
  );
  assert.match(
    phoneClickSource,
    /else if \(action === "viewer-back"\) \{\s*if \(!dismissTapSharePresentation\(\{ restoreFocus: true \}\)\) dispatch\(\{ type: "VIEWER_BACK_TAPPED" \}\);\s*\}/
  );
});

test("one focused trace drives every inspector highlight", () => {
  assert.match(controller, /function focusedTrace\(\)/);
  assert.match(controller, /function highlightSequence\(/);
  assert.match(controller, /dataset\.highlightSeq = String\(trace\.seq\)/);
  assert.match(controller, /trace\?\.effects\.machines/);
  assert.match(controller, /trace\?\.effects\.workloads/);
  assert.match(controller, /trace\?\.effects\.milestones/);
  assert.match(controller, /trace\?\.effects\.page/);
  assert.match(controller, /trace\?\.effects\.edges/);
  assert.match(controller, /trace\?\.effects\.markers/);
  assert.match(controller, /id: "marker-snapshot"|byID\("marker-snapshot"\)/);
  assert.match(controller, /window\.__tapCamStartupPrototype/);
  assert.match(css, /\[data-highlight-seq\]/);
});

test("candidate media and exact symbol exports match the manifest", () => {
  const viewfinder = manifest.fixtureAssets.find((asset) => asset.path.endsWith("viewfinder-camera-fixture.png"));
  assert.equal(sha256(viewfinder.path), viewfinder.sha256);
  for (const symbol of Object.values(candidate.symbolAssets)) {
    assert.equal(sha256(symbol.path), symbol.sha256);
  }
  assert.match(html, /assets\/media\/viewfinder-camera-fixture\.png/);
  assert.match(html, /assets\/tapcam-launch-logo\.png/);
});

test("desktop review keeps phone, lifecycle, workloads, and console in one viewport", () => {
  const desktop = sourceBetween(css, "@media (min-width: 1180px) {", "@media (min-width: 1180px) and (max-height: 760px)");
  assert.match(desktop, /html, body \{ height: 100%; overflow: hidden; \}/);
  assert.match(desktop, /height: 100svh/);
  assert.match(desktop, /grid-template-columns: clamp\(210px, 17vw, 240px\) var\(--scaled-phone-width\) minmax\(0, 1fr\)/);
  assert.match(desktop, /\.scenario-panel, \.phone-column, \.inspector-panel \{ min-width: 0; min-height: 0; height: 100%; \}/);
  assert.match(desktop, /\.phone-column \{ width: var\(--scaled-phone-width\); display: block; justify-items: start; overflow: hidden; \}/);
  assert.match(desktop, /\.inspector-panel[\s\S]*grid-template-columns: minmax\(0, 1\.06fr\) minmax\(300px, \.94fr\)/);
  assert.match(desktop, /\.surface-business-card \{ grid-column: 1 \/ -1; grid-row: 2; \}/);
  assert.match(desktop, /\.lifecycle-inspector-column[\s\S]*grid-column: 1;[\s\S]*grid-row: 3/);
  assert.match(desktop, /\.runtime-inspector-column[\s\S]*grid-column: 2;[\s\S]*grid-row: 3/);
  assert.match(desktop, /\.event-section \{ grid-column: 1 \/ -1; grid-row: 4; \}/);
  assert.match(desktop, /\.machine-list, \.machine-flow-diagram, \.workload-list, \.event-log \{ min-height: 0; overflow-y: auto/);
  assert.match(css, /\.timing-event-view \{ min-height: 0; flex: 1; overflow: auto/);
  assert.match(css, /@media \(min-width: 1180px\) and \(max-height: 760px\) \{[\s\S]*--phone-scale: \.72; --scaled-phone-width: 295px/);

  for (const heightBand of [
    /@media \(min-width: 1180px\) and \(max-height: 760px\)/,
    /@media \(min-width: 1180px\) and \(min-height: 761px\) and \(max-height: 840px\)/,
    /@media \(min-width: 1180px\) and \(min-height: 841px\) and \(max-height: 940px\)/,
    /@media \(min-width: 1180px\) and \(min-height: 941px\)/
  ]) assert.match(css, heightBand);

  assert.match(css, /@media \(max-width: 1179px\)/);
  assert.match(css, /@media \(max-width: 790px\)/);
  assert.match(css, /@media \(max-width: 430px\)/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(html, /fixture delay demonstrates order only|演示说明/);
});
