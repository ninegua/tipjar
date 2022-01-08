import { Ed25519KeyIdentity } from "@dfinity/identity";
import { Actor, HttpAgent } from "@dfinity/agent";
import { Principal } from "@dfinity/principal";

import {
  idlFactory as tipjar_idl,
  canisterId as tipjar_id,
} from "../../declarations/tipjar";
import { idlFactory as ledger_idl, canisterId as ledger_id } from "./ledger.js";
import crc32 from "crc-32";
import { sha224 } from "js-sha256";

function newIdentity() {
  const entropy = crypto.getRandomValues(new Uint8Array(32));
  const identity = Ed25519KeyIdentity.generate(entropy);
  localStorage.setItem("local_identity", JSON.stringify(identity));
  return identity;
}

function readIdentity() {
  const stored = localStorage.getItem("local_identity");
  if (!stored) {
    return newIdentity();
  }
  try {
    return Ed25519KeyIdentity.fromJSON(stored);
  } catch (error) {
    console.log(error);
    return newIdentity();
  }
}

function principalToAccountId(principal, subaccount) {
  const shaObj = sha224.create();
  shaObj.update("\x0Aaccount-id");
  shaObj.update(principal.toUint8Array());
  shaObj.update(subaccount ? subaccount : new Uint8Array(32));
  const hash = new Uint8Array(shaObj.array());
  const crc = crc32.buf(hash);
  const blob = new Uint8Array([
    (crc >> 24) & 0xff,
    (crc >> 16) & 0xff,
    (crc >> 8) & 0xff,
    crc & 0xff,
    ...hash,
  ]);
  return Buffer.from(blob).toString("hex");
}

function buildSubAccountId(principal) {
  const blob = principal.toUint8Array();
  const subAccount = new Uint8Array(32);
  subAccount[0] = blob.length;
  subAccount.set(blob, 1);
  return subAccount;
}

const FEE = { e8s: 10000n };
const TOP_UP_CANISTER_MEMO = BigInt(0x50555054);
BigInt.prototype.toJSON = function () {
  return Number(this);
};
const minting_id = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
const identity = readIdentity();
const principal = identity.getPrincipal();
const account = principalToAccountId(principal);
document.getElementById("account").value = account;

const agent = new HttpAgent({ identity: readIdentity() });
const ledger = Actor.createActor(ledger_idl, { agent, canisterId: ledger_id });
const tipjar = Actor.createActor(tipjar_idl, { agent, canisterId: tipjar_id });

var topping_up = false;
async function topup(amount, recipient) {
  if (!topping_up) {
    console.log("topping up");
    topping_up = true;
    const to_subaccount = buildSubAccountId(recipient);
    const account = principalToAccountId(minting_id, to_subaccount);
    const block_height = await ledger.send_dfx({
      to: account,
      fee: FEE,
      memo: TOP_UP_CANISTER_MEMO,
      from_subaccount: [],
      created_at_time: [],
      amount,
    });

    console.log(block_height);
    const result = await ledger.notify_dfx({
      to_canister: minting_id,
      block_height,
      from_subaccount: [],
      to_subaccount: [[...to_subaccount]],
      max_fee: FEE,
    });

    topping_up = false;
    return result;
  }
}

var refreshing_ledger = false;
function refresh_ledger() {
  if (!refreshing_ledger) {
    refreshing_ledger = true;
    ledger
      .account_balance_dfx({ account })
      .then((balance) => {
        document.getElementById("balance").value = balance.e8s;
        refreshing_ledger = false;
        if (balance.e8s > 20000n) {
          topup(
            { e8s: balance.e8s - 20000n },
            Principal.fromText(tipjar_id),
            0
          );
        }
      })
      .catch((err) => {
        console.log(err);
        refreshing_ledger = false;
      });
  }
}

var refreshing_cycles = false;
function refresh_cycles() {
  if (!refreshing_cycles) {
    refreshing_cycles = true;
    tipjar
      .remaining_cycles()
      .then((cycles) => {
        document.getElementById("cycles").value = cycles.toString();
        refreshing_cycles = false;
      })
      .catch((err) => {
        console.log(err);
        refreshing_cycles = false;
      });
  }
}

/// refresh every 5s
setInterval(refresh_ledger, 5100);
setInterval(refresh_cycles, 4900);
