import { randomUUID } from "node:crypto";

// When a player steps on a warp, the server issues a ticket saying where they arrive.
// The client leaves the old room and joins the new one with the ticket, so it can't
// pick its own spawn point. In-memory for now; moves to Redis once there are several processes.

export interface Transfer {
  trainerId: string;
  mapId: string;
  x: number;
  y: number;
  facing: string;
}

const TICKET_TTL_MS = 30_000;
const tickets = new Map<string, Transfer>();

export function issueTicket(transfer: Transfer): string {
  const ticket = randomUUID();
  tickets.set(ticket, transfer);
  setTimeout(() => tickets.delete(ticket), TICKET_TTL_MS).unref();
  return ticket;
}

/** A ticket only works for the trainer it was issued to, on the map it points at. */
export function redeemTicket(ticket: unknown, mapId: string, trainerId: string): Transfer | undefined {
  if (typeof ticket !== "string") return undefined;
  const transfer = tickets.get(ticket);
  if (!transfer || transfer.mapId !== mapId || transfer.trainerId !== trainerId) return undefined;
  tickets.delete(ticket);
  return transfer;
}
