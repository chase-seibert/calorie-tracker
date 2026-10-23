# Magic recommendations

Magic recommends up to four foods, saved meals, or repeated sets. Before the
first food is logged today, it includes the current local-time band and any
earlier bands that have started today. After a food has been logged, it uses
only the current band. Its purpose is to make recurring routines fast without
turning an inferred set into a saved meal.

## Time and history window

Magic assigns the current local time to one band:

- Breakfast: 5:00 AM through 10:59 AM.
- Lunch: 11:00 AM through 2:59 PM.
- Dinner: 3:00 PM through 4:59 AM.

Before 5:00 AM, dinner is the only active band. From 5:00 AM to 10:59 AM,
breakfast is active. From 11:00 AM to 2:59 PM, lunch and breakfast are used,
in that order. From 3:00 PM onward, dinner, lunch, and breakfast are used, in
that order. Earlier bands are included only while there are no food entries in
today's diary.

Each selected band uses the 10 complete local calendar days immediately before
today. Today is never part of historical counts, scores, combination cohesion,
or recency tie-breakers. Calorie-adjustment entries are ignored. Within each
historical day, only entries whose logging time belongs to that band are
considered.

## Item identity

A normal food is identified by its stable food ID. A saved meal is identified
by its saved-meal ID and is treated as one recommendation item. Foods and saved
meals with similar names are not merged. A deleted saved meal cannot become a
recommendation because it can no longer be resolved to a current item.

## Foods or meals logged today

Logging an item today does not automatically hide it from Magic. Instead, it
adds a stronger historical-confidence requirement:

1. Magic checks all of today's diary entries, regardless of which time band
   they were logged in.
2. For every matching item logged today, Magic looks in the current band's
   10-day history.
3. The item remains eligible only if at least one historical day contains two
   or more matching entries in that band.
4. Today's entries do not help satisfy the two-logs-on-one-day requirement.

This gate applies both to a singleton and to an item inside a set. If any member
of a proposed set was logged today but lacks a qualifying historical double,
the whole set is excluded rather than partially suggested.

Examples:

- Cappuccino was logged today and twice during breakfast six days ago: it can
  appear in a breakfast singleton or set.
- Cappuccino was logged today and once on each of two prior breakfast days: it
  does not appear, because neither day contains two cappuccino logs.
- Cappuccino was not logged today and appeared on two prior breakfast days: it
  is eligible under the normal singleton rule below.

## Singleton selection

For an item not logged today, a singleton requires presence on at least two
distinct historical days in the current time band. Multiple entries on one day
count once for this normal day-frequency score.

For an item logged today, the same-day historical repeat rule replaces the
normal two-distinct-days eligibility check. A single historical day with two
matching entries is sufficient, although its singleton score is still based on
one distinct day.

A singleton's score is the number of distinct historical days on which the item
appeared in the selected band. Its most recent historical entry supplies the
recency tie-breaker and the current display data.

## Set selection

Magic considers sets of two and three distinct items. For every historical day,
it takes the distinct items observed in the selected band and generates all
two-item and three-item combinations. Items only need to occur on the same day
and in the same band; they do not need to be adjacent or logged within a smaller
minute interval.

A set is eligible when:

- The complete combination appeared on at least two distinct historical days.
- Its cohesion is at least 0.60. Cohesion is the combination's day count divided
  by the largest individual day count among its members.
- Every member logged today passes the two-logs-on-one-historical-day gate.

The set score is:

`combination day count + 1.25 + 0.25 × (item count − 2)`

This gives a reliable pair a 1.25-point set boost and a reliable three-item set
a 1.50-point boost. Adding a set creates separate ordinary diary entries; Magic
does not create a saved meal or grouped diary object.

## Ranking and result limit

Within each band, singleton and set candidates share one ranking. Magic sorts
them by:

1. Score, highest first.
2. Most recent qualifying historical observation, newest first.
3. Item count, larger set first.
4. Stable suggestion ID, ascending, for deterministic final ordering.

Magic merges band results by taking the highest-ranked suggestion from the
current band, then each earlier band in order, and repeating that cycle until
four suggestions are selected or all bands are empty. Duplicate suggestions
shared by multiple bands appear once. This keeps the current period prominent
while making room for routines from periods that have passed.

## UI refresh behavior

Magic calculates a snapshot when the mode is initially shown or explicitly
selected. The default search-first Log Food sheet also uses that snapshot as its
content before the user types. Typing replaces it with search results.

Adding a suggestion does not immediately recalculate or remove rows. The add
button shows its green confirmation checkmark while the visible list stays
stable. Closing and reopening the pane, or selecting Magic again, creates a new
snapshot using the then-current diary.

## Current limitations

- Identity is ID-based rather than name-based, so equivalent foods from
  different sources remain separate.
- Set inference uses same-day, same-band co-occurrence and does not infer a
  narrower meal boundary inside a time band.
- Quantities affect what is logged but not recommendation eligibility or rank.
- Dinner intentionally spans both late evening and the hours before 5:00 AM.
