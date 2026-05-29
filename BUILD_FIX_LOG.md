# Build Fix Log — 2026-05-29

Errors reported by user before this session:

```
Missing package product 'FFmpeg-Kit'
Missing package product 'Sentry'
```

## T0 — Initial diagnosis

`Photobooth-ai.xcodeproj/project.pbxproj` declares two SPM
dependencies, both correctly wired into PBXBuildFile,
PBXFrameworksBuildPhase, packageProductDependencies,
packageReferences, XCRemoteSwiftPackageReference, and
XCSwiftPackageProductDependency sections.

| Product | Repo | Pin |
|---------|------|-----|
| `FFmpeg-Kit` | `tylerjonesio/ffmpeg-kit-spm` | revision `6053b0e4f8607314ff5e14e0b18fc250c0f87c9b` |
| `Sentry` | `getsentry/sentry-cocoa` | upToNextMajor `9.9.0` → resolved `9.15.0` |

`Package.resolved` already has both pins. Suggests this is a derived-data
/ SPM cache resolution mismatch, not a manifest problem. Plan:

1. Try a clean `xcodebuild build` first to capture the *current* error
   verbatim before wiping anything.
2. If it fails: wipe `DerivedData/Photobooth-ai-*` + `~/Library/Caches/org.swift.swiftpm` + local `.swiftpm` + `xcshareddata/swiftpm/`.
3. Re-resolve + re-build.
4. If still failing: fall back to the FFmpeg fork waterfall per prompt.

## T1 — First build attempt: GREEN

`xcodebuild -project Photobooth-ai.xcodeproj -scheme Photobooth-ai -destination 'generic/platform=iOS Simulator' -configuration Debug build` → `** BUILD SUCCEEDED **`.

Both packages resolved cleanly:

- `Sentry: https://github.com/getsentry/sentry-cocoa @ 9.15.0`
- `ffmpeg-kit-spm: https://github.com/tylerjonesio/ffmpeg-kit-spm @ 6053b0e`

All 5 targets in the dep graph built: `Photobooth-ai`, `Sentry`,
`SentryCppHelper`, `FFmpeg-Kit` (twice — duplicate explicit dep
in the wrapper package, harmless). All 7 FFmpeg subframeworks
(`libavcodec/avdevice/avfilter/avformat/avutil/swresample/swscale`)
+ `ffmpegkit` + `Sentry` copied into `.app/Frameworks/`.

**Diagnosis of user-reported error:** the "Missing package product"
errors were stale. Package.resolved was already correct from RA3
(`b46340b`), but the previous Xcode session must have hit a transient
resolution failure (network blip, derived-data corruption, or
Xcode-side caching). The pre-warm during the RA0-RA8 commit cycle
quietly fixed it. No code changes needed.

**No commit needed for Phase 1.** Build is green as-is. Moving to
Phase 2.
