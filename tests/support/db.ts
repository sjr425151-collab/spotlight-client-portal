import { Client } from "pg";

/** Direct access to the LOCAL Supabase database for test setup only (synthetic data). */
const DATABASE_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

export async function withDb<T>(fn: (db: Client) => Promise<T>): Promise<T> {
  const url = new URL(DATABASE_URL);
  if (!["127.0.0.1", "localhost"].includes(url.hostname)) {
    throw new Error("Tests may only connect to a local database");
  }
  const db = new Client({ connectionString: DATABASE_URL });
  await db.connect();
  try {
    return await fn(db);
  } finally {
    await db.end();
  }
}
