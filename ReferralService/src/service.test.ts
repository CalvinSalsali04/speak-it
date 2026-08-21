import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import test from "node:test";
import { OfferCodeCipher } from "./crypto.js";
import { ReferralDatabase } from "./database.js";
import { ReferralService, ReferralServiceError } from "./service.js";
import type {
  AppleGateway,
  AppleTransaction,
  AuthenticatedIdentity,
  PromotionalOfferSignature,
  ReferralConfiguration
} from "./types.js";

const configuration: ReferralConfiguration = {
  publicInviteBaseURL: "https://speakitapp.ca/invite/",
  appStoreID: "123456789",
  friendOfferIdentifier: "friend_month",
  friendCustomCode: "SPEAKITFRIEND",
  firstRewardOfferIdentifier: "first_reward",
  rewardMonthlyPromotionalOfferIdentifier: "reward_monthly",
  rewardAnnualPromotionalOfferIdentifier: "reward_annual",
  monthlyProductID: "com.calvinwak.SpeakIt.pro.monthly",
  annualProductID: "com.calvinwak.SpeakIt.pro.annual",
  annualRewardCap: 12
};

class FakeAppleGateway implements AppleGateway {
  transactions = new Map<string, AppleTransaction>();
  bindings: Array<{ originalTransactionID: string; appAccountToken: string }> = [];

  async verifyTransaction(value: string): Promise<AppleTransaction> {
    const transaction = this.transactions.get(value);
    if (!transaction) throw new Error("unknown fake transaction");
    return { ...transaction };
  }

  async bindAppAccountToken(transaction: AppleTransaction, appAccountToken: string): Promise<void> {
    this.bindings.push({ originalTransactionID: transaction.originalTransactionId, appAccountToken });
  }

  async createPromotionalOffer(
    productID: string,
    offerID: string,
    _appAccountToken: string
  ): Promise<PromotionalOfferSignature> {
    return {
      productID,
      offerID,
      keyID: "KEY",
      nonce: randomUUID(),
      signature: "signed",
      timestamp: Date.now()
    };
  }
}

function makeHarness(): {
  database: ReferralDatabase;
  apple: FakeAppleGateway;
  service: ReferralService;
} {
  const database = new ReferralDatabase(":memory:");
  const apple = new FakeAppleGateway();
  const cipher = new OfferCodeCipher(randomBytes(32).toString("base64"));
  return {
    database,
    apple,
    service: new ReferralService(database, apple, configuration, cipher)
  };
}

function identity(): AuthenticatedIdentity {
  return {
    appAccountToken: randomUUID(),
    credential: randomBytes(32).toString("base64url")
  };
}

function friendTransaction(
  friend: AuthenticatedIdentity,
  originalTransactionId = randomUUID()
): AppleTransaction {
  return {
    transactionId: randomUUID(),
    originalTransactionId,
    appAccountToken: friend.appAccountToken,
    productId: configuration.monthlyProductID,
    offerIdentifier: configuration.friendOfferIdentifier,
    offerType: 3,
    environment: "Sandbox",
    purchaseDate: Date.now(),
    expiresDate: Date.now() + 31 * 86_400_000
  };
}

test("a verified friend offer creates exactly one reward", async () => {
  const { service, apple, database } = makeHarness();
  const referrer = identity();
  const friend = identity();
  const invite = service.createInvite(referrer);
  service.acceptInvite(friend, invite.code);
  const transaction = friendTransaction(friend);
  apple.transactions.set("friend-jws", transaction);

  const first = await service.verifyTransaction(friend, "friend-jws", invite.code);
  const second = await service.verifyTransaction(friend, "friend-jws", invite.code);

  assert.equal(first.referralQualified, true);
  assert.equal(first.rewardCreated, true);
  assert.equal(second.duplicate, true);
  assert.equal(second.referralQualified, true);
  assert.deepEqual(service.status(referrer), {
    successfulReferrals: 1,
    availableRewards: 1,
    claimedRewards: 0
  });
  database.close();
});

test("a person cannot accept their own invite", () => {
  const { service, database } = makeHarness();
  const referrer = identity();
  const invite = service.createInvite(referrer);
  assert.throws(
    () => service.acceptInvite(referrer, invite.code),
    (error: unknown) => error instanceof ReferralServiceError && error.code === "self_referral"
  );
  database.close();
});

test("the same App Store subscription cannot qualify both sides", async () => {
  const { service, apple, database } = makeHarness();
  const referrer = identity();
  const friend = identity();
  const originalTransactionID = randomUUID();
  const referrerTransaction: AppleTransaction = {
    ...friendTransaction(referrer, originalTransactionID),
    offerIdentifier: undefined
  };
  apple.transactions.set("referrer-jws", referrerTransaction);
  await service.verifyTransaction(referrer, "referrer-jws");
  const invite = service.createInvite(referrer);
  service.acceptInvite(friend, invite.code);
  apple.transactions.set("friend-jws", friendTransaction(friend, originalTransactionID));

  await assert.rejects(
    service.verifyTransaction(friend, "friend-jws", invite.code),
    (error: unknown) => error instanceof ReferralServiceError &&
      ["transaction_owner_conflict", "self_referral"].includes(error.code)
  );
  database.close();
});

test("an accountless referrer claims an encrypted one-time Apple offer code", async () => {
  const { service, apple, database } = makeHarness();
  const referrer = identity();
  const friend = identity();
  const invite = service.createInvite(referrer);
  service.acceptInvite(friend, invite.code);
  apple.transactions.set("friend-jws", friendTransaction(friend));
  await service.verifyTransaction(friend, "friend-jws", invite.code);
  service.importFirstRewardCodes(["ONE-TIME-CODE"], configuration.firstRewardOfferIdentifier);

  const claim = await service.claimReward(referrer);

  assert.equal(claim.mode, "offer_code");
  if (claim.mode === "offer_code") {
    assert.match(claim.redemptionURL, /ONE-TIME-CODE/);
  }
  const retry = await service.claimReward(referrer);
  assert.equal(retry.mode, "offer_code");
  if (retry.mode === "offer_code") {
    assert.equal(retry.redemptionURL, claim.mode === "offer_code" ? claim.redemptionURL : "");
  }
  database.close();
});

test("a subscriber reward uses a server-signed promotional offer", async () => {
  const { service, apple, database } = makeHarness();
  const referrer = identity();
  const referrerTransaction: AppleTransaction = {
    ...friendTransaction(referrer),
    offerIdentifier: undefined
  };
  apple.transactions.set("referrer-jws", referrerTransaction);
  await service.verifyTransaction(referrer, "referrer-jws");

  const friend = identity();
  const invite = service.createInvite(referrer);
  service.acceptInvite(friend, invite.code);
  apple.transactions.set("friend-jws", friendTransaction(friend));
  await service.verifyTransaction(friend, "friend-jws", invite.code);

  const claim = await service.claimReward(referrer);

  assert.equal(claim.mode, "promotional_offer");
  if (claim.mode === "promotional_offer") {
    assert.equal(claim.offer.offerID, configuration.rewardMonthlyPromotionalOfferIdentifier);
    assert.equal(claim.offer.productID, configuration.monthlyProductID);
  }
  const retry = await service.claimReward(referrer);
  assert.equal(retry.mode, "promotional_offer");
  assert.equal(service.status(referrer).availableRewards, 1);
  database.close();
});

test("an old or expired friend offer cannot qualify a fresh referral", async () => {
  const { service, apple, database } = makeHarness();
  const referrer = identity();
  const friend = identity();
  const invite = service.createInvite(referrer);
  service.acceptInvite(friend, invite.code);
  apple.transactions.set("old-friend-jws", {
    ...friendTransaction(friend),
    purchaseDate: Date.now() - 86_400_000,
    expiresDate: Date.now() - 1
  });

  await assert.rejects(
    service.verifyTransaction(friend, "old-friend-jws", invite.code),
    (error: unknown) => error instanceof ReferralServiceError &&
      error.code === "friend_offer_not_verified"
  );
  assert.equal(service.status(referrer).availableRewards, 0);

  apple.transactions.set("old-friend-jws", friendTransaction(friend));
  const retried = await service.verifyTransaction(friend, "old-friend-jws", invite.code);
  assert.equal(retried.referralQualified, true);
  assert.equal(service.status(referrer).availableRewards, 1);
  database.close();
});

test("referral codes are bounded before database lookup", () => {
  const { service, database } = makeHarness();
  assert.throws(
    () => service.acceptInvite(identity(), "<script>bad</script>"),
    (error: unknown) => error instanceof ReferralServiceError &&
      error.code === "invalid_request"
  );
  database.close();
});

test("transactions without appAccountToken are bound through Apple's server API", async () => {
  const { service, apple, database } = makeHarness();
  const customer = identity();
  apple.transactions.set("outside-jws", {
    ...friendTransaction(customer),
    appAccountToken: undefined,
    offerIdentifier: undefined
  });

  await service.verifyTransaction(customer, "outside-jws");

  assert.equal(apple.bindings.length, 1);
  assert.equal(apple.bindings[0]?.appAccountToken, customer.appAccountToken);
  database.close();
});
