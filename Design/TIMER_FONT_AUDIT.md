# Dynamic Island timer-font audit

Date: 2026-07-18

> Resolution update: the compact/minimal views now instantiate
> `CompactTimerPet` with the direct bitmap-color-font path. `PetIslandTimerPets.ttc`
> is copied only into the widget extension, and the system timer's changing
> final digit is the visible pet glyph. The compact layout is 32 pt leading
> content with an empty trailing region. Sprite frames are stored as intact
> 96-ppem PNG strikes in the Apple `sbix` table.

## Result

The original COLRv0 implementation split every sprite color into many tiny
TrueType contours. CoreText dropped some contours at compact Dynamic Island
sizes, creating transparent holes and apparently displaced pixels. A single
Shepherd frame lost 445 of 1010 visible grid cells in a controlled render.

`build_live_activity_timer_fonts.py` now stores every frame as one intact PNG
in an Apple `sbix` strike. The base `glyf` digit remains a monochrome silhouette
for renderers that ignore bitmap strikes. Simulator QA confirms that the color
bitmap path remains active after the app process terminates.

## Bundle and table verification

A clean generic-iOS build produced:

`PetIslandLiveActivity.appex/`

- `PetIslandTimerPets.ttc`
- `PetIslandTimerParrotClassic.ttf`
- `PetIslandTimerRunA.ttf`
- `PetIslandTimerRunB.ttf`
- `PetIslandTimerSleep.ttf`

The built TTC SHA-256 matched the source TTC byte-for-byte. Its collection
header is valid and contains 19 faces. Every face has the required `cmap`,
`head`, `hhea`, `hmtx`, `maxp`, `name`, `OS/2`, `post`, `glyf`, `loca`, and
`sbix` tables. HarfBuzz/fontconfig reports all 19 expected PostScript names,
including `PetIslandTimerDogShepherd`, `PetIslandTimerParrotClassic`, and
`PetIslandTimerPenguinRockhopper`. The character map covers ASCII `0...9` and
colon.

After the `sbix` change:

- the normal color rendering preserves the complete pixel grid;
- stripping `sbix` leaves a visible monochrome pet silhouette;
- all 19 TTF faces and the TTC regenerate successfully.

## Registration issue

Both `Info.plist` files list the TTC in `UIAppFonts`, and the TTC is present in
the extension bundle. However, the manual process registration currently loads
only `PetIslandTimerParrotClassic.ttf`. The other 18 faces depend entirely on
implicit `UIAppFonts` registration of a collection.

WidgetKit executes the extension in a process separate from the main app.
Register the TTC explicitly with `.process`, and resolve it from the extension
bundle. Apple documents that the registration API accepts font collections and
makes their descriptors discoverable in the calling process:

- [CTFontManagerRegisterFontURLs](https://developer.apple.com/documentation/coretext/ctfontmanagerregisterfonturls%28_%3A_%3A_%3A_%3A%29)
- [Adding a custom font to your app](https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app)
- [Widget extension process discussion](https://developer.apple.com/forums/thread/671476)

Suggested replacement for `LiveTimerFontRegistry`:

```swift
private final class LiveTimerFontBundleToken: NSObject {}

private enum LiveTimerFontRegistry {
    private static let registeredPostScriptNames: Set<String> = {
        let bundle = Bundle(for: LiveTimerFontBundleToken.self)
        guard let url = bundle.url(
            forResource: "PetIslandTimerPets",
            withExtension: "ttc"
        ) else { return [] }

        var unmanagedError: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &unmanagedError
        ) else {
            // "Already registered" is harmless; descriptors below are the
            // source of truth rather than the Boolean result.
            return descriptors(in: url)
        }
        return descriptors(in: url)
    }()

    static func isAvailable(_ postScriptName: String) -> Bool {
        registeredPostScriptNames.contains(postScriptName)
    }

    private static func descriptors(in url: URL) -> Set<String> {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor] ?? []
        return Set(descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
        })
    }
}
```

## View wiring and public timer technique

Apple supports dynamic timer text in widgets and Live Activities. WidgetKit
updates the timer without an extension-owned repeating timer:

- [Displaying dynamic dates in widgets](https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates)
- [`Text.init(timerInterval:pauseTime:countsDown:showsHours:)`](https://developer.apple.com/documentation/swiftui/text/init%28timerinterval%3Apausetime%3Acountsdown%3Ashowshours%3A%29)

The public timer-font technique assigns animation frames to changing timer
digits, makes the timer use the custom font, fixes its intrinsic size, and clips
the string so only the final digit is visible. More elaborate versions add GSUB
ligatures for complete timer strings. The current generated font has no GSUB
table; it uses the simpler trailing-digit clipping variant, which is sufficient
because each ASCII digit has the same one-em advance.

The code should use the explicit interval initializer rather than the less
controlled `Text(date, style: .timer)` overload:

```swift
Text(
    timerInterval: timerStart...timerEnd,
    countsDown: false,
    showsHours: true
)
    .font(.custom(fontName, fixedSize: max(proxy.size.width, proxy.size.height)))
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: true)
    .frame(
        width: proxy.size.width,
        height: proxy.size.height,
        alignment: .trailing
    )
    .clipped()
    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
```

Then wire `TimerDrivenCompactPet` into the non-sleeping branch of
`CompactPetGlyph`; keep `ActivityAnimatedPet(..., isSleeping: true)` for stale
or luminance-reduced states. Pass the session's `startedAt` and `endsAt` as the
interval bounds. This preserves the current visible safe fallback while making
the experimental timer path reachable.

Do not apply `.monospacedDigit()` after `.font(.custom(...))`; it may replace the
intended digit design. Avoid `minimumScaleFactor` on dynamic timer text because
WidgetKit timer layout can reserve its maximum width. The existing
`fixedSize` + trailing frame + clipping approach intentionally handles that
reserved width.

## Project cleanup after simulator QA

The three experimental mask fonts and the standalone Parrot TTF are no longer
members of either target. Only `PetIslandTimerPets.ttc` is copied into the
widget extension and declared in its `UIAppFonts`; the main app does not bundle
timer-font resources. The generator retains the standalone faces and mask fonts
as engineering artifacts, but they are not shipped in the application bundle.

The timer-font mechanism is a public-API workaround, not an Apple-documented
animation contract. Keep the image-based sleeping fallback and complete
physical-device/AOD QA before enabling it for release.
