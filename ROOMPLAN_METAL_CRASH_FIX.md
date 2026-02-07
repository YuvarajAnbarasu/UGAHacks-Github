# RoomPlan Metal Crash Fix (tonemapLUT / fsSurfaceShadow)

## The error

```
failed assertion `Draw Errors Validation
Fragment Function(realitykit::fsSurfaceShadow): incorrect type of texture (MTLTextureType2D) 
bound at Texture binding at index 14 (expect MTLTextureType1D) for tonemapLUT[0].'
```

This is a **Metal API Validation** assertion inside Apple's RealityKit. It triggers when RoomPlan is running and the debug layer validates shader bindings. The app is killed by `SIGABRT` even though the renderer might work fine without validation.

## Required step: Disable Metal API Validation (for Run)

So that the app can scan the room without freezing/crashing:

1. In Xcode: **Product → Scheme → Edit Scheme...**
2. Select **Run** in the left sidebar.
3. Open the **Diagnostics** tab.
4. **Uncheck "Metal API Validation"**.
5. Close the scheme editor and run the app again.

Scanning should then complete and you can export the room (USDZ) and use the data.

## What we changed in code

- **RealityResourceManager** no longer imports RealityKit/ARKit, so during room scan our app does not load RealityKit; only RoomPlan does. That avoids duplicate shader library registration and reduces the chance of texture binding conflicts.
- **Scanner delay** increased to 1.5s before the RoomPlan view is created, so any previous AR/Metal use can tear down first.
- **“Preparing scanner…”** state so the RoomPlan Metal context is created only after that delay.

## Release builds

Metal API Validation is typically **off** in Release. So archive/TestFlight/App Store builds usually do not hit this assertion; the fix above is mainly for **Run (Debug)**.
