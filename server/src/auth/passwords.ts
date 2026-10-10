import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";

// scrypt is built into Node, so there's no native module to compile. Hashes are stored as
// "scrypt$N$r$p$<salt>$<key>" (base64), so the cost can be raised later without breaking old ones.

const COST = { N: 2 ** 15, r: 8, p: 1 };
const KEY_LEN = 32;

function derive(password: string, salt: Buffer, cost: typeof COST): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const maxmem = 256 * cost.N * cost.r; // scrypt needs 128·N·r bytes; leave headroom
    scrypt(password.normalize("NFKC"), salt, KEY_LEN, { ...cost, maxmem }, (err, key) => (err ? reject(err) : resolve(key)));
  });
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await derive(password, salt, COST);
  return ["scrypt", COST.N, COST.r, COST.p, salt.toString("base64"), key.toString("base64")].join("$");
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [algo, n, r, p, salt, key] = stored.split("$");
  if (algo !== "scrypt" || !salt || !key) return false;
  const expected = Buffer.from(key, "base64");
  const actual = await derive(password, Buffer.from(salt, "base64"), { N: Number(n), r: Number(r), p: Number(p) });
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

// Verifying against this when the username doesn't exist makes "no such user" take as long as
// "wrong password", so response times don't reveal which usernames are registered.
export const DUMMY_HASH = await hashPassword(randomBytes(16).toString("hex"));
