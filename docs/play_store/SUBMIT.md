# Play production submit

Complete after Internal testing smoke ([INTERNAL_TEST.md](INTERNAL_TEST.md)).

## Pre-submit
- [ ] Listing ([LISTING.md](LISTING.md)) + graphics
- [ ] Privacy policy URL: https://legal.allinonepos.app
- [ ] Data safety ([DATA_SAFETY.md](DATA_SAFETY.md))
- [ ] Content rating questionnaire
- [ ] Target audience / news apps declarations as applicable
- [ ] AAB on a release track (Production or staged rollout)
- [ ] **Staged rollout** (e.g. 20%) for first public version

## After publish
- [ ] Bump `pubspec.yaml` `+BUILD` before next upload
- [ ] Watch Play ANRs/crashes + Sentry 48h

## Rejected?
Common: missing privacy URL, incomplete Data safety, debug-signed AAB (should be impossible after `key.properties` wiring), Play Billing policy confusion (clarify external license for POS).
