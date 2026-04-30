# Apple Depth Limitations

Apple still-photo depth is not an arbitrary pairing system. Depth delivery is
bound to a device or virtual device, active video format, active depth format,
zoom range, and session configuration.

The safe release path is:

```text
AVCaptureDevice with supportedDepthDataFormats
        |
        v
activeFormat + activeDepthDataFormat
        |
        v
AVCapturePhotoOutput.isDepthDataDeliveryEnabled
        |
        v
AVCapturePhoto.depthData
```

Important constraints:

- A physical RGB camera cannot be assumed to pair with an independent LiDAR or
  TrueDepth device.
- `supportedVideoZoomRangesForDepthDataDelivery` can restrict zoom when depth is
  enabled.
- Virtual devices may switch constituents internally; manifest records
  `activePrimaryConstituent` when available.
- Non-LiDAR devices do not let us assert LiDAR fusion participation. The
  manifest records only public `AVCaptureDevice.DeviceType` facts.
