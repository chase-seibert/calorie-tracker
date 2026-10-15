# Task 196 — unified food customization screens

Captured from the production SwiftUI views on the iPhone 17 Pro simulator running iOS 27.0. The screenshot matrix test passed with a clean reset fixture. All images are unaltered 1206 × 2622 PNGs. See the [side-by-side comparison](comparison.html) and [verification notes](verification.md).

| Screen | Screenshot |
| --- | --- |
| USDA food | [usda-portioned-log.png](usda-portioned-log.png) |
| Open Food Facts packaged food | [off-packaged-log.png](off-packaged-log.png) |
| Chase Food customization | [yum-chase-configured-log.png](yum-chase-configured-log.png) |
| Saved meal | [saved-meal-log.png](saved-meal-log.png) |

The saved-meal capture shows the meal icon and title without a separate Edit link, read-only ingredient quantities with Customize links, swipe-only delete actions hidden by default, and the Log Meal action. Rename remains in the item menu. Macro labels and values share a baseline. The UI tests exercise renaming through the menu, component quantity editing, swipe-to-delete confirmation, and imported/photo-review child editors.
