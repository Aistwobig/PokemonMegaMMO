import type { Client } from "colyseus";

// Which client each trainer is connected as, across all rooms. A trainer may only be online once:
// a second login kicks the first, so two connections can never act on the same Pokémon or items.
// In-memory for now; moves to Redis once there are several processes.

export const CLOSE_LOGGED_IN_ELSEWHERE = 4001;

const online = new Map<string, Client>();

export function claimOnline(trainerId: string, client: Client): void {
  const previous = online.get(trainerId);
  online.set(trainerId, client);
  if (previous && previous !== client) previous.leave(CLOSE_LOGGED_IN_ELSEWHERE);
}

export function isOnline(trainerId: string): boolean {
  return online.has(trainerId);
}

export function releaseOnline(trainerId: string, client: Client): void {
  if (online.get(trainerId) === client) online.delete(trainerId);
}
