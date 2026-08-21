import { readFileSync } from "node:fs";
import type { ReferralConfiguration } from "./types.js";

export interface ServerConfiguration extends ReferralConfiguration {
  port: number;
  host: string;
  databasePath: string;
  bundleID: string;
  appAppleID: number;
  appleIssuerID: string;
  appleKeyID: string;
  applePrivateKey: string;
  appleRootCertificates: Buffer[];
  adminToken: string;
  codeEncryptionKey: string;
}

export function loadConfiguration(environment = process.env): ServerConfiguration {
  const required = (name: string): string => {
    const value = environment[name]?.trim();
    if (!value) throw new Error(`${name} is required`);
    return value;
  };

  const appAppleID = Number(required("APPLE_APP_ID"));
  if (!Number.isSafeInteger(appAppleID) || appAppleID <= 0) {
    throw new Error("APPLE_APP_ID must be the numeric App Store app ID");
  }
  const certificatePaths = required("APPLE_ROOT_CA_PATHS")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  return {
    port: Number(environment.PORT ?? "8787"),
    host: environment.HOST ?? "127.0.0.1",
    databasePath: environment.DATABASE_PATH ?? "./data/referrals.sqlite",
    publicInviteBaseURL: required("PUBLIC_INVITE_BASE_URL"),
    appStoreID: String(appAppleID),
    bundleID: environment.APPLE_BUNDLE_ID ?? "com.calvinwak.SpeakIt",
    appAppleID,
    appleIssuerID: required("APPLE_ISSUER_ID"),
    appleKeyID: required("APPLE_KEY_ID"),
    applePrivateKey: readFileSync(required("APPLE_PRIVATE_KEY_PATH"), "utf8"),
    appleRootCertificates: certificatePaths.map((path) => readFileSync(path)),
    friendOfferIdentifier: required("APPLE_FRIEND_OFFER_IDENTIFIER"),
    friendCustomCode: required("APPLE_FRIEND_CUSTOM_CODE"),
    firstRewardOfferIdentifier: required("APPLE_REWARD_OFFER_IDENTIFIER"),
    rewardMonthlyPromotionalOfferIdentifier: required(
      "APPLE_REWARD_MONTHLY_PROMO_IDENTIFIER"
    ),
    rewardAnnualPromotionalOfferIdentifier: required(
      "APPLE_REWARD_ANNUAL_PROMO_IDENTIFIER"
    ),
    monthlyProductID: "com.calvinwak.SpeakIt.pro.monthly",
    annualProductID: "com.calvinwak.SpeakIt.pro.annual",
    annualRewardCap: 12,
    adminToken: required("ADMIN_TOKEN"),
    codeEncryptionKey: required("CODE_ENCRYPTION_KEY")
  };
}
