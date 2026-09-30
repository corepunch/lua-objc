# Adventure Arena onboarding

First-launch tour for kids and parents. One idea per screen, Skip always
visible, a first story waiting at the end.

## Screens

1. **Welcome** — what the arena is.
2. **How you play** — type, tap a suggestion, swipe the compass.
3. **Who is playing** — Kids, Parents, or Together.
4. **Worlds you like** — catalog genres; horror is hidden for kids.
5. **Ready** — a recommended first story, or browse the library.

## References

- Kree8 onboarding boards collected by [Satya](https://x.com/heysatya_/status/2104913127435538579):
  one value per screen, Skip + Next, interest tiles, a first action.
- FlightElite board from the same set: dark hero, progress, preference chips.
- [Mobile onboarding practices, 2026](https://www.lowcode.agency/blog/mobile-onboarding-best-practices):
  value in the first minute, skip is not a failure, personalize before signup.
- Diskmap’s first-launch sheet in this repo: complete-once flag, large sheet,
  Skip always available.

## Persistence

`adventure-arena/onboarding.json` stores `completed`, `audience`, `interests`,
and `firstStory`. There is no migration: a new format simply replaces the old
file.
