import { Ed25519KeyIdentity } from "@dfinity/identity";
import { Actor, HttpAgent, AnonymousIdentity } from "@dfinity/agent";
import { Principal } from "@dfinity/principal";
import { AuthClient } from "@dfinity/auth-client";
import { encodeIcrcAccount } from "@dfinity/ledger-icrc";
import pemfile from "pem-file";

import {
  idlFactory as cycles_ledger_idl,
  canisterId as cycles_ledger_id,
} from "../../declarations/cycles_ledger";
import {
  idlFactory as icp_ledger_idl,
  canisterId as icp_ledger_id,
} from "../../declarations/ledger";
import {
  idlFactory as tipjar_idl,
  canisterId as tipjar_id,
} from "../../declarations/tipjar";
import crc32 from "crc-32";
import { sha224 } from "@noble/hashes/sha256";

function saveLocalIdentity(local) {
  let identity = JSON.stringify(local.identity);
  localStorage.setItem(
    "local_identity",
    JSON.stringify({ identity, type: local.type }),
  );
}

function newLocalIdentity() {
  const entropy = crypto.getRandomValues(new Uint8Array(32));
  const local = {
    identity: Ed25519KeyIdentity.generate(entropy),
    type: "temp",
  };
  saveLocalIdentity(local);
  return local;
}

function newAnonymousIdentity() {
  return { identity: new AnonymousIdentity(), type: "anonymous" };
}

function removeLocalIdentity() {
  localStorage.removeItem("local_identity");
}

function readLocalIdentity() {
  var stored = localStorage.getItem("local_identity");
  if (!stored) {
    return newAnonymousIdentity();
  }
  try {
    var local = JSON.parse(stored);
    if (Array.isArray(local)) {
      local = { identity: stored, type: "temp" };
    }
    local.identity = Ed25519KeyIdentity.fromJSON(local.identity);
    return local;
  } catch (error) {
    console.log(error);
    return newAnonymousIdentity();
  }
}

function principalToAccountId(principal, subaccount) {
  const shaObj = sha224.create();
  shaObj.update("\x0Aaccount-id");
  shaObj.update(principal.toUint8Array());
  shaObj.update(subaccount ? subaccount : new Uint8Array(32));
  const hash = shaObj.digest();
  const crc = crc32.buf(hash);
  return [
    (crc >> 24) & 0xff,
    (crc >> 16) & 0xff,
    (crc >> 8) & 0xff,
    crc & 0xff,
    ...hash,
  ];
}

function principalToSubAccount(principal) {
  const blob = principal.toUint8Array();
  const subAccount = new Uint8Array(32);
  subAccount[0] = blob.length;
  subAccount.set(blob, 1);
  return subAccount;
}

function createState(identity, authenticated) {
  let principal = identity.getPrincipal();
  let subaccount = principalToSubAccount(principal);
  console.log("caller principal", principal.toString());
  console.log("caller subaccount", Buffer.from(subaccount).toString("hex"));
  let account_id = principalToAccountId(
    Principal.fromText(tipjar_id),
    subaccount,
  );
  let icrc_account = {
    owner: Principal.fromText(tipjar_id),
    subaccount: [subaccount],
  };
  let icrc_account_id = encodeIcrcAccount({
    owner: icrc_account.owner,
    subaccount: icrc_account.subaccount[0],
  });
  return {
    identity,
    principal,
    account_id,
    icrc_account,
    icrc_account_id,
    authenticated,
    users: {},
  };
}

function createActors(agent) {
  return {
    tipjar: Actor.createActor(tipjar_idl, { agent, canisterId: tipjar_id }),
    icp_ledger: Actor.createActor(icp_ledger_idl, {
      agent,
      canisterId: icp_ledger_id,
    }),
    cycles_ledger: Actor.createActor(cycles_ledger_idl, {
      agent,
      canisterId: cycles_ledger_id,
    }),
  };
}

function createHttpAgent(identity) {
  let http_agent = new HttpAgent({ identity });
  if (process.env.NODE_ENV !== "production") {
    http_agent.fetchRootKey().catch((err) => {
      console.log(err);
    });
  }
  return http_agent;
}

export async function decodeIdentity(pem) {
  var buf;
  try {
    buf = pemfile.decode(pem);
    //console.log("decoded pem", buf);
    //console.log("decoded pem length" + buf.length);
    if (buf.length != 85) {
      throw "expecting byte length 85 but got " + buf.length;
    }
    let secretKey = Buffer.concat([buf.slice(16, 48), buf.slice(53, 85)]);
    let identity = Ed25519KeyIdentity.fromSecretKey(secretKey);
    let _msg = await identity.sign(Buffer.from([0, 1, 2, 3, 4]));
    return { ok: identity };
  } catch (err) {
    return { err: "Error loading PEM: " + err };
  }
}

export class Agent {
  constructor(auth_client_callback) {
    this.auth_client_callback = auth_client_callback;
    AuthClient.create({ idleOptions: { disableDefaultIdleCallback: true } })
      .then((client) => {
        this.try_activate_auth_client(client);
      })
      .catch((err) => {
        console.log(err);
      });
  }

  get_user_info() {
    return this.state.principal ? this.state.users[this.state.principal] : null;
  }

  set_user_info(info) {
    if (this.state.principal) {
      if (info && this.state.users[this.state.principal]) {
        // Ignore info.balance.icp, only keep info.balance.cycles
        let balance = this.state.users[this.state.principal].balance;
        balance.cycle = info.balance.cycle;
        info.balance = balance;
      }
      this.state.users[this.state.principal] = info;
    }
  }

  is_anonymous() {
    return !this.state || this.state.authenticated == "anonymous";
  }

  is_temporary() {
    return this.state && this.state.authenticated == "temp";
  }

  is_authenticated() {
    return (
      this.state &&
      (this.state.authenticated == "auth" ||
        this.state.authenticated == "imported")
    );
  }

  async try_activate_auth_client(client) {
    this.auth_client = client;
    let authenticated = await client.isAuthenticated();
    if (authenticated) {
      await this.activate_auth_client();
    }
    if (!this.state) {
      this.try_activate_local_client();
    }
  }

  // We'll delegate local identity to auth client identity.
  // If delegation is successfully, local identity will be destroyed.
  async activate_auth_client(callback) {
    try {
      if (!this.is_authenticated()) {
        let auth_identity = await this.auth_client.getIdentity();
        var result;
        if (this.http_agent) {
          result = await this.tipjar_delegate(auth_identity.getPrincipal());
          console.log(result);
        }
        if (!result || "ok" in result || "UserNotFound" in result.err) {
          console.log("Use auth client: ", auth_identity);
          removeLocalIdentity();
          this.state = createState(auth_identity, "auth");
          this.http_agent = createHttpAgent(auth_identity);
          this.actors = createActors(this.http_agent);
        } else {
          console.log("activate_auth_client failed in delegate");
        }
      }
    } catch (err) {
      console.log(err);
    }
    if (callback) {
      callback();
    }
    if (this.state && this.auth_client_callback) {
      this.auth_client_callback();
    }
  }

  activate_anonymous_client() {
    removeLocalIdentity();
    let local = newAnonymousIdentity();
    this.state = createState(local.identity, "anonymous");
    this.http_agent = createHttpAgent(local.identity);
    this.actors = createActors(this.http_agent);
    if (this.auth_client_callback) {
      this.auth_client_callback();
    }
  }

  try_activate_local_client() {
    let local = readLocalIdentity();
    if (local.type == "anonymous") {
      this.activate_anonymous_client();
    } else {
      this.activate_local_client();
    }
  }

  activate_local_client() {
    var local = readLocalIdentity();
    if (local.type == "anonymous") {
      local = newLocalIdentity();
    }
    this.state = createState(local.identity, local.type);
    this.http_agent = createHttpAgent(local.identity);
    this.actors = createActors(this.http_agent);
    if (this.auth_client_callback) {
      this.auth_client_callback();
    }
  }

  async activate_pem_client(identity) {
    let result = await this.tipjar_delegate(identity.getPrincipal());
    console.log(result);
    if ("ok" in result || "UserNotFound" in result.err) {
      saveLocalIdentity({ identity, type: "imported" });
      this.state = createState(identity, "imported");
      this.http_agent = createHttpAgent(identity);
      this.actors = createActors(this.http_agent);
      if (this.auth_client_callback) {
        this.auth_client_callback();
      }
    } else {
      console.log("activate_pem_client failed in delegate");
    }
  }

  account_id_hex() {
    return Buffer.from(this.state.account_id).toString("hex");
  }

  icrc_account() {
    return this.state.icrc_account;
  }

  icrc_account_id() {
    return this.state.icrc_account_id;
  }

  tipjar_stats() {
    return this.actors.tipjar.stats();
  }

  tipjar_aboutme() {
    return this.actors.tipjar.aboutme();
  }

  tipjar_ping() {
    return this.actors.tipjar.ping([]);
  }

  tipjar_delegate(x) {
    return this.actors.tipjar.delegate(x);
  }

  tipjar_allocate(x) {
    return this.actors.tipjar.allocate(x);
  }

  icp_ledger_account_balance() {
    return this.actors.icp_ledger.account_balance({
      account: this.state.account_id,
    });
  }

  cycles_ledger_account_balance() {
    return this.actors.cycles_ledger.icrc1_balance_of(this.state.icrc_account);
  }

  async ii_login(login_callback) {
    try {
      await this.auth_client.login({
        maxTimeToLive: 30n * 24n * 3600000000000n, // expire in 30 days, but II max is 8 days.
        onSuccess: async () => {
          await this.activate_auth_client(login_callback);
        },
        onError: (err) => {
          login_callback();
          console.log(err);
        },
      });
    } catch (err) {
      login_callback();
      console.log(err);
    }
  }

  async logout() {
    this.set_user_info(null);
    if (this.state.authenticated == "auth") {
      await this.auth_client.logout();
    }
    this.state.authenticated = null;
    this.activate_anonymous_client();
  }
}
