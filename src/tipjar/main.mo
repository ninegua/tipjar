import AccountId "mo:accountid/AccountId";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import TrieSet "mo:base/TrieSet";

import Ledger "canister:ledger";
import Logger "canister:logger";
import Blackhole "canister:blackhole";

import Queue "mo:mutable-queue/Queue";
import Util "./Util";

shared (installation) actor class TipJar() = self {
  let OWNER = installation.caller;
  let FEE = 10000 : Nat64;
  let MIN_DEPOSIT = FEE * 2;
  let CYCLE_MINTING_CANISTER = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
  let TOP_UP_CANISTER_MEMO = 0x50555054 : Nat64;
  // let CHECK_INTERVAL = 24 * 3600 * 1_000_000_000; // 24 hours in nano seconds 
  let CHECK_INTERVAL = 3600 * 8_000_000_000; // 8 hour
  let MIN_CYCLE_GAP = 100_000_000_000; // minimum gap required before we send in refill
  let MIN_RESERVE = 1_000_000_000_000; // this canister needs at least this much

  type Management = actor { deposit_cycles : ({canister_id: Principal}) -> async (); };

  type Balance = Util.Balance;
  type User = Util.User;
  type Canister = Util.Canister;
  type Token = Util.Token;
  type Cycle = Util.Cycle;
  type Queue<T> = Queue.Queue<T>;
  type Result<O, E> = Result.Result<O, E>;

  type TipJar = { var funded: Cycle; var allocated: Cycle; var donated: Cycle; };
  stable var tipjar : TipJar = { var funded = 0; var allocated = 0; var donated = 0 };

  func selfBalance() : Cycle {
    let cycles = Cycles.balance();
    if (cycles >= tipjar.funded) (cycles - tipjar.funded) else 0
  };

  stable var canisters_v3: Queue<Canister> = Queue.empty();
  stable var users_v3: Queue<User> = Queue.empty();

  func all_users() : Queue<User> {
    return users_v3;
  };

  func all_canisters() : Queue<Canister> {
    return canisters_v3;
  };

  func userInfo(user: User) : Util.UserInfo {
    Util.userInfo(Principal.fromActor(self), user)
  };

  func findUser(id: Principal) : ?User {
    Util.findUser(all_users(), id)
  };

  func findOrCreateNewUser(id: Principal) : User {
    Util.findOrCreateNewUser(all_users(), id)
  };

  type DelegateError = {
    #UserNotFound;
    #AlreadyDelegated;
    #DoubleDelegateNotAllowed;
  };

  public shared (arg) func delegate(id: Principal) : async Result<(), DelegateError> {
    let log = logger("delegate");
    assert(not Principal.isAnonymous(id));
    switch (findUser(arg.caller)) {
      case null { #err(#UserNotFound) };
      case (?user) {
        if (Util.delegateUser(user, id)) {
          ignore log("Delegated " # debug_show({ from = user.id; to = id; 
                                                 balance = user.balance }));
          if (user.balance.cycle > 0 or Queue.size(user.allocations) > 0) {
            let delegate = Util.findOrCreateNewUser(all_users(), id);
            // target user cannot be delegated
            if (Option.isSome(delegate.delegate)) {
              ignore log("DoublyDelegated " # debug_show({ user = userInfo(delegate) }));
               return #err(#DoubleDelegateNotAllowed);
            };
            Util.transferAccount(user, delegate);
          };
          #ok(()) 
        } else {
          ignore log("AlreadyDelegated " # debug_show({
            user = userInfo(user); 
            delegate = Option.map(Option.chain(user.delegate, findUser), userInfo); }));
          #err(#AlreadyDelegated)
        }
      };
    }
  };

  public shared query (arg) func aboutme() : async Util.UserInfo {
    userInfo(Option.get(findUser(arg.caller), Util.newUser(arg.caller)))
  };

  stable var whitelist : Queue<{id: Principal}> = Queue.empty();

  public shared (arg) func allow(id: Principal) {
    assert(arg.caller == OWNER);
    ignore Queue.pushFront({id = id}, whitelist);
  };

  public shared (arg) func testNotify(id: Principal, icp: Token, height: Ledger.BlockIndex) {
    assert(arg.caller == OWNER);
    let user = Option.unwrap(findUser(id));
    let deposit : Deposit = { user = user; icp = icp };
    depositing := ?(deposit, #Notify(height));
  };

  public shared (arg) func testDelegate(from: Principal, to: Principal) {
    assert(arg.caller == OWNER);
    switch (findUser(from), findOrCreateNewUser(to)) {
      case (?from, to) {
       assert(Util.delegateUser(from, to.id));
       let log = logger("testDelegate");
       ignore log("Delegated " # debug_show({ from = from.id; to = to.id; 
                                              balance = from.balance }));
        Util.transferAccount(from, to);
      };
      case _ {
        assert(false);
      };
    }
  };

  public shared (arg) func selfCheck() : async Text {
    assert(arg.caller == OWNER);
    // (userid, canisterid)
    type Pair = (Principal, Principal);
    func hash(x: Pair) : Hash.Hash {
      Hash.hashNat8([Principal.hash(x.0), Principal.hash(x.1)])
    };
    func eq(x: Pair, y: Pair) : Bool { x.0 == y.0 and x.1 == y.1 };
    var set = TrieSet.empty<Pair>();
    var out = "";
    for (user in Queue.toIter(all_users())) {
       out := out # "User " # Principal.toText(user.id) # "\n";
       for (alloc in Queue.toIter(user.allocations)) {
          let elem = (user.id, alloc.canister.id);
          if (TrieSet.mem(set, elem, hash(elem), eq)) {
             out := out # "  Duplicate allocation " # Principal.toText(alloc.canister.id) # "\n";
          };
          set := TrieSet.put(set, elem, hash(elem), eq);
       } 
    };
    for (canister in Queue.toIter(all_canisters())) {
       out := out # "Canister " # Principal.toText(canister.id) # "\n";
       for (donor in Queue.toIter(canister.donors)) {
          let elem = (donor.id, canister.id);
          if (not TrieSet.mem(set, elem, hash(elem), eq)) {
            out := out # "\n  Missing donor " # Principal.toText(donor.id) # "\n";
          }
       }
    };
    out
  };

  type AllocationError = {
    #CanisterStatusError: Text;
    #InsufficientBalance: Cycle;
    #UserDoesNotExist;
    #AliasTooLong: Nat;
    #AliasTooShort: Nat;
    #AccessDenied;
  };

  public shared (arg) func allocate(alloc: Util.AllocationInput) : async Result<Util.UserInfo, AllocationError> {
    if (Option.isNull(Queue.find<{id:Principal}>(whitelist, Util.eqId(arg.caller)))) {
      return #err(#AccessDenied)
    };
    let log = logger("allocate");
    switch (alloc.alias) {
      case null ();
      case (?s) {
        if (s.size() < 3) {
          return #err(#AliasTooShort(3));
        } else if (s.size() > 20) {
          return #err(#AliasTooLong(20));
        }
      }
    };
    switch (findUser(arg.caller)) {
      case null { #err(#UserDoesNotExist) };
      case (?user) {
        switch (Util.findCanister(all_canisters(), alloc.canister)) {
          case (?canister) {
            let before = Util.getCanisterAllocation(canister);
            switch (Util.setAllocation(user, canister, alloc.alias, alloc.allocated)) {
              case (#err(usable)) {
                #err(#InsufficientBalance(usable))
              };
              case (#ok(allocation)) {
               let after = Util.getCanisterAllocation(canister);
               tipjar.allocated := tipjar.allocated + after - before;
               ignore log("Allocated " # 
                 debug_show({ asked = alloc; allocated = Util.allocationInfo(allocation) }));
               #ok(userInfo(user))
              }
            }
          };
          case null {
            try {
              ignore log("BeforeCanisterStatus " # debug_show({ asked = alloc }));
              let cycle = if (alloc.canister == Principal.fromActor(self)) {
                  selfBalance()
                }  else {
                  (await Blackhole.canister_status({ canister_id = alloc.canister })).cycles;
                };
              let canister = Util.findOrAddCanister(all_canisters(), alloc.canister, cycle);
              let before = Util.getCanisterAllocation(canister);
              switch (Util.setAllocation(user, canister, alloc.alias, alloc.allocated)) {
                case (#err(usable)) {
                  #err(#InsufficientBalance(usable))
                };
                case (#ok(allocation)) {
                  ignore log("AfterCanisterStatus " # 
                    debug_show({ allocated = Util.allocationInfo(allocation) }));
                  let after = Util.getCanisterAllocation(canister);
                  tipjar.allocated := tipjar.allocated + after - before;
                  #ok(userInfo(user))
                }
              };
            } catch(err) {
              ignore log("AfterCanisterStatus " # show_error(err));
              #err(#CanisterStatusError(Error.message(err)))
            }
          };
        } 
      }
    }
  };

  //////////////////////////////////////////////////////////////////////////
  
  type Deposit = { user: User; icp: Token; };

  stable var deposits : Queue<Deposit> = Queue.empty();
  type Stage = {
    #Mint;
    #MintCalled;
    #Notify: Ledger.BlockIndex;
    #NotifyCalled;
  };
  type Depositing = (Deposit, Stage);
  var depositing : ?Depositing = null;
  var stopping = false;

  type Stats = { donors: Nat; canisters: Nat; funded: Nat; allocated: Nat; donated: Nat; info: Text };
  type DepositingInfo = { id: Principal; icp: Token; stage: Stage };

  func depositingInfo() : ?DepositingInfo { 
    Option.map(depositing, func(d: Depositing) : DepositingInfo {
      { id = d.0.user.id; icp = d.0.icp; stage = d.1 }
    })
  };

  public shared query (msg) func stats() : async Stats {
    let info = if (msg.caller == OWNER) {
            debug_show({
              owner = OWNER;
              stopping = stopping; 
              depositing = depositingInfo();
              topping_up = Option.map(topping_up, func(c: Canister) : Principal { c.id });
              pending_deposit = Queue.size(deposits); 
              pending_topup = Queue.size(topup_queue);
              balance = selfBalance();
              canisters = Array.map(Queue.toArray(all_canisters()), func (x:Canister):Principal {x.id});})
          } else "";
    { donors = Queue.size(all_users());
      canisters = Queue.size(all_canisters());
      funded = tipjar.funded;
      allocated = tipjar.allocated;
      donated = tipjar.donated;
      info = info;
    }
  };

  public shared (arg) func stop(val: Bool) {
    assert(arg.caller == OWNER);
    stopping := val;
  };

  // A user ping to update their account balance.
  // If some ICP is received, it will be inserted into the deposit queue.
  public shared (arg) func ping(for_user: ?Principal) {
    if (stopping) return;
    let log = logger("ping");
    let id = switch (for_user, arg.caller == OWNER) {
      case (?id, true) id;
      case _ (arg.caller);
    };
    assert(not Principal.isAnonymous(id));
    let subaccount = Util.principalToSubAccount(id);
    let account = Blob.fromArray(AccountId.fromPrincipal(Principal.fromActor(self), ?subaccount));
    try {
      let icp = await Ledger.account_balance({ account = account });
      if (icp.e8s >= MIN_DEPOSIT and 
          Option.isNull(Queue.find<Deposit>(deposits, func(x) { x.user.id == id })) and 
          not (Option.getMapped(depositingInfo(), Util.eqId(id), false))) {
        let user = findOrCreateNewUser(id);
        ignore log("AccountBalance " # debug_show({
          user = id; 
          icp = { old = user.balance.icp; new = icp }; 
          delegate = Option.isSome(user.delegate);
          }));
        ignore Util.setUserICP(user, icp);
        Util.setUserStatus(user, ?#DepositingCycle);
        ignore Queue.pushBack(deposits, { user = user; icp = icp });
        return;
      };
      switch (findUser(id)) {
        case null ();
        case (?user) {
          if (Util.setUserICP(user, icp)) {
            ignore log("AccountBalance " # debug_show({
              user = id; 
              icp = { old = user.balance.icp; new = icp };
              delegate = Option.isSome(user.delegate);
            }));
          }
        }
      }
    } catch(err) {
      ignore log("AccountBalance " # debug_show ({ user = id; err = show_error(err) }))
    }
  };

  // Poll the deposit queue to convert from ICP to Cycle.
  // Inflight deposit should block canister topup, and vice versa.
  public shared (arg) func poll() {
    if (stopping or not (arg.caller == Principal.fromActor(self) or arg.caller == OWNER)) return;
    if (Option.isNull(depositing)) {
      switch (Queue.popFront(deposits)) {
        case null {
          return;
        };
        case (?deposit) { 
          assert(Option.isNull(topping_up)); // TRAP if there is topping up inflight
          depositing := ?(deposit, #Mint)
        };
      }
    };
    let log = logger("poll");
    switch depositing {
      case (?(deposit, #Mint)) {
        let user = deposit.user;
        let from_subaccount = Util.principalToSubAccount(user.id);
        let to_subaccount = Util.principalToSubAccount(Principal.fromActor(self));
        let account = AccountId.fromPrincipal(CYCLE_MINTING_CANISTER, ?to_subaccount);
        ignore log("BeforeTransfer " # debug_show({ user = user.id; deposit = deposit.icp }));
        try {
          depositing := ?(deposit, #MintCalled);
          let result = await Ledger.transfer({
                to = Blob.fromArray(account);
                fee = { e8s = FEE };
                memo = TOP_UP_CANISTER_MEMO;
                from_subaccount = ?Blob.fromArray(from_subaccount);
                amount = { e8s = deposit.icp.e8s - 2 * FEE };
                created_at_time = null;
              });
          ignore log("AfterTransfer " # debug_show({ result = result; }));
          switch (result) {
            case (#Ok(block_height)) {
              depositing := ?(deposit, #Notify(block_height));
            };
            case (#Err(err)) {
              depositing := null;
              Util.setUserStatus(user, ?#DepositError(debug_show(err)));
            }
          }
        } catch(err) {
          // TODO: notify user?
          ignore log("AfterTransfer " # show_error(err));
          depositing := null;
          Util.setUserStatus(user, ?#DepositError(Error.message(err)));
        }
      };
      case (?(deposit, #Notify(block_height))) {
        let user = deposit.user;
        let from_subaccount = Util.principalToSubAccount(user.id);
        let to_subaccount = Util.principalToSubAccount(Principal.fromActor(self));
        let starting_cycles = Cycles.balance();
        ignore log("BeforeNotify " # 
          debug_show({ user = user.id; deposit = deposit.icp; starting_cycles = starting_cycles; }));
        try {
          depositing := ?(deposit, #NotifyCalled);
          await Ledger.notify_dfx({
              to_canister = CYCLE_MINTING_CANISTER;
              block_height = block_height;
              from_subaccount = ?Blob.fromArray(from_subaccount);
              to_subaccount = ?Blob.fromArray(to_subaccount);
              max_fee = { e8s = FEE };
            });
          let ending_cycles = Cycles.balance();
          ignore log("AfterNotify " # debug_show({ ending_cycles = ending_cycles; }));
          if (ending_cycles < starting_cycles) {
            // TODO: notify user
          } else {
            tipjar.funded := tipjar.funded + ending_cycles - starting_cycles; 
            let beneficiary = Option.get(Option.chain(user.delegate, findUser), user);
            let old_cycle = beneficiary.balance.cycle;
            ignore Util.setUserCycle(beneficiary, 
              beneficiary.balance.cycle + ending_cycles - starting_cycles); 
            ignore log("TopUpCycle " # debug_show({
              user = beneficiary.id; delegate = beneficiary.id != user.id;
              old = old_cycle; new = beneficiary.balance.cycle; }));
          };
          Util.setUserStatus(user, ?#DepositSuccess);
        } catch(err) {
          Util.setUserStatus(user, ?#DepositError(Error.message(err)));
          ignore log("AfterNotify " # show_error(err))
        };
        depositing := null;
      };
      case (_) ();
    }
  };

  var topup_queue : Queue<Canister> = Queue.empty<Canister>();
  var topping_up : ?Canister = null;
  public shared (arg) func topup() {
    if (stopping or Option.isSome(topping_up) or 
        not (arg.caller == Principal.fromActor(self) or arg.caller == OWNER)) return;
    switch (Queue.popFront(topup_queue)) {
      case null { return };
      case (?canister) {
        let log = logger("topup");
        let average = Util.roundUp(Util.getCanisterDailyAverage(canister));
        let cycle = Util.getCanisterCycle(canister);
        if (cycle + MIN_CYCLE_GAP <= average) {
          let gap = Nat.sub(average, cycle);
          // can't allow tipjar to go below MIN_RESERVE.
          if (gap + MIN_RESERVE > Cycles.balance()) return; 
          switch (Util.deductCanisterDonation(canister, gap)) {
            case null return;
            case (?donation) {
              if (donation > gap) { return };                // Can't fail
              if (tipjar.funded < donation) {                // Can't fail
                ignore log("ConsistencyError " # debug_show({ funded = tipjar.funded; donation = donation }));
                return
              };
              if (tipjar.allocated < donation) {             // Can't fail
                ignore log("ConsistencyError " # debug_show({ allocated = tipjar.allocated; donation = donation }));
                return
              };
              Util.addDonation(canister, donation);
              tipjar.funded := tipjar.funded - donation;
              tipjar.donated := tipjar.donated + donation;
              tipjar.allocated := tipjar.allocated - donation;
              // only need to make deposit call when not topping up self
              if (canister.id != Principal.fromActor(self)) {
                assert(Option.isNull(depositing)); // TRAP when depositing is in progress
                topping_up := ?canister;
                ignore log("BeforeDeposit " # debug_show({ canister = canister.id; cycle = donation }));
                let management : Management = actor("aaaaa-aa");
                try {
                  Cycles.add(donation);
                  await management.deposit_cycles({canister_id = canister.id});
                  ignore log("AfterDeposit")
                } catch (err) {
                  ignore log("AfterDeposit " # show_error(err))
                };
                topping_up := null;
              } else {
                ignore log("SelfDeposit " # debug_show({ canister = canister.id; cycle = donation }));
              }
            }
          }
        }
      }
    };
    // We only reach here after a successful topup
    topup()
  };

  system func heartbeat() : async () {
    if (stopping) return;
    poll();
    switch (Queue.first(all_canisters())) {
      case null ();
      case (?canister) {
        if (canister.last_checked + CHECK_INTERVAL < Time.now()) {
          let log = logger("heartbeat");
          canister.last_checked := Time.now();
          ignore Queue.rotate(all_canisters());
          ignore log("BeforeCheck " # debug_show({ canister = canister.id }));
          // This canister is specially handled.
          let cycle = if (canister.id == Principal.fromActor(self)) {
             selfBalance()
          } else {
            try {
              let status = await Blackhole.canister_status({ canister_id = canister.id });
              canister.error := null;
              status.cycles
            } catch(err) {
              canister.error := ?debug_show(Error.code(err));
              ignore log("AfterCheck " # show_error(err));
              return;
            }
          };
          Util.setCanisterCycle(canister, cycle);
          ignore log("AfterCheck " # debug_show({ cycle = cycle }));
          if (cycle + MIN_CYCLE_GAP <= Util.roundUp(Util.getCanisterDailyAverage(canister))) {
            ignore log("EnqueueTopUp " # debug_show({ canister = canister.id }));
            ignore Queue.pushBack(topup_queue, canister);
            topup();
          }
        }
      }
    }
  };

  func show_error(err: Error) : Text {
    debug_show({ error = Error.code(err); message = Error.message(err); })
  };

  func logger(name: Text) : Text -> async () {
    let prefix = "[" # Int.toText(Time.now()) # "/"; 
    func(s: Text) : async () {
      Logger.append([prefix # Int.toText(Time.now() / 1_000_000_000) # "] " # name # ": " # s])
    }
  };
}
