# Submit for App Review → release

Complete only after TestFlight smoke ([TESTFLIGHT_SMOKE.md](TESTFLIGHT_SMOKE.md)) passes.

## Pre-submit
- [ ] Listing fields filled ([LISTING.md](LISTING.md))
- [ ] Privacy Policy URL live: https://legal.allinonepos.app
- [ ] App Privacy nutrition labels ([PRIVACY_NUTRITION.md](PRIVACY_NUTRITION.md))
- [ ] Screenshots uploaded (iPhone 6.7" + 6.1"; iPad if still universal)
- [ ] Review notes pasted ([REVIEW_NOTES.md](REVIEW_NOTES.md)) with demo credentials filled
- [ ] Build selected (Processed in Connect)
- [ ] Export compliance: uses exempt encryption (matches `ITSAppUsesNonExemptEncryption=false`)
- [ ] **Manual release** selected (not auto) for first public version

## Submit
App Store Connect → the iOS version → **Add for Review** → **Submit to App Review**.

## After approval
- [ ] Verify listing on App Store (region availability)
- [ ] Tap **Release this version** (manual)
- [ ] Bump `pubspec.yaml` build number for the next upload (`1.0.0+N`)
- [ ] Watch Sentry for 48h

## Rejected?
Common fixes: missing privacy URL, incomplete demo login, unclear non-IAP licensing (clarify in Review Notes), missing iPad screenshots while iPad is supported.
