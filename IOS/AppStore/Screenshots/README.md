# App Store screenshots (iPhone only)

- `raw/` – untouched simulator captures of a real library (iPhone 18 Pro, 1206×2622, light mode, 9:41 status bar). `raw-demo/` holds the earlier set from the seeded demo server (`tools/seed_demo.py`), which also has collections, meal plan and shopping shots.
- `iphone-6.9/` (1320×2868, required) and `iphone-6.5/` (1284×2778) – the finished slides, eight each. Upload in filename order.
- `frame.swift` + `assets/` – the framer (forest-green ground, cream captions, photographic iPhone frame), adapted from the ShelfHead set.
- `generate.sh` – rebuilds every slide and holds the captions:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./generate.sh`

To retake a raw shot: seed a fresh server, `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3`, then `xcrun simctl io <udid> screenshot raw/NN-name.png`.
