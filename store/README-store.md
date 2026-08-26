# App Store Connect listing copy

Character counts verified against Apple's limits.

| Field | Limit | Used | File |
|---|---|---|---|
| App Name | 30 | 10 | `Squad Picker` |
| Subtitle | 30 | 30 | `subtitle.txt` |
| Promotional Text | 170 | 163 | `promo.txt` |
| Description | 4000 | 1861 | `description.txt` |
| Keywords | 100 | 98 | `keywords.txt` |

Promotional text can be updated without submitting a new build — useful for
gameweek-timely messaging (deadline reminders, wildcard weeks).

Keywords deliberately avoid repeating words already in the app name and
subtitle (fantasy, football, squad, builder, picker), since Apple indexes those
fields too and repeats waste the 100 characters.

## Trademark note

Apple rejected the first submission under Guideline 5.2.1: the metadata
referenced Fantasy Premier League without authorisation. The app was renamed
from "FPL Picker" to "Squad Picker", and "premier", "league" and "epl" were
removed from the keywords and the description. Public-facing metadata now
names no league, competition or fantasy provider. Do not reintroduce those
terms without a licence.

`review-notes.txt`, `third-party-services.md` and `regulated-and-ip.txt` are
private to App Review rather than public metadata, so they still name the data
source — App Review needs to know where the data comes from.
