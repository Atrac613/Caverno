# Pantry Tracker

A small Flutter app for keeping track of what is in the kitchen.

## Getting started

```bash
flutter pub get
flutter run
```

## Status

- [x] PT-4 Barcode scanning (shipped in 0.3)
- [x] PT-7 Offline storage with drift (shipped in 0.4)
- [ ] PT-9 Shared household lists: in progress, see pull request #41
- [ ] PT-11 Notification permission redesign: blocked on the design review
- [ ] PT-12 Expiry reminders
- [ ] PT-15 Recipe suggestions

## Next up

When PT-9 merges, start PT-12 (expiry reminders). It does not depend on the
permission redesign, because the first version only shows in-app banners.
Recipe suggestions wait until after 1.0.

## License

MIT
