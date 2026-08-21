import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  timingSafeEqual
} from "node:crypto";

export function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function secureToken(byteCount = 18): string {
  return randomBytes(byteCount).toString("base64url");
}

export function credentialsMatch(value: string, expectedHash: string): boolean {
  const actual = Buffer.from(sha256(value), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export class OfferCodeCipher {
  private readonly key: Buffer;

  constructor(base64Key: string) {
    this.key = Buffer.from(base64Key, "base64");
    if (this.key.length !== 32) {
      throw new Error("CODE_ENCRYPTION_KEY must be a base64-encoded 32-byte key");
    }
  }

  encrypt(value: string): { ciphertext: string; iv: string; tag: string } {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, iv);
    const ciphertext = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
    return {
      ciphertext: ciphertext.toString("base64"),
      iv: iv.toString("base64"),
      tag: cipher.getAuthTag().toString("base64")
    };
  }

  decrypt(ciphertext: string, iv: string, tag: string): string {
    const decipher = createDecipheriv(
      "aes-256-gcm",
      this.key,
      Buffer.from(iv, "base64")
    );
    decipher.setAuthTag(Buffer.from(tag, "base64"));
    return Buffer.concat([
      decipher.update(Buffer.from(ciphertext, "base64")),
      decipher.final()
    ]).toString("utf8");
  }
}
