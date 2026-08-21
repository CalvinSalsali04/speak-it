export type ReferralStatus = "created" | "accepted" | "qualified";
export type RewardStatus = "available" | "claimed" | "redeemed";
export type OfferCodeKind = "first_reward";

export interface AppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  appAccountToken?: string;
  productId: string;
  offerIdentifier?: string;
  offerType?: number;
  environment: "Sandbox" | "Production";
  expiresDate?: number;
  revocationDate?: number;
  purchaseDate?: number;
  originalPurchaseDate?: number;
  signedDate?: number;
}

export interface PromotionalOfferSignature {
  productID: string;
  offerID: string;
  keyID: string;
  nonce: string;
  signature: string;
  timestamp: number;
}

export interface AppleGateway {
  verifyTransaction(signedTransaction: string): Promise<AppleTransaction>;
  bindAppAccountToken(transaction: AppleTransaction, appAccountToken: string): Promise<void>;
  createPromotionalOffer(
    productID: string,
    offerID: string,
    appAccountToken: string
  ): Promise<PromotionalOfferSignature>;
}

export interface ReferralConfiguration {
  publicInviteBaseURL: string;
  appStoreID: string;
  friendOfferIdentifier: string;
  friendCustomCode: string;
  firstRewardOfferIdentifier: string;
  rewardMonthlyPromotionalOfferIdentifier: string;
  rewardAnnualPromotionalOfferIdentifier: string;
  monthlyProductID: string;
  annualProductID: string;
  annualRewardCap: number;
}

export interface AuthenticatedIdentity {
  appAccountToken: string;
  credential: string;
}
