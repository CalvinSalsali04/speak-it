import { OfferCodeCipher } from "./crypto.js";
import {
  ReferralDatabase,
  ReferralDatabaseError,
  type IdentityRow,
  type ReferralRow
} from "./database.js";
import type {
  AppleGateway,
  AuthenticatedIdentity,
  ReferralConfiguration
} from "./types.js";

export class ReferralService {
  constructor(
    private readonly database: ReferralDatabase,
    private readonly apple: AppleGateway,
    private readonly configuration: ReferralConfiguration,
    private readonly codeCipher: OfferCodeCipher
  ) {}

  authenticate(identity: AuthenticatedIdentity): IdentityRow {
    if (!isUUID(identity.appAccountToken) || identity.credential.length < 32) {
      throw new ReferralServiceError("unauthorized", "The referral identity is invalid", 401);
    }
    try {
      return this.database.authenticateOrCreate(
        identity.appAccountToken.toLowerCase(),
        identity.credential
      );
    } catch (error) {
      throw mapDatabaseError(error);
    }
  }

  createInvite(identity: AuthenticatedIdentity): {
    code: string;
    inviteURL: string;
  } {
    const account = this.authenticate(identity);
    const referral = this.database.getOrCreateReferral(account.appAccountToken);
    const url = new URL(this.configuration.publicInviteBaseURL);
    url.searchParams.set("ref", referral.code);
    return { code: referral.code, inviteURL: url.toString() };
  }

  acceptInvite(identity: AuthenticatedIdentity, code: string): {
    referralCode: string;
    redemptionURL: string;
  } {
    if (!isReferralCode(code)) {
      throw new ReferralServiceError("invalid_request", "A valid referral code is required", 400);
    }
    const account = this.authenticate(identity);
    try {
      this.database.acceptReferral(code, account.appAccountToken);
    } catch (error) {
      throw mapDatabaseError(error);
    }
    return {
      referralCode: code,
      redemptionURL: this.redemptionURL(this.configuration.friendCustomCode)
    };
  }

  async verifyTransaction(
    identity: AuthenticatedIdentity,
    signedTransaction: string,
    referralCode?: string
  ): Promise<{
    accepted: boolean;
    referralQualified: boolean;
    rewardCreated: boolean;
    duplicate: boolean;
  }> {
    const account = this.authenticate(identity);
    const transaction = await this.apple.verifyTransaction(signedTransaction);

    if (transaction.appAccountToken &&
        transaction.appAccountToken.toLowerCase() !== account.appAccountToken) {
      throw new ReferralServiceError(
        "transaction_owner_conflict",
        "The verified App Store transaction belongs to another referral identity",
        409
      );
    }
    if (!transaction.appAccountToken) {
      await this.apple.bindAppAccountToken(transaction, account.appAccountToken);
      transaction.appAccountToken = account.appAccountToken;
    }

    const referral = referralCode
      ? this.database.referralByCode(referralCode)
      : null;
    if (referralCode) {
      this.validateQualifyingReferral(
        referral,
        account,
        transaction.originalTransactionId,
        transaction.transactionId
      );
      this.validateFriendOffer(referral!, transaction);
    }

    if (this.database.transactionExists(transaction.transactionId)) {
      if (referral) {
        if (referral.status === "qualified") {
          return {
            accepted: true,
            referralQualified: true,
            rewardCreated: false,
            duplicate: true
          };
        }
        return this.qualifyReferral(referral, transaction.transactionId, true);
      }
      return {
        accepted: true,
        referralQualified: false,
        rewardCreated: false,
        duplicate: true
      };
    }

    try {
      this.database.recordTransactionIdentity(
        account.appAccountToken,
        transaction.originalTransactionId,
        transaction.productId
      );
      this.database.insertTransaction({
        transactionID: transaction.transactionId,
        originalTransactionID: transaction.originalTransactionId,
        appAccountToken: account.appAccountToken,
        productID: transaction.productId,
        offerIdentifier: transaction.offerIdentifier,
        offerType: transaction.offerType,
        environment: transaction.environment,
        expiresAt: transaction.expiresDate,
        revocationAt: transaction.revocationDate,
        signedAt: transaction.signedDate
      });
    } catch (error) {
      throw mapDatabaseError(error);
    }

    const isRewardRedemption = [
      this.configuration.firstRewardOfferIdentifier,
      this.configuration.rewardMonthlyPromotionalOfferIdentifier,
      this.configuration.rewardAnnualPromotionalOfferIdentifier
    ].includes(transaction.offerIdentifier ?? "");
    if (isRewardRedemption && !transaction.revocationDate) {
      this.database.markRewardRedeemed(
        account.appAccountToken,
        transaction.transactionId,
        transaction.productId
      );
    }

    if (!referral) {
      return {
        accepted: true,
        referralQualified: false,
        rewardCreated: false,
        duplicate: false
      };
    }

    return this.qualifyReferral(referral, transaction.transactionId, false);
  }

  private validateFriendOffer(referral: ReferralRow, transaction: Awaited<ReturnType<AppleGateway["verifyTransaction"]>>): void {
    const qualifyingProducts = [
      this.configuration.monthlyProductID,
      this.configuration.annualProductID
    ];
    const acceptanceGracePeriod = 5 * 60 * 1_000;
    if (transaction.revocationDate ||
        !transaction.expiresDate || transaction.expiresDate <= Date.now() ||
        !transaction.purchaseDate ||
        !referral.acceptedAt ||
        transaction.purchaseDate < referral.acceptedAt - acceptanceGracePeriod ||
        transaction.offerIdentifier !== this.configuration.friendOfferIdentifier ||
        transaction.offerType !== 3 ||
        !qualifyingProducts.includes(transaction.productId)) {
      throw new ReferralServiceError(
        "friend_offer_not_verified",
        "Apple did not verify the one-month friend offer for this referral",
        422
      );
    }
  }

  private qualifyReferral(
    referral: ReferralRow,
    transactionID: string,
    duplicate: boolean
  ): {
    accepted: boolean;
    referralQualified: boolean;
    rewardCreated: boolean;
    duplicate: boolean;
  } {
    this.database.qualifyReferral(referral, transactionID);
    const yearStart = Date.UTC(new Date().getUTCFullYear(), 0, 1);
    const rewardCount = this.database.rewardsInYear(referral.referrerToken, yearStart);
    const rewardCreated = rewardCount < this.configuration.annualRewardCap;
    if (rewardCreated) {
      this.database.createReward(referral.id, referral.referrerToken);
    }
    return {
      accepted: true,
      referralQualified: true,
      rewardCreated,
      duplicate
    };
  }

  status(identity: AuthenticatedIdentity): {
    successfulReferrals: number;
    availableRewards: number;
    claimedRewards: number;
  } {
    const account = this.authenticate(identity);
    return this.database.referralSummary(account.appAccountToken);
  }

  async claimReward(identity: AuthenticatedIdentity): Promise<
    | { mode: "offer_code"; rewardID: string; redemptionURL: string }
    | { mode: "promotional_offer"; rewardID: string; offer: Awaited<ReturnType<AppleGateway["createPromotionalOffer"]>> }
  > {
    const account = this.authenticate(identity);
    const reward = this.database.nextClaimableReward(account.appAccountToken);
    if (!reward) {
      throw new ReferralServiceError("no_reward", "There is no referral reward ready to claim", 404);
    }

    if (!account.originalTransactionID || !account.latestProductID) {
      const code = this.database.assignOfferCode(reward.id, this.codeCipher);
      if (!code) {
        throw new ReferralServiceError(
          "reward_codes_unavailable",
          "Referral reward codes are temporarily unavailable",
          503
        );
      }
      this.database.markRewardClaimed(reward.id, "offer_code", null);
      return {
        mode: "offer_code",
        rewardID: reward.id,
        redemptionURL: this.redemptionURL(code)
      };
    }

    const offerID = account.latestProductID === this.configuration.annualProductID
      ? this.configuration.rewardAnnualPromotionalOfferIdentifier
      : this.configuration.rewardMonthlyPromotionalOfferIdentifier;
    if (account.latestProductID !== this.configuration.annualProductID &&
        account.latestProductID !== this.configuration.monthlyProductID) {
      throw new ReferralServiceError(
        "reward_not_applicable",
        "Permanent Pro is already active, so a subscription month cannot be added",
        409
      );
    }
    const offer = await this.apple.createPromotionalOffer(
      account.latestProductID,
      offerID,
      account.appAccountToken
    );
    this.database.markRewardClaimed(reward.id, "promotional_offer", account.latestProductID);
    return { mode: "promotional_offer", rewardID: reward.id, offer };
  }

  importFirstRewardCodes(codes: string[], offerIdentifier: string): number {
    if (offerIdentifier !== this.configuration.firstRewardOfferIdentifier) {
      throw new ReferralServiceError(
        "wrong_offer",
        "The code batch does not belong to the configured first-reward offer",
        422
      );
    }
    return this.database.importOfferCodes(codes, offerIdentifier, this.codeCipher);
  }

  private validateQualifyingReferral(
    referral: ReferralRow | null,
    friend: IdentityRow,
    friendOriginalTransactionID: string,
    friendTransactionID: string
  ): void {
    if (!referral || referral.friendToken !== friend.appAccountToken ||
        !["accepted", "qualified"].includes(referral.status)) {
      throw new ReferralServiceError(
        "referral_not_accepted",
        "This transaction is not attached to an accepted referral invite",
        409
      );
    }
    if (referral.status === "qualified" &&
        referral.friendTransactionID !== friendTransactionID) {
      throw new ReferralServiceError(
        "invite_already_used",
        "This invite has already qualified with another transaction",
        409
      );
    }
    const referrer = this.database.identity(referral.referrerToken);
    if (referrer?.originalTransactionID === friendOriginalTransactionID) {
      throw new ReferralServiceError(
        "self_referral",
        "The same App Store subscription can’t be both sides of a referral",
        409
      );
    }
  }

  private redemptionURL(code: string): string {
    const url = new URL("https://apps.apple.com/redeem");
    url.searchParams.set("ctx", "offercodes");
    url.searchParams.set("id", this.configuration.appStoreID);
    url.searchParams.set("code", code);
    return url.toString();
  }
}

export class ReferralServiceError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: number
  ) {
    super(message);
  }
}

function mapDatabaseError(error: unknown): ReferralServiceError {
  if (error instanceof ReferralDatabaseError) {
    return new ReferralServiceError(
      error.code,
      error.message,
      error.code === "unauthorized" ? 401 : 409
    );
  }
  throw error;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isReferralCode(value: string): boolean {
  return /^[A-Za-z0-9_-]{8,80}$/.test(value);
}
