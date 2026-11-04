# App Store screenshots (iPhone only)

- `raw/` – untouched simulator captures of the seeded demo server (`tools/seed_demo.py`; iPhone 17 Pro, 1206×2622, light mode, 9:41 status bar), taken by the `ScreenshotTests` UI test. `raw-demo/` holds an older demo set from before the redesign.
- `iphone-6.9/` (1320×2868, required) and `iphone-6.5/` (1284×2778) – the finished slides, ten each. Upload in filename order.
- `frame.swift` + `assets/` – the framer (forest-green ground, cream captions, photographic iPhone frame), adapted from the ShelfHead set.
- `generate.sh` – rebuilds every slide and holds the captions:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./generate.sh`

To retake every shot: `IOS/scripts/run-ui-tests.sh --screenshots` (needs Docker). It starts and seeds a throwaway server, sets the status bar and light mode, runs `RecipeManagerUITests/ScreenshotTests`, writes `raw/` and `docs/screenshots/ios` (half size, 600×1304), then runs `generate.sh`. Check the results by eye before committing.
