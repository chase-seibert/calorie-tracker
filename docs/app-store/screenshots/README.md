# App Store screenshot drafts

These are first-pass, unretouched captures from the iPhone 17 Pro simulator at
1206 × 2622 pixels, with the status bar set to 9:41. Recreate the set with:

```sh
make app-store-screenshots
```

The target seeds the existing date-relative diary fixture, uses UI automation to
capture the six product screens, and exports them with stable filenames. Set
`APP_STORE_SIMULATOR_ID` to use a specific local simulator, or
`APP_STORE_SIMULATOR_OS` to select another installed runtime.

| File | Screen |
|---|---|
| `01-main-diary.png` | Main diary and quick logging |
| `02-magic-suggestions.png` | Time-aware Magic suggestions |
| `03-cheat-day.png` | Diary with cheat day active |
| `04-ai-meal-entry.png` | AI meal description with a selected photo |
| `05-ai-generated-meal.png` | Generated meal estimate ready for review |
| `06-burger-customized-logging.png` | Burger configured as one food with selected cheese and bacon |

The AI form uses a generated salmon-bowl photo stored at
`CalorieTracker/Resources/Fixtures/AppStoreMealPhoto.png`. The Debug simulator
view reads it from Application Support only when the screenshot test enables its
fixture flag. The result screen uses a local meal estimate fixture, so capture
does not call the inference service or send data to a model provider. The cheat
day capture uses a screenshot-only calorie goal so the +1,000 estimate displays
as 650 calories over.

These drafts show native app screens without marketing captions or device
frames. Review the current copy, screenshot order, and image framing before
using them in the release page or App Store listing. In particular, the public
AI claim depends on the release service being enabled and approved.
