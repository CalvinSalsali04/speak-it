# App Store Connect pricing status — September 9, 2026

Verified in the signed-in App Store Connect UI for SpeakIt (6803372596).

- Monthly product `com.calvinwak.SpeakIt.pro.monthly` (6803384549): changed the United States starting price from USD 1.99 to USD 2.99, confirmed, then reopened Starting Price and verified USD 2.99. Other storefront prices were preserved, including Canada CAD 2.99.
- Annual product `com.calvinwak.SpeakIt.pro.annual` (6803385342): verified existing United States starting price USD 14.99; Canada CAD 19.99. No price mutation needed.
- Group 22321683: changed annual and monthly to the same service level (1), saved and verified. Both provide identical Pro access.
- Added and verified missing English (Canada) group localization, display name Speak It Pro, using the existing app name.
- Both products and the group still show Prepare for Submission. First subscriptions must accompany a new app version. No submission or actual purchase was performed.

## Incomplete

The annual pricing page showed only Starting Price, with no future schedule. Add Pricing exposed introductory offers, offer codes and promotional offers, but no price-change scheduling control. The intended October 22 increase to USD 29.99 and price preservation are NOT configured or verified. Do not treat the local sale deadline or standard-price comparison as evidence of an Apple schedule.

Automatic approval review rejected recalculating all 175 regional monthly prices as broader than the authorized US-dollar change. Used the permitted individual US storefront edit instead. A worldwide recalculation requires explicit approval; other storefronts remain at their previous prices.

End-to-end StoreKit Sandbox purchase, renewal and restore testing remains incomplete. App Store metadata verification alone does not demonstrate those flows work.

## Scheduling research follow-up

Apple's [subscription pricing guide](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions)
documents **Subscription Prices → + → Plan Subscription Price Change**, then
region, start date and price, followed by a separate choice to preserve existing
subscriber prices. It allows one future change per region and billing plan.
This is different from editing Starting Price or creating an offer. The guide
does not establish that Prepare for Submission caused the missing control.
The account-specific cause remains unverified; do not assume approval alone
will resolve it. No schedule or preservation setting was changed in this pass.

A read-only browser follow-up reached the existing SpeakIt TestFlight page.
Distribution did not load; one reload redirected to Apple's authentication
widget. The live schedule control could not be inspected further in that
expired session. No price, subscription, tester, or submission was changed.
