import Foundation
import AVFoundation

/// Phase 6 — stabilization presets (blueprint §7.4).
///
/// Honest tradeoff surfaced BEFORE render: more smoothing = more crop, memory
/// and latency. Crop fractions are documented ESTIMATES for the pre-render
/// preview ("~N% tighter frame"); the exact crop is hardware/format dependent
/// and its real feel is L3 calibration (HANDOFF). Never present a mode the
/// device can't do — unsupported presets are disabled with a reason, not
/// silently swapped.
enum StabilizationPreset: String, CaseIterable, Identifiable, Sendable {
    case off, standard, cinematic
    /// v2 (blueprint §2): visible but locked until Extended ships.
    case cinematicExtended

    var id: String { rawValue }

    var isV2Locked: Bool { self == .cinematicExtended }

    var label: String {
        switch self {
        case .off:               "Off"
        case .standard:          "Standard"
        case .cinematic:         "Cinematic"
        case .cinematicExtended: "Cinematic Extended"
        }
    }

    /// Operator guidance (blueprint: Off for rigid arms, Standard/Cinematic
    /// for cheap/vibrating rigs).
    var guidance: String {
        switch self {
        case .off:               "Rigid, well-balanced arms. Full frame, zero added latency."
        case .standard:          "Light smoothing for slightly vibrating rigs."
        case .cinematic:         "Strong smoothing for cheap or shaky arms."
        case .cinematicExtended: "Maximum smoothing — coming in a later update."
        }
    }

    var avMode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off:               .off
        case .standard:          .standard
        case .cinematic:         .cinematic
        case .cinematicExtended: .cinematicExtended
        }
    }

    /// Estimated crop cost (fraction of frame lost to stabilization margin).
    /// Estimates for the preview UI; exact values are format-dependent.
    var estimatedCropFraction: Double {
        switch self {
        case .off:               0
        case .standard:          0.10
        case .cinematic:         0.20
        case .cinematicExtended: 0.25
        }
    }

    /// "~20% tighter frame" — the pre-render crop preview line.
    var cropPreviewText: String? {
        guard estimatedCropFraction > 0 else { return nil }
        return "~\(Int(estimatedCropFraction * 100))% tighter frame"
    }

    // MARK: - Availability (pure core = testable; device probe wraps it)

    /// Which presets are usable given the modes a format supports. `off` is
    /// always usable; v2-locked presets are NEVER offered in v1.
    static func supportedPresets(
        supportedAVModes: Set<AVCaptureVideoStabilizationMode>
    ) -> [StabilizationPreset] {
        allCases.filter { preset in
            if preset == .off { return true }
            if preset.isV2Locked { return false }
            return supportedAVModes.contains(preset.avMode)
        }
    }

    /// Probe the current device's rear camera (settings screens have no live
    /// session). Simulator has no camera → only `.off` (honest).
    static func supportedOnCurrentDevice() -> [StabilizationPreset] {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else { return [.off] }
        var modes: Set<AVCaptureVideoStabilizationMode> = []
        for format in device.formats {
            for preset in allCases where format.isVideoStabilizationModeSupported(preset.avMode) {
                modes.insert(preset.avMode)
            }
        }
        return supportedPresets(supportedAVModes: modes)
    }

    // MARK: - Legacy migration

    /// Map the pre-Phase-6 `stabilizationEnabled: Bool?` to a preset:
    /// explicit false → off; true/nil → standard (safe middle — the old code
    /// reached for the strongest mode, which contradicts the §7.4 default of
    /// honesty-about-crop; DECISIONS_LOG #26).
    static func migrated(fromLegacyEnabled legacy: Bool?) -> StabilizationPreset {
        legacy == false ? .off : .standard
    }

    /// Effective preset for camera settings (new field wins; legacy migrates).
    static func effective(from camera: CameraSettings) -> StabilizationPreset {
        if let raw = camera.stabilizationPreset,
           let preset = StabilizationPreset(rawValue: raw) {
            return preset
        }
        return migrated(fromLegacyEnabled: camera.stabilizationEnabled)
    }
}
