# Speak It referral service

This service makes **Give a month. Get a month.** an Apple-verified program
without requiring a visible Speak It account. The iPhone app generates a random
UUID plus a separate credential in Keychain, includes the UUID as StoreKit's
`appAccountToken`, and sends App Store-signed transaction JWS values here.

The service never grants Pro itself. Apple remains the entitlement authority:

1. The friend accepts an invite and redeems Apple's one-month offer code.
2. The service verifies the signed transaction with Apple's root certificates.
3. A qualifying transaction closes the referral and creates one ledger reward.
4. A referrer with a subscription receives a server-signed promotional offer.
5. A referrer without one receives an encrypted, one-time Apple offer code.

## Protections

- One accepted referral per anonymous friend identity.
- One reward per referral and per verified transaction.
- The same original Apple transaction cannot own both sides of a referral.
- The friend transaction must be an active offer-code transaction for an
  allowed Speak It subscription, purchased after the invite was accepted.
- Revoked, expired, replayed, ordinary-price, and wrong-offer transactions do
  not qualify.
- A referrer can earn at most 12 rewards per UTC calendar year.
- Cancelling redemption does not lose a reward; the same assigned one-time code
  or a fresh promotional-offer signature can be requested again.
- One-time offer codes are encrypted at rest with AES-256-GCM. Credentials and
  raw offer codes are never logged.

## Apple configuration

Create the following under the monthly/annual products in the same subscription
group. Identifiers must match the environment variables exactly.

| Purpose | Apple mechanism | Identifier/code | Eligibility and duration |
| --- | --- | --- | --- |
| Friend's month | Offer Code | offer `speakit_referral_friend_month`, custom code `SPEAKITFRIEND` | New subscribers; 1 month free |
| First referrer reward | Offer Code batch | offer `speakit_referral_reward_month` | New, existing, and expired; 1 month free; generate one-time-use codes |
| Monthly subscriber reward | Promotional Offer | `speakit_referral_reward_monthly` | Existing/expired monthly subscribers; 1 month free |
| Annual subscriber reward | Promotional Offer | `speakit_referral_reward_annual` | Existing/expired annual subscribers; 1 month free |
| Founder month | Offer Code | custom code `CALVINMONTH` | Intended founder eligibility; 1 month free |
| Founder year | Offer Code | custom code `CALVINYEAR` | Intended founder eligibility; 1 year free |

Create an Apple In-App Purchase signing key, keep the `.p8` private key outside
the repository, and download Apple's current root certificates. The same key is
used by the official App Store Server Library to call the App Store Server API
and sign StoreKit promotional offers.

The service uses Apple's Set App Account Token endpoint when a transaction was
started in the App Store redemption sheet and therefore arrived without the
app's anonymous token.

## Run locally

Requires Node 22.5 or newer.

```sh
cp .env.example .env
npm ci
npm test
npm run build
set -a
. ./.env
set +a
npm start
```

`GET /health` returns `{"status":"ok"}`. A direct host run defaults to
`127.0.0.1`; expose it through a TLS reverse proxy. The Docker image sets
`HOST=0.0.0.0` so the hosting platform's private ingress can reach the container.

Generate the 32-byte code encryption key with:

```sh
openssl rand -base64 32
```

Generate the administrator token with:

```sh
openssl rand -base64 48
```

## Import one-time reward codes

Download the one-time-use code values from App Store Connect, then import them
over a private operator connection. Do not put the JSON file in the repository.

```sh
curl --fail-with-body https://referrals.speakitapp.ca/v1/admin/offer-codes/import \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"offerIdentifier":"speakit_referral_reward_month","codes":["CODE-ONE","CODE-TWO"]}'
```

The import is idempotent. Codes are encrypted before the transaction commits.
Monitor the unassigned-code count operationally and replenish before it reaches
zero; an empty pool returns a retriable 503 and does not consume the reward.

## Production deployment

- Put the service behind HTTPS and host-level per-IP and per-route rate limits.
- Strip untrusted forwarding headers at the reverse proxy.
- Mount the `.p8` key and Apple certificates read-only; inject all other secrets
  from the hosting platform's secret manager.
- Mount `/data` on an encrypted persistent volume, set
  `DATABASE_PATH=/data/referrals.sqlite`, and back it up. SQLite WAL assumes one
  service instance. Migrate the ledger to PostgreSQL before horizontal scaling.
- Alert on 5xx responses, App Store verification failures, exhausted offer-code
  inventory, and failed backups. Never log request bodies or authorization
  headers.
- Exercise the complete flow in Apple's Sandbox before setting
  `SPEAKIT_REFERRAL_API_URL` in the Release build.

The public promise is deliberately gated. `SpeakItReferralAPIURL` is empty in
the checked-in build settings, so the app shows the ordinary **Share Speak It**
row until a production URL is injected. `Website/assets/stage.js` has a separate
`REFERRALS_ENABLED` switch to turn on only after the same end-to-end check.

## HTTP surface

| Method and path | Purpose |
| --- | --- |
| `POST /v1/referrals/invite` | Create or reuse the caller's open invite |
| `POST /v1/referrals/accept` | Attach a friend identity before Apple redemption |
| `POST /v1/transactions/verify` | Verify and ledger an App Store-signed JWS |
| `GET /v1/referrals/status` | Return successful invites and reward counts |
| `POST /v1/rewards/claim` | Return a one-time code or signed promotional offer |
| `POST /v1/admin/offer-codes/import` | Import first-reward code inventory |

Public routes use `X-SpeakIt-App-Account-Token` plus a bearer credential. The
admin import uses the independent `ADMIN_TOKEN` only.
