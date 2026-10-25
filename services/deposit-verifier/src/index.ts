import { Interface, getAddress } from "ethers";

interface Env {
  DB: D1Database;
  BASE_RPC_URL?: string;
  VAULT_ADDRESS?: string;
  GAME_ORIGIN?: string;
  MIN_CONFIRMATIONS?: string;
}

const CHAIN_ID = "0x2105"; // Base Mainnet, 8453
const VAULT_ABI = [
  "event Deposited(address indexed player, uint256 amount, uint256 newAvailableBalance)",
  "function deposit() payable"
];
const vaultInterface = new Interface(VAULT_ABI);
const depositSelector = vaultInterface.getFunction("deposit")!.selector;
const TX_HASH_RE = /^0x[a-fA-F0-9]{64}$/;
const ADDRESS_RE = /^0x[a-fA-F0-9]{40}$/;

type RpcError = { code?: number; message?: string };
type RpcResponse<T> = { result?: T; error?: RpcError };

function json(data: unknown, status = 200, origin?: string): Response {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer"
  });
  if (origin) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
    headers.set("access-control-allow-methods", "POST, GET, OPTIONS");
    headers.set("access-control-allow-headers", "Content-Type");
  }
  return new Response(JSON.stringify(data), { status, headers });
}

async function rpc<T>(env: Env, method: string, params: unknown[]): Promise<T> {
  if (!env.BASE_RPC_URL) throw new Error("RPC_NOT_CONFIGURED");
  const response = await fetch(env.BASE_RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params })
  });
  if (!response.ok) throw new Error("RPC_UNAVAILABLE");
  const body = await response.json() as RpcResponse<T>;
  if (body.error || body.result === undefined) throw new Error("RPC_ERROR");
  return body.result;
}

function hexToBigInt(value: string): bigint {
  if (!/^0x[0-9a-fA-F]+$/.test(value)) throw new Error("INVALID_RPC_DATA");
  return BigInt(value);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const requestOrigin = request.headers.get("Origin") ?? "";
    const allowedOrigin = env.GAME_ORIGIN ?? "";

    // No wildcard CORS. Set GAME_ORIGIN to the exact deployed game origin.
    if (requestOrigin && requestOrigin !== allowedOrigin) {
      return json({ ok: false, error: "ORIGIN_NOT_ALLOWED" }, 403);
    }
    const corsOrigin = requestOrigin === allowedOrigin && allowedOrigin ? allowedOrigin : undefined;

    if (request.method === "OPTIONS") {
      if (!corsOrigin) return json({ ok: false, error: "ORIGIN_NOT_ALLOWED" }, 403);
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": corsOrigin,
          "access-control-allow-methods": "POST, GET, OPTIONS",
          "access-control-allow-headers": "Content-Type",
          "access-control-max-age": "600",
          "vary": "Origin"
        }
      });
    }

    if (url.pathname === "/health" && request.method === "GET") {
      const ready = Boolean(env.DB && env.BASE_RPC_URL && env.VAULT_ADDRESS && env.GAME_ORIGIN);
      return json({ ok: true, ready, mode: "read-only-verifier", chainId: 8453, realDepositsEnabled: false }, 200, corsOrigin);
    }

    if (url.pathname !== "/v1/deposits/verify" || request.method !== "POST") {
      return json({ ok: false, error: "NOT_FOUND" }, 404, corsOrigin);
    }

    // Fail closed until an independently verified contract address and bindings exist.
    if (!env.DB || !env.BASE_RPC_URL || !env.VAULT_ADDRESS || !env.GAME_ORIGIN) {
      return json({ ok: false, error: "VERIFIER_NOT_CONFIGURED" }, 503, corsOrigin);
    }

    let vaultAddress: string;
    try {
      vaultAddress = getAddress(env.VAULT_ADDRESS);
    } catch {
      return json({ ok: false, error: "INVALID_SERVER_CONFIGURATION" }, 503, corsOrigin);
    }

    let payload: { txHash?: unknown; wallet?: unknown };
    try {
      payload = await request.json() as { txHash?: unknown; wallet?: unknown };
    } catch {
      return json({ ok: false, error: "INVALID_JSON" }, 400, corsOrigin);
    }
    if (typeof payload.txHash !== "string" || !TX_HASH_RE.test(payload.txHash)) {
      return json({ ok: false, error: "INVALID_TX_HASH" }, 400, corsOrigin);
    }
    if (typeof payload.wallet !== "string" || !ADDRESS_RE.test(payload.wallet)) {
      return json({ ok: false, error: "INVALID_WALLET" }, 400, corsOrigin);
    }

    const txHash = payload.txHash.toLowerCase();
    let wallet: string;
    try {
      wallet = getAddress(payload.wallet);
    } catch {
      return json({ ok: false, error: "INVALID_WALLET" }, 400, corsOrigin);
    }

    try {
      const chainId = await rpc<string>(env, "eth_chainId", []);
      if (chainId.toLowerCase() !== CHAIN_ID) {
        return json({ ok: false, error: "WRONG_CHAIN" }, 503, corsOrigin);
      }

      const code = await rpc<string>(env, "eth_getCode", [vaultAddress, "latest"]);
      if (!code || code === "0x") {
        return json({ ok: false, error: "VAULT_CODE_NOT_FOUND" }, 503, corsOrigin);
      }

      const [receipt, tx] = await Promise.all([
        rpc<any>(env, "eth_getTransactionReceipt", [txHash]),
        rpc<any>(env, "eth_getTransactionByHash", [txHash])
      ]);
      if (!receipt || !tx) return json({ ok: false, error: "TRANSACTION_NOT_FOUND" }, 404, corsOrigin);
      if (receipt.status !== "0x1") return json({ ok: false, error: "TRANSACTION_FAILED" }, 422, corsOrigin);
      if (String(receipt.transactionHash).toLowerCase() !== txHash) {
        return json({ ok: false, error: "RECEIPT_HASH_MISMATCH" }, 422, corsOrigin);
      }
      if (!tx.to || getAddress(tx.to) !== vaultAddress || !tx.input?.startsWith(depositSelector)) {
        return json({ ok: false, error: "NOT_A_DIRECT_VAULT_DEPOSIT" }, 422, corsOrigin);
      }
      if (getAddress(tx.from) !== wallet) {
        return json({ ok: false, error: "WALLET_MISMATCH" }, 422, corsOrigin);
      }

      const matchingLogs = (receipt.logs ?? []).filter((log: any) =>
        typeof log.address === "string" &&
        getAddress(log.address) === vaultAddress &&
        Array.isArray(log.topics) &&
        log.topics[0]?.toLowerCase() === vaultInterface.getEvent("Deposited")!.topicHash.toLowerCase()
      );

      const decoded = matchingLogs
        .map((log: any): { log: any; player: string; amount: bigint; newAvailableBalance: bigint } | null => {
          try {
            const parsed = vaultInterface.parseLog({ topics: log.topics, data: log.data });
            if (!parsed) return null;
            return {
              log,
              player: getAddress(String(parsed.args.player)),
              amount: BigInt(parsed.args.amount.toString()),
              newAvailableBalance: BigInt(parsed.args.newAvailableBalance.toString())
            };
          } catch {
            return null;
          }
        })
        .filter((entry): entry is { log: any; player: string; amount: bigint; newAvailableBalance: bigint } =>
          Boolean(entry && entry.player === wallet && entry.amount > 0n));

      if (decoded.length !== 1) {
        return json({ ok: false, error: decoded.length ? "AMBIGUOUS_DEPOSIT_LOGS" : "DEPOSIT_EVENT_NOT_FOUND" }, 422, corsOrigin);
      }

      const item = decoded[0];
      if (hexToBigInt(String(tx.value ?? "0x0")) !== item.amount) {
        return json({ ok: false, error: "TRANSACTION_VALUE_MISMATCH" }, 422, corsOrigin);
      }
      const logIndex = Number(hexToBigInt(item.log.logIndex).toString());
      const blockNumber = hexToBigInt(receipt.blockNumber);
      const receiptBlockHash = String(receipt.blockHash).toLowerCase();
      const latestHex = await rpc<string>(env, "eth_blockNumber", []);
      const latestBlock = hexToBigInt(latestHex);
      const configuredConfirmations = Number(env.MIN_CONFIRMATIONS ?? "20");
      const minConfirmations = Number.isSafeInteger(configuredConfirmations) && configuredConfirmations >= 1
        ? configuredConfirmations : 20;
      const confirmations = latestBlock >= blockNumber ? Number(latestBlock - blockNumber + 1n) : 0;

      // Detect a reorg by checking the canonical hash at the receipt's block height.
      const canonicalBlock = await rpc<any>(env, "eth_getBlockByNumber", [receipt.blockNumber, false]);
      if (!canonicalBlock || String(canonicalBlock.hash).toLowerCase() !== receiptBlockHash) {
        return json({ ok: false, error: "REORG_DETECTED" }, 409, corsOrigin);
      }

      if (confirmations < minConfirmations) {
        return json({
          ok: true, status: "pending", confirmations, requiredConfirmations: minConfirmations,
          txHash, player: wallet, amountWei: item.amount.toString()
        }, 200, corsOrigin);
      }

      const now = new Date().toISOString();
      const existing = await env.DB.prepare(
        "SELECT block_hash, player, amount_wei, status FROM verified_deposits WHERE chain_id = ? AND tx_hash = ? AND log_index = ?"
      ).bind(8453, txHash, logIndex).first<{ block_hash: string; player: string; amount_wei: string; status: string }>();

      if (existing && existing.block_hash === receiptBlockHash && existing.status === "finalized") {
        if (existing.player.toLowerCase() !== wallet.toLowerCase() || existing.amount_wei !== item.amount.toString()) {
          return json({ ok: false, error: "IDEMPOTENCY_CONFLICT" }, 409, corsOrigin);
        }
        return json({
          ok: true, status: "finalized", alreadyRecorded: true, txHash, logIndex,
          player: wallet, amountWei: item.amount.toString(), blockNumber: blockNumber.toString(),
          confirmations, note: "On-chain verification only; contract remains the balance source of truth."
        }, 200, corsOrigin);
      }

      // Unique key makes retries idempotent. This table is an audit/index only, never a spendable ledger.
      await env.DB.prepare(`
        INSERT INTO verified_deposits
          (chain_id, tx_hash, log_index, block_number, block_hash, player, amount_wei, status, confirmations, first_seen_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'finalized', ?, ?, ?)
        ON CONFLICT(chain_id, tx_hash, log_index) DO UPDATE SET
          block_number = excluded.block_number,
          block_hash = excluded.block_hash,
          player = excluded.player,
          amount_wei = excluded.amount_wei,
          status = 'finalized',
          confirmations = excluded.confirmations,
          updated_at = excluded.updated_at
      `).bind(
        8453, txHash, logIndex, blockNumber.toString(), receiptBlockHash,
        wallet.toLowerCase(), item.amount.toString(), confirmations, now, now
      ).run();

      return json({
        ok: true, status: "finalized", alreadyRecorded: false, txHash, logIndex,
        player: wallet, amountWei: item.amount.toString(), blockNumber: blockNumber.toString(),
        confirmations, note: "On-chain verification only; contract remains the balance source of truth."
      }, 200, corsOrigin);
    } catch (error) {
      // Keep provider/internal details out of public responses.
      const message = error instanceof Error ? error.message : "";
      const status = message === "RPC_NOT_CONFIGURED" ? 503 : 502;
      return json({ ok: false, error: status === 503 ? "VERIFIER_NOT_CONFIGURED" : "VERIFICATION_TEMPORARILY_UNAVAILABLE" }, status, corsOrigin);
    }
  }
};
