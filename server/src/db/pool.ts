import pg from "pg";
import { config } from "../config.ts";

export const pool = new pg.Pool({ connectionString: config.databaseUrl });

/** Runs fn inside a transaction. Use for anything that moves Pokémon between owners (trades). */
export async function transaction<T>(fn: (client: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}
