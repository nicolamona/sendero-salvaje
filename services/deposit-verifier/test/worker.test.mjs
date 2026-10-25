import test from "node:test";
import assert from "node:assert/strict";
import { Interface, getAddress } from "ethers";
import worker from "../src/index.ts";

const abi = new Interface([
  "event Deposited(address indexed player, uint256 amount, uint256 newAvailableBalance)",
  "function deposit() payable"
]);
const wallet = getAddress("0x1111111111111111111111111111111111111111");
const vault = getAddress("0x2222222222222222222222222222222222222222");
const blockHash = "0x" + "ab".repeat(32);
const txHash = "0x" + "cd".repeat(32);
const amount = 100n;
let rows;
let rpcMode;

function env() {
  return {
    DB: {
      prepare(sql) {
        let values = [];
        return {
          bind(...args) { values = args; return this; },
          async first() {
            const key = values.slice(0, 3).join(":");
            return rows.get(key) ?? null;
          },
          async run() {
            const [chain, hash, logIndex, blockNumber, bHash, player, wei, confirmations, firstSeen, updated] = values;
            rows.set([chain, hash, logIndex].join(":"), {
              chain_id: chain, tx_hash: hash, log_index: logIndex,
              block_number: blockNumber, block_hash: bHash, player, amount_wei: wei,
              status: "finalized", confirmations, first_seen_at: firstSeen, updated_at: updated
            });
            return { success: true };
          }
        };
      }
    },
    BASE_RPC_URL: "https://rpc.example.invalid",
    VAULT_ADDRESS: vault,
    GAME_ORIGIN: "https://example.game",
    MIN_CONFIRMATIONS: "20"
  };
}

function mockRpc({ confirmations = 25, from = wallet, txValue = amount, eventPlayer = wallet, receiptStatus = "0x1" } = {}) {
  const log = {
    address: vault,
    topics: [abi.getEvent("Deposited").topicHash, "0x" + eventPlayer.slice(2).toLowerCase().padStart(64, "0")],
    data: "0x" + [
      amount.toString(16).padStart(64, "0"),
      (amount * 2n).toString(16).padStart(64, "0")
    ].join(""),
    logIndex: "0x0"
  };
  const receipt = {
    transactionHash: txHash, status: receiptStatus, blockNumber: "0x64",
    blockHash, logs: [log]
  };
  const tx = {
    hash: txHash, to: vault, from, input: abi.getFunction("deposit").selector,
    value: "0x" + BigInt(txValue).toString(16)
  };
  globalThis.fetch = async (_url, options) => {
    const body = JSON.parse(options.body);
    let result;
    switch (body.method) {
      case "eth_chainId": result = "0x2105"; break;
      case "eth_getCode": result = "0x6001"; break;
      case "eth_getTransactionReceipt": result = receipt; break;
      case "eth_getTransactionByHash": result = tx; break;
      case "eth_blockNumber": result = "0x" + (100n + BigInt(confirmations) - 1n).toString(16); break;
      case "eth_getBlockByNumber": result = { hash: blockHash }; break;
      default: throw new Error("Unexpected RPC method " + body.method);
    }
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }), { status: 200 });
  };
}

async function request(payload, configuration = env()) {
  return worker.fetch(new Request("https://worker.example/v1/deposits/verify", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  }), configuration);
}

test.beforeEach(() => {
  rows = new Map();
  rpcMode = undefined;
});

test("fails closed when server configuration is missing", async () => {
  const response = await request({ txHash, wallet }, { GAME_ORIGIN: "https://example.game" });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "VERIFIER_NOT_CONFIGURED");
});

test("rejects a malformed transaction hash before RPC calls", async () => {
  const response = await request({ txHash: "bad", wallet });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "INVALID_TX_HASH");
});

test("rejects a transaction submitted for the wrong wallet", async () => {
  mockRpc({ from: getAddress("0x3333333333333333333333333333333333333333") });
  const response = await request({ txHash, wallet });
  assert.equal(response.status, 422);
  assert.equal((await response.json()).error, "WALLET_MISMATCH");
});

test("keeps deposits pending until the confirmation threshold", async () => {
  mockRpc({ confirmations: 3 });
  const response = await request({ txHash, wallet });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.status, "pending");
  assert.equal(rows.size, 0);
});

test("records a finalized deposit idempotently", async () => {
  mockRpc({ confirmations: 25 });
  const first = await request({ txHash, wallet });
  const firstBody = await first.json();
  assert.equal(firstBody.status, "finalized");
  assert.equal(firstBody.amountWei, amount.toString());
  assert.equal(firstBody.alreadyRecorded, false);
  assert.equal(rows.size, 1);

  const second = await request({ txHash, wallet });
  const secondBody = await second.json();
  assert.equal(secondBody.status, "finalized");
  assert.equal(secondBody.alreadyRecorded, true);
  assert.equal(rows.size, 1);
});

test("rejects a transaction value that disagrees with the event", async () => {
  mockRpc({ txValue: 101n });
  const response = await request({ txHash, wallet });
  assert.equal(response.status, 422);
  assert.equal((await response.json()).error, "TRANSACTION_VALUE_MISMATCH");
});

test("rejects a receipt whose block is no longer canonical", async () => {
  mockRpc({ confirmations: 25 });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_url, options) => {
    const body = JSON.parse(options.body);
    if (body.method === "eth_getBlockByNumber") {
      return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result: { hash: "0x" + "ef".repeat(32) } }));
    }
    return originalFetch(_url, options);
  };
  const response = await request({ txHash, wallet });
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error, "REORG_DETECTED");
  assert.equal(rows.size, 0);
});
