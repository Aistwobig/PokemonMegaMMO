import "dotenv/config";

export const config = {
  port: Number(process.env.PORT ?? 2567),
  databaseUrl: process.env.DATABASE_URL ?? "postgres://game:devpassword@localhost:5432/pokemmo",
  redisUrl: process.env.REDIS_URL ?? "redis://localhost:6379",
  // Login/register rate limits. Only turn off for local testing (AUTH_RATE_LIMITS=off).
  authRateLimits: process.env.AUTH_RATE_LIMITS !== "off",
  // Developer tools for testing the game, e.g. starting your own trainer over (DEV_TOOLS=on).
  // Off unless asked for, so players on a shared server don't see them.
  devTools: process.env.DEV_TOOLS === "on",
};
