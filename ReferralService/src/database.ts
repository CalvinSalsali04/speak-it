import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import Database from "better-sqlite3";
import { credentialsMatch, OfferCodeCipher, secureToken, sha256 } from "./crypto.js";

export interface IdentityRow {
  appAccountToken: string;
  originalTransactionID: string | null;
  latestProductID: string | null;
}

export interface ReferralRow {
  id: string;
  code: string;
  referrerToken: string;
  friendToken: string | null;
  status: string;
  friendTransactionID: string | null;
  acceptedAt: number | null;
}

export interface RewardRow {
  id: string;
  referralID: string;
  beneficiaryToken: string;
  status: string;
  claimMode: string | null;
  productID: string | null;
}

export class ReferralDatabase {
  private readonly db: Database.Database;

  constructor(path: string) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.db = new Database(path);
    this.db.exec("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS identities (
        app_account_token TEXT PRIMARY KEY,
        credential_hash TEXT NOT NULL,
        original_transaction_id TEXT UNIQUE,
        latest_product_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS referrals (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        referrer_token TEXT NOT NULL REFERENCES identities(app_account_token),
        friend_token TEXT UNIQUE REFERENCES identities(app_account_token),
        status TEXT NOT NULL CHECK(status IN ('created', 'accepted', 'qualified')),
        friend_transaction_id TEXT UNIQUE,
        created_at INTEGER NOT NULL,
        accepted_at INTEGER,
        qualified_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS transactions (
        transaction_id TEXT PRIMARY KEY,
        original_transaction_id TEXT NOT NULL,
        app_account_token TEXT NOT NULL REFERENCES identities(app_account_token),
        product_id TEXT NOT NULL,
        offer_identifier TEXT,
        offer_type INTEGER,
        environment TEXT NOT NULL,
        expires_at INTEGER,
        revocation_at INTEGER,
        signed_at INTEGER,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS rewards (
        id TEXT PRIMARY KEY,
        referral_id TEXT NOT NULL UNIQUE REFERENCES referrals(id),
        beneficiary_token TEXT NOT NULL REFERENCES identities(app_account_token),
        status TEXT NOT NULL CHECK(status IN ('available', 'claimed', 'redeemed')),
        claim_mode TEXT,
        product_id TEXT,
        claimed_at INTEGER,
        redeemed_transaction_id TEXT UNIQUE,
        redeemed_at INTEGER,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS offer_codes (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL CHECK(kind = 'first_reward'),
        offer_identifier TEXT NOT NULL,
        code_hash TEXT NOT NULL UNIQUE,
        ciphertext TEXT NOT NULL,
        iv TEXT NOT NULL,
        tag TEXT NOT NULL,
        reward_id TEXT UNIQUE REFERENCES rewards(id),
        assigned_at INTEGER,
        redeemed_transaction_id TEXT UNIQUE,
        created_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS referrals_referrer_index
        ON referrals(referrer_token, created_at);
      CREATE INDEX IF NOT EXISTS rewards_beneficiary_index
        ON rewards(beneficiary_token, created_at);
      CREATE INDEX IF NOT EXISTS transactions_account_index
        ON transactions(app_account_token, created_at);
    `);
  }

  close(): void {
    this.db.close();
  }

  authenticateOrCreate(appAccountToken: string, credential: string): IdentityRow {
    const existing = this.db.prepare(`
      SELECT app_account_token, credential_hash, original_transaction_id, latest_product_id
      FROM identities WHERE app_account_token = ?
    `).get(appAccountToken) as Record<string, string | null> | undefined;
    if (existing) {
      if (!credentialsMatch(credential, String(existing.credential_hash))) {
        throw new ReferralDatabaseError("unauthorized", "The referral identity credential is invalid");
      }
      return {
        appAccountToken: String(existing.app_account_token),
        originalTransactionID: existing.original_transaction_id ?? null,
        latestProductID: existing.latest_product_id ?? null
      };
    }

    const now = Date.now();
    this.db.prepare(`
      INSERT INTO identities (
        app_account_token, credential_hash, created_at, updated_at
      ) VALUES (?, ?, ?, ?)
    `).run(appAccountToken, sha256(credential), now, now);
    return { appAccountToken, originalTransactionID: null, latestProductID: null };
  }

  identity(appAccountToken: string): IdentityRow | null {
    const row = this.db.prepare(`
      SELECT app_account_token, original_transaction_id, latest_product_id
      FROM identities WHERE app_account_token = ?
    `).get(appAccountToken) as Record<string, string | null> | undefined;
    return row ? {
      appAccountToken: String(row.app_account_token),
      originalTransactionID: row.original_transaction_id ?? null,
      latestProductID: row.latest_product_id ?? null
    } : null;
  }

  recordTransactionIdentity(
    appAccountToken: string,
    originalTransactionID: string,
    productID: string
  ): void {
    const owner = this.db.prepare(`
      SELECT app_account_token FROM identities WHERE original_transaction_id = ?
    `).get(originalTransactionID) as { app_account_token: string } | undefined;
    if (owner && owner.app_account_token !== appAccountToken) {
      throw new ReferralDatabaseError(
        "transaction_owner_conflict",
        "This App Store subscription is already associated with another referral identity"
      );
    }
    this.db.prepare(`
      UPDATE identities
      SET original_transaction_id = COALESCE(original_transaction_id, ?),
          latest_product_id = ?, updated_at = ?
      WHERE app_account_token = ?
    `).run(originalTransactionID, productID, Date.now(), appAccountToken);
  }

  transactionExists(transactionID: string): boolean {
    return Boolean(this.db.prepare(
      "SELECT 1 FROM transactions WHERE transaction_id = ?"
    ).get(transactionID));
  }

  insertTransaction(transaction: {
    transactionID: string;
    originalTransactionID: string;
    appAccountToken: string;
    productID: string;
    offerIdentifier?: string;
    offerType?: number;
    environment: string;
    expiresAt?: number;
    revocationAt?: number;
    signedAt?: number;
  }): void {
    this.db.prepare(`
      INSERT INTO transactions (
        transaction_id, original_transaction_id, app_account_token,
        product_id, offer_identifier, offer_type, environment,
        expires_at, revocation_at, signed_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      transaction.transactionID,
      transaction.originalTransactionID,
      transaction.appAccountToken,
      transaction.productID,
      transaction.offerIdentifier ?? null,
      transaction.offerType ?? null,
      transaction.environment,
      transaction.expiresAt ?? null,
      transaction.revocationAt ?? null,
      transaction.signedAt ?? null,
      Date.now()
    );
  }

  getOrCreateReferral(referrerToken: string): ReferralRow {
    const existing = this.db.prepare(`
      SELECT id, code, referrer_token, friend_token, status, friend_transaction_id, accepted_at
      FROM referrals
      WHERE referrer_token = ? AND status IN ('created', 'accepted')
      ORDER BY created_at DESC LIMIT 1
    `).get(referrerToken) as Record<string, string | null> | undefined;
    if (existing) return mapReferral(existing);

    const referral: ReferralRow = {
      id: secureToken(),
      code: secureToken(12),
      referrerToken,
      friendToken: null,
      status: "created",
      friendTransactionID: null,
      acceptedAt: null
    };
    this.db.prepare(`
      INSERT INTO referrals (id, code, referrer_token, status, created_at)
      VALUES (?, ?, ?, 'created', ?)
    `).run(referral.id, referral.code, referrerToken, Date.now());
    return referral;
  }

  referralByCode(code: string): ReferralRow | null {
    const row = this.db.prepare(`
      SELECT id, code, referrer_token, friend_token, status, friend_transaction_id, accepted_at
      FROM referrals WHERE code = ?
    `).get(code) as Record<string, string | null> | undefined;
    return row ? mapReferral(row) : null;
  }

  acceptReferral(code: string, friendToken: string): ReferralRow {
    const referral = this.referralByCode(code);
    if (!referral) throw new ReferralDatabaseError("referral_not_found", "This invite is no longer valid");
    if (referral.referrerToken === friendToken) {
      throw new ReferralDatabaseError("self_referral", "You can’t redeem your own referral invite");
    }
    if (referral.status === "qualified") return referral;
    if (referral.friendToken && referral.friendToken !== friendToken) {
      throw new ReferralDatabaseError("invite_already_used", "This invite has already been accepted");
    }
    const used = this.db.prepare(`
      SELECT 1 FROM referrals WHERE friend_token = ? AND code <> ?
    `).get(friendToken, code);
    if (used) {
      throw new ReferralDatabaseError("friend_already_referred", "This person has already used a referral invite");
    }
    this.db.prepare(`
      UPDATE referrals SET friend_token = ?, status = 'accepted', accepted_at = ?
      WHERE code = ?
    `).run(friendToken, Date.now(), code);
    return this.referralByCode(code)!;
  }

  qualifyReferral(referral: ReferralRow, transactionID: string): void {
    this.db.prepare(`
      UPDATE referrals
      SET status = 'qualified', friend_transaction_id = ?, qualified_at = ?
      WHERE id = ? AND status = 'accepted'
    `).run(transactionID, Date.now(), referral.id);
  }

  rewardsInYear(appAccountToken: string, yearStart: number): number {
    const row = this.db.prepare(`
      SELECT COUNT(*) AS count FROM rewards
      WHERE beneficiary_token = ? AND created_at >= ?
    `).get(appAccountToken, yearStart) as { count: number };
    return Number(row.count);
  }

  createReward(referralID: string, beneficiaryToken: string): RewardRow {
    const existing = this.db.prepare(`
      SELECT id, referral_id, beneficiary_token, status, claim_mode, product_id
      FROM rewards WHERE referral_id = ?
    `).get(referralID) as Record<string, string | null> | undefined;
    if (existing) return mapReward(existing);
    const id = secureToken();
    this.db.prepare(`
      INSERT INTO rewards (id, referral_id, beneficiary_token, status, created_at)
      VALUES (?, ?, ?, 'available', ?)
    `).run(id, referralID, beneficiaryToken, Date.now());
    return this.reward(id)!;
  }

  reward(id: string): RewardRow | null {
    const row = this.db.prepare(`
      SELECT id, referral_id, beneficiary_token, status, claim_mode, product_id
      FROM rewards WHERE id = ?
    `).get(id) as Record<string, string | null> | undefined;
    return row ? mapReward(row) : null;
  }

  nextClaimableReward(appAccountToken: string): RewardRow | null {
    const row = this.db.prepare(`
      SELECT id, referral_id, beneficiary_token, status, claim_mode, product_id
      FROM rewards
      WHERE beneficiary_token = ? AND status IN ('available', 'claimed')
      ORDER BY CASE WHEN status = 'claimed' THEN 0 ELSE 1 END, created_at LIMIT 1
    `).get(appAccountToken) as Record<string, string | null> | undefined;
    return row ? mapReward(row) : null;
  }

  markRewardClaimed(rewardID: string, mode: string, productID: string | null): void {
    this.db.prepare(`
      UPDATE rewards
      SET status = 'claimed', claim_mode = ?, product_id = ?, claimed_at = ?
      WHERE id = ? AND status = 'available'
    `).run(mode, productID, Date.now(), rewardID);
  }

  markRewardRedeemed(
    appAccountToken: string,
    transactionID: string,
    productID: string
  ): RewardRow | null {
    const row = this.db.prepare(`
      SELECT id, referral_id, beneficiary_token, status, claim_mode, product_id
      FROM rewards
      WHERE beneficiary_token = ? AND status = 'claimed'
        AND (product_id IS NULL OR product_id = ?)
      ORDER BY claimed_at LIMIT 1
    `).get(appAccountToken, productID) as Record<string, string | null> | undefined;
    if (!row) return null;
    this.db.prepare(`
      UPDATE rewards SET status = 'redeemed', redeemed_transaction_id = ?, redeemed_at = ?
      WHERE id = ?
    `).run(transactionID, Date.now(), String(row.id));
    this.db.prepare(`
      UPDATE offer_codes SET redeemed_transaction_id = ? WHERE reward_id = ?
    `).run(transactionID, String(row.id));
    return this.reward(String(row.id));
  }

  referralSummary(appAccountToken: string): {
    successfulReferrals: number;
    availableRewards: number;
    claimedRewards: number;
  } {
    const referrals = this.db.prepare(`
      SELECT COUNT(*) AS count FROM referrals
      WHERE referrer_token = ? AND status = 'qualified'
    `).get(appAccountToken) as { count: number };
    const rewards = this.db.prepare(`
      SELECT
        SUM(CASE WHEN status IN ('available', 'claimed') THEN 1 ELSE 0 END) AS available,
        SUM(CASE WHEN status = 'redeemed' THEN 1 ELSE 0 END) AS claimed
      FROM rewards WHERE beneficiary_token = ?
    `).get(appAccountToken) as { available: number | null; claimed: number | null };
    return {
      successfulReferrals: Number(referrals.count),
      availableRewards: Number(rewards.available ?? 0),
      claimedRewards: Number(rewards.claimed ?? 0)
    };
  }

  importOfferCodes(
    codes: string[],
    offerIdentifier: string,
    cipher: OfferCodeCipher
  ): number {
    const insert = this.db.prepare(`
      INSERT OR IGNORE INTO offer_codes (
        id, kind, offer_identifier, code_hash, ciphertext, iv, tag, created_at
      ) VALUES (?, 'first_reward', ?, ?, ?, ?, ?, ?)
    `);
    let imported = 0;
    for (const rawCode of codes) {
      const code = rawCode.trim();
      if (!code) continue;
      const encrypted = cipher.encrypt(code);
      const result = insert.run(
        secureToken(), offerIdentifier, sha256(code), encrypted.ciphertext,
        encrypted.iv, encrypted.tag, Date.now()
      );
      imported += Number(result.changes);
    }
    return imported;
  }

  assignOfferCode(rewardID: string, cipher: OfferCodeCipher): string | null {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const existing = this.db.prepare(`
        SELECT ciphertext, iv, tag FROM offer_codes WHERE reward_id = ?
      `).get(rewardID) as Record<string, string> | undefined;
      if (existing) {
        this.db.exec("COMMIT");
        return cipher.decrypt(
          String(existing.ciphertext),
          String(existing.iv),
          String(existing.tag)
        );
      }
      const row = this.db.prepare(`
        SELECT id, ciphertext, iv, tag FROM offer_codes
        WHERE reward_id IS NULL ORDER BY created_at LIMIT 1
      `).get() as Record<string, string> | undefined;
      if (!row) {
        this.db.exec("ROLLBACK");
        return null;
      }
      this.db.prepare(`
        UPDATE offer_codes SET reward_id = ?, assigned_at = ? WHERE id = ?
      `).run(rewardID, Date.now(), String(row.id));
      this.db.exec("COMMIT");
      return cipher.decrypt(
        String(row.ciphertext),
        String(row.iv),
        String(row.tag)
      );
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }
}

export class ReferralDatabaseError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

function mapReferral(row: Record<string, string | null>): ReferralRow {
  return {
    id: String(row.id),
    code: String(row.code),
    referrerToken: String(row.referrer_token),
    friendToken: row.friend_token ?? null,
    status: String(row.status),
    friendTransactionID: row.friend_transaction_id ?? null,
    acceptedAt: row.accepted_at == null ? null : Number(row.accepted_at)
  };
}

function mapReward(row: Record<string, string | null>): RewardRow {
  return {
    id: String(row.id),
    referralID: String(row.referral_id),
    beneficiaryToken: String(row.beneficiary_token),
    status: String(row.status),
    claimMode: row.claim_mode ?? null,
    productID: row.product_id ?? null
  };
}
