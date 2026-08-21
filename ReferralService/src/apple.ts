import { randomUUID } from "node:crypto";
import {
  AppStoreServerAPIClient,
  Environment,
  PromotionalOfferSignatureCreator,
  SignedDataVerifier
} from "@apple/app-store-server-library";
import type { ServerConfiguration } from "./config.js";
import type {
  AppleGateway,
  AppleTransaction,
  PromotionalOfferSignature
} from "./types.js";

export class AppleServerGateway implements AppleGateway {
  private readonly productionVerifier: SignedDataVerifier;
  private readonly sandboxVerifier: SignedDataVerifier;
  private readonly productionClient: AppStoreServerAPIClient;
  private readonly sandboxClient: AppStoreServerAPIClient;
  private readonly signatureCreator: PromotionalOfferSignatureCreator;

  constructor(private readonly configuration: ServerConfiguration) {
    this.productionVerifier = new SignedDataVerifier(
      configuration.appleRootCertificates,
      true,
      Environment.PRODUCTION,
      configuration.bundleID,
      configuration.appAppleID
    );
    this.sandboxVerifier = new SignedDataVerifier(
      configuration.appleRootCertificates,
      true,
      Environment.SANDBOX,
      configuration.bundleID,
      undefined
    );
    this.productionClient = new AppStoreServerAPIClient(
      configuration.applePrivateKey,
      configuration.appleKeyID,
      configuration.appleIssuerID,
      configuration.bundleID,
      Environment.PRODUCTION
    );
    this.sandboxClient = new AppStoreServerAPIClient(
      configuration.applePrivateKey,
      configuration.appleKeyID,
      configuration.appleIssuerID,
      configuration.bundleID,
      Environment.SANDBOX
    );
    this.signatureCreator = new PromotionalOfferSignatureCreator(
      configuration.applePrivateKey,
      configuration.appleKeyID,
      configuration.bundleID
    );
  }

  async verifyTransaction(signedTransaction: string): Promise<AppleTransaction> {
    const environment = readUntrustedEnvironment(signedTransaction);
    const verifier = environment === "Production"
      ? this.productionVerifier
      : this.sandboxVerifier;
    const transaction = await verifier.verifyAndDecodeTransaction(signedTransaction);
    if (!transaction.transactionId || !transaction.originalTransactionId || !transaction.productId) {
      throw new Error("The App Store transaction is missing required identifiers");
    }
    return {
      transactionId: transaction.transactionId,
      originalTransactionId: transaction.originalTransactionId,
      appAccountToken: transaction.appAccountToken,
      productId: transaction.productId,
      offerIdentifier: transaction.offerIdentifier,
      offerType: transaction.offerType,
      environment,
      expiresDate: transaction.expiresDate,
      revocationDate: transaction.revocationDate,
      purchaseDate: transaction.purchaseDate,
      originalPurchaseDate: transaction.originalPurchaseDate,
      signedDate: transaction.signedDate
    };
  }

  async bindAppAccountToken(
    transaction: AppleTransaction,
    appAccountToken: string
  ): Promise<void> {
    const client = transaction.environment === "Production"
      ? this.productionClient
      : this.sandboxClient;
    await client.setAppAccountToken(transaction.originalTransactionId, { appAccountToken });
  }

  async createPromotionalOffer(
    productID: string,
    offerID: string,
    appAccountToken: string
  ): Promise<PromotionalOfferSignature> {
    const nonce = randomUUID();
    const timestamp = Date.now();
    return {
      productID,
      offerID,
      keyID: this.configuration.appleKeyID,
      nonce,
      signature: this.signatureCreator.createSignature(
        productID,
        offerID,
        appAccountToken,
        nonce,
        timestamp
      ),
      timestamp
    };
  }
}

function readUntrustedEnvironment(signedTransaction: string): "Sandbox" | "Production" {
  const payload = signedTransaction.split(".")[1];
  if (!payload) throw new Error("The transaction is not a JWS value");
  const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as {
    environment?: string;
  };
  if (decoded.environment !== "Sandbox" && decoded.environment !== "Production") {
    throw new Error("The transaction environment is unsupported");
  }
  return decoded.environment;
}
