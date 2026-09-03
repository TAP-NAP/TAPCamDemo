# Planes Geometry Principles

`Planes` is a photo-local geometry tool, not color segmentation, ARKit plane
tracking, or world reconstruction. From one TAP depth photo it reconstructs
camera-space points, fits a plane near a user-selected seed, grows the connected
planar surface, and projects the result back onto the image.

## Required input

Analysis requires one bounded, validated input containing:

- the primary RGB image;
- finite positive metric depth samples in native row-major pixel order;
- usable camera intrinsics `fx`, `fy`, `cx`, `cy` from the manifest, with the
  Apple depth calibration as the local fallback; and
- image orientation sufficient to map displayed taps to native depth pixels.

`TAPDepthAnalysisInputValidation` rejects oversized images or maps, inconsistent
sample counts, wholly invalid depth, and unusable calibration before geometry
allocates per-pixel products. RGB, depth, calibration, and orientation must all
describe the same captured resource; a preview or thumbnail is not an input.

## Coordinate contract

For native depth pixel `(u, v)` and depth in meters `Z`, pinhole back-projection
is:

```text
X = (u - cx) * Z / fx
Y = (v - cy) * Z / fy
Z = depthMeters
```

Plane fitting uses these camera-space points. It deliberately does not compare
only adjacent raw Z values: a continuous tilted wall has a real Z gradient but
still lies near one 3D plane. Pixel runs and RGB sampling remain in raw/native
coordinates; display orientation is applied once at the rendering boundary to
both geometry and the fitted projection camera.

Camera space is local to the captured camera. Without gravity, motion, or a
world transform, the app cannot label a plane as floor/wall, track it across
photos, infer hidden geometry, or claim a world-space model.

## Seeded plane region

The current interaction and algorithm are fixed:

1. Map the user's tap to a native valid depth pixel.
2. Build or reuse the image-generation geometry cache of projected points and
   bounded local normals.
3. Fit a seed-local plane with weighted total least squares/PCA.
4. Measure perpendicular point-to-plane residuals.
5. Derive an adaptive residual threshold from the median and MAD, clamped by
   the selected strictness and depth-quality bounds.
6. Grow an 8-connected BFS region through accepted neighboring points.
7. Refit from the first accepted set and run one second bounded growth pass.
8. Produce compact pixel runs, contour, grid diagnostics, estimate, confidence,
   flatness, sample count, visible bounds, and approximate visible area.

Residual is the primary acceptance signal. At high strictness, local-normal
agreement is a soft penalty, not a replacement binary angle gate. Minimum seed
and region samples reject accidental tiny fits. `maximumVisitedPixels` bounds
worst-case growth; cancellation is checked during projection, fitting, growth,
and output work so an old tap cannot publish over a newer generation.

The cache is per immutable loaded input. Prewarm is optional: if it is absent,
the first request may build it, but only the newest request identity can store or
publish the result. Equivalent taps may reuse cached geometry; stale input,
strictness, orientation, or generation cannot.

## Output and claim boundary

The overlay shows the selected seed, connected mask/boundary, fit diagnostics,
and progress. Confidence combines fit residual, inlier ratio, and supported
sample count; it is not a probability that the real-world object is planar.
Area is an approximation of the visible grown region in camera coordinates, not
the full physical surface beyond the mask.

The same projection primitives feed the static-photo `3D projection`. That view
converts positive camera depth to SceneKit's camera-facing `-Z`, starts from the
capture-camera projection, rejects far-depth sentinels, and keeps interaction as
a reversible view transform. It remains a colored point projection, not a mesh,
scan, digital twin, or recovered world camera.

Implementation entry points are `DepthAnalysisPlaneRegionRequestCoordinator`,
`DepthAnalysisPlaneRegionDetector`, `TAPDepthGeometryProjector`, and
`TAPPlaneEstimator`. `TAPDepthAnalysisPlaneRegionTests` protects projection,
orientation, tilted/noisy planes, strictness, growth bounds, cache generation,
cancellation, and the non-world-space claim boundary.
