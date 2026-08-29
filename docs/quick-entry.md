# System quick entry

VitaChase exposes the same local diary and recommendation data through Home
Screen quick actions, Siri/App Intents, and an interactive widget. No food names,
history, or nutrition data leave the device.

## Home Screen app icon

Touch and hold VitaChase on the Home Screen to see the current Magic
recommendations. Up to four single foods, saved meals, or Magic sets appear with
their calories. Selecting one launches VitaChase, logs every item with its
remembered quantity, and leaves the diary visible without showing a confirmation
dialog.

iOS always launches or resumes an app when a Home Screen icon quick action is
selected. This surface cannot log while keeping the app closed; Siri and widget
buttons provide that behavior.

## Siri and Shortcuts

The app publishes two App Shortcuts:

- “Log cappuccino in VitaChase” logs the most recently used exact-name match
  from Recent. Compound requests such as “Log a cappuccino and feta cheese in
  VitaChase” log each exact Recent match together. Partial matches can be
  resolved by Siri. If every requested name cannot be resolved from Recent,
  nothing is logged.
- “How many calories do I have left in VitaChase?” reports the daily goal minus
  today's food, meal, adjustment, and alcohol calories. It asks the user to set
  a goal when none exists.

Both actions are also available in the Shortcuts app. Background logs use the
remembered quantity or portion and are synchronized to HealthKit the next time
the main app performs its normal health sync.

## Home and Lock Screen widget

Add “VitaChase Quick Log” from the widget gallery. The small Home Screen widget
shows one suggestion, the medium widget shows up to three, and the large widget
shows up to eight. Circular and rectangular Lock Screen variants log the leading
suggestion. A button logs directly without opening the app. After a successful
write, the widget reloads and shows a green “Logged” receipt for ten minutes.

“VitaChase Calories Left” is a separate widget for the Home or Lock Screen. It
shows the remaining (or over-goal) calories and progress against the daily goal.
Diary changes reload both widget types, and the calories widget schedules a new
entry at the next local midnight.

The widget prefers current Magic recommendations and falls back to Recent when
Magic has no eligible result. Its timeline precomputes the next breakfast,
lunch, and dinner transitions at 5 AM, 11 AM, and 3 PM local time, so the visible
choices change at the same boundaries as the in-app Magic mode.

## Shared storage

The app and widget use App Group `group.com.cseibert.CalorieTracker`. On the
first app launch after upgrading, VitaChase copies the existing Application
Support diary into the group container and leaves the legacy file intact as a
recovery copy. All subsequent writes use the shared copy.
