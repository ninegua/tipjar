import AccountId "mo:accountid/AccountId";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import TrieSet "mo:base/TrieSet";

import CMC "canister:cmc";
import ICPLedger "canister:ledger";
import CyclesLedger "canister:cycles_ledger";
import Logger "canister:logger";
import Blackhole "canister:blackhole";

import Queue "mo:mutable-queue/Queue";
import Util "./Util";

shared (installation) actor class TipJar() = self {

  // Some administrative functions are only accessible by who created this canister.
  let OWNER = installation.caller;

  // ICP fees (TODO: this ideally should come from the ledger instead of being hard coded).
  let ICP_FEE = 10000 : Nat64;

  // TCycles fees (TODO: this ideally should come from the ledger instead of being hard coded).
  let TCYCLES_FEE = 100_000_000 : Cycle;

  // Minimum ICP deposit required before converting to cycles.
  let ICP_MIN_DEPOSIT = ICP_FEE * 10;

  // Minimum TCycles deposit required before converting to cycles.
  let TCYCLES_MIN_DEPOSIT = TCYCLES_FEE * 10;

  // The current method of converting ICP to cycles is by sending ICP to the
  // cycle minting canister with a memo.
  let CYCLE_MINTING_CANISTER = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
  let TOP_UP_CANISTER_MEMO = 0x50555054 : Nat64;

  // Wait for CHECK_INTERVAL before checking a canister's cycle balance again (8 hours).
  let CHECK_INTERVAL = 3600 * 8_000_000_000;

  // Period to call the poll function when there are pending deposits (every 5 seconds).
  let POLLING_PERIOD = 5 * 1_000_000_000;

  // The minimum gap (from the average) required before we topup a canister.
  let MIN_CYCLE_GAP = 100_000_000_000;

  // The minimum cycle balance for the TipJar canister to keep working.
  let MIN_RESERVE = 1_000_000_000_000;

  // The maximum number of canisters per user account.
  let MAX_CANISTERS_PER_USER = 200;

  // Interface of the IC00 management canister. At the moment we only need
  // 'deposit_cycles' to unconditionally send cycles to another canister.
  type Management = actor { deposit_cycles : ({canister_id: Principal}) -> async (); };

  type Balance = Util.Balance;
  type User = Util.User;
  type Canister = Util.Canister;
  type ICP = Util.ICP;
  type Cycle = Util.Cycle;
  type Queue<T> = Queue.Queue<T>;
  type Result<O, E> = Result.Result<O, E>;

  // General stats that we track.
  type TipJar = { var funded: Cycle; var allocated: Cycle; var donated: Cycle; };
  stable var tipjar : TipJar = { var funded = 0; var allocated = 0; var donated = 0 };

  // Return this canister's cycle balance without counting users' funds.
  func selfBalance() : Cycle {
    let cycles = Cycles.balance();
    if (cycles >= tipjar.funded) (cycles - tipjar.funded) else 0
  };

  // Convert Error to Text.
  func show_error(err: Error) : Text {
    debug_show({ error = Error.code(err); message = Error.message(err); })
  };

  // Helper to create logging function.
  func logger(name: Text) : Text -> async () {
    let prefix = "[" # Int.toText(Time.now()) # "/";
    func(s: Text) : async () {
      Logger.append([prefix # Int.toText(Time.now() / 1_000_000_000) # "] " # name # ": " # s])
    }
  };

  //////////////////////////////////////////////////////////////////////////
  // User related operations
  //////////////////////////////////////////////////////////////////////////

  stable var canisters_v3: Queue<Canister> = Queue.empty();
  stable var users_v3: Queue<User> = Queue.empty();

  // Use this function to get the user list instead of the stable variable itself.
  func all_users() : Queue<User> {
    return users_v3;
  };

  // Use this function to get the canister list instead of the stable variable itself.
  func all_canisters() : Queue<Canister> {
    return canisters_v3;
  };

  // Convert User to UserInfo.
  func userInfo(user: User) : Util.UserInfo {
    Util.userInfo(Principal.fromActor(self), user)
  };

  // Find a user by id.
  func findUser(id: Principal) : ?User {
    Util.findUser(all_users(), id)
  };

  // Same as 'findUser' but will create a new user if not found.
  func findOrCreateNewUser(id: Principal) : User {
    Util.findOrCreateNewUser(all_users(), id)
  };

  // Find a user by account id, and return user's principal.
  // FIXME: It may run out of execution limits before completion.
  public shared query func findUserByAccount(id: Text) : async ?Principal {
    let self_principal = Principal.fromActor(self);
    Option.map(Queue.find(all_users(), func (user: User) : Bool {
      let subaccount = Util.principalToSubAccount(user.id);
      let account = Util.toHex(AccountId.fromPrincipal(self_principal, ?subaccount));
      return account == id;
    }), func (user: User) : Principal { user.id })
  };

  type DelegateError = {
    #UserNotFound;
    #AlreadyDelegated;
    #DoubleDelegateNotAllowed;
  };

  // Delegate caller's account to the given user id.
  // The given user id doesn't need to have an existing account, but if it does,
  // it must be an already delegated account. it means double delegation is not
  // allowed.
  // Delegation can only be done once.
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

  type DepositCyclesError = {
    #UserNotFound;
    #NoCyclesToDeposit;
  };

  // Deposit available cycles to the given user's cycle account.
  public shared func depositCyclesFor(id: Principal) : async Result<Cycle, DepositCyclesError> {
    let amount = Cycles.available();
    if (amount == 0) {
      return #err(#NoCyclesToDeposit);
    };
    switch (findUser(id)) {
      case null { #err(#UserNotFound) };
      case (?user) {
        let accepted = Cycles.accept<system>(amount);
        user.balance.cycle := user.balance.cycle + accepted;
        return #ok(accepted)
      }
    }
  };

  // Return 'UserInfo' of the caller.
  // Note that it will return a default value even when the caller doesn't have an account.
  public shared query (arg) func aboutme() : async Util.UserInfo {
    userInfo(Option.get(findUser(arg.caller), Util.newUser(arg.caller)))
  };

  // Test function that directly calls ledger's notify. Used by admin for debugging only.
  public shared (arg) func testNotify(id: Principal, icp: ICP, height: ICPLedger.BlockIndex) {
    assert(arg.caller == OWNER);
    let user = Option.unwrap(findUser(id));
    let deposit : DepositV2 = { user = user; token = #ICP(icp) };
    depositing := ?(deposit, #Notify(height));
  };

  // Return self check statistics. Used by admin for debugging only.
  // TODO: also check balance discrepencies.
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
    #TooManyCanisters: Nat;
    #AccessDenied;
  };

  public type AllocationInput = {
    canister: Principal;
    alias: ?Text;
    allocated: Cycle;
  };

  // Create an allocation by setting aside some cycles that will be donated to a given canister.
  // Return updated UserInfo if successful.
  public shared (arg) func allocate(alloc: AllocationInput)
      : async Result<Util.UserInfo, AllocationError> {
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
        if (Queue.size(user.allocations) >= MAX_CANISTERS_PER_USER) {
          return #err(#TooManyCanisters(MAX_CANISTERS_PER_USER));
        };
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
  // System related operations
  //////////////////////////////////////////////////////////////////////////

  // We we are in stopping mode, new deposits or topup will not be processed.
  var stopping = false;

  type DepositToken = { #ICP: ICP; #TCYCLES: Cycle };

  type Deposit = { user: User; icp: ICP; };
  type DepositV2 = { user: User; token: DepositToken; };

  // Deposit queue. Require users to ping to be added to this queue.
  stable var deposits : Queue<Deposit> = Queue.empty();
  stable var deposits_v2 : Queue<DepositV2> = Queue.empty();

  type Stage = {
    #Mint;
    #MintCalled;
    #Notify: ICPLedger.BlockIndex;
    #NotifyCalled;
  };

  type Depositing = (DepositV2, Stage);

  // Current deposit in progress.
  var depositing : ?Depositing = null;

  // Stop future system activities after finishing pending ones.
  public shared (arg) func stop(val: Bool) {
    assert(arg.caller == OWNER);
    stopping := val;
  };

  // A user has to 'ping' to see updated account balance.
  // If some ICP is received, it will be inserted into the deposit queue.
  public shared (arg) func ping(for_user: ?Principal) {
    // Do nothing when we are stopping.
    if (stopping) return;
    let log = logger("ping");

    // Allow admin to ping on behalf of a user.
    let id = switch (for_user, arg.caller == OWNER) {
      case (?id, true) id;
      case _ (arg.caller);
    };

    // Disallow anonymous user.
    assert(not Principal.isAnonymous(id));

    let owner = Principal.fromActor(self);
    let subaccount = Util.principalToSubAccount(id);
    let account = Blob.fromArray(AccountId.fromPrincipal(owner, ?subaccount));
    try {
      let cycles = await CyclesLedger.icrc1_balance_of({ owner = owner; subaccount = ?Blob.fromArray(subaccount) });
      if (cycles >= TCYCLES_MIN_DEPOSIT and
          Option.isNull(Queue.find<DepositV2>(deposits_v2, func(x) { x.user.id == id })) and
          not (Option.getMapped(depositingInfo(), Util.eqId(id), false))) {
        let user = findOrCreateNewUser(id);
        ignore log("TCYCLES Balance " # debug_show({
          user = id;
          tcycles = cycles;
          delegate = Option.isSome(user.delegate);
          }));
        Util.setUserStatus(user, ?#DepositingCycle);
        ignore Queue.pushBack(deposits_v2, { user = user; token = #TCYCLES(cycles) });
        // TODO: trigger poll
        return;
      }
    } catch (err) {
      ignore log("TCycles Balance " # debug_show ({ user = id; err = show_error(err) }))
    };
    try {
      let icp = await ICPLedger.account_balance({ account = account });
      if (icp.e8s >= ICP_MIN_DEPOSIT and
          Option.isNull(Queue.find<DepositV2>(deposits_v2, func(x) { x.user.id == id })) and
          not (Option.getMapped(depositingInfo(), Util.eqId(id), false))) {
        let user = findOrCreateNewUser(id);
        ignore log("ICP Balance " # debug_show({
          user = id;
          icp = { old = user.balance.icp; new = icp };
          delegate = Option.isSome(user.delegate);
          }));
        ignore Util.setUserICP(user, icp);
        Util.setUserStatus(user, ?#DepositingCycle);
        ignore Queue.pushBack(deposits_v2, { user = user; token = #ICP(icp) });
        // TODO: trigger poll
        return;
      };
      switch (findUser(id)) {
        case null ();
        case (?user) {
          if (Util.setUserICP(user, icp)) {
            ignore log("ICP Balance " # debug_show({
              user = id;
              icp = { old = user.balance.icp; new = icp };
              delegate = Option.isSome(user.delegate);
            }));
          }
        }
      }
    } catch(err) {
      ignore log("ICP Balance " # debug_show ({ user = id; err = show_error(err) }))
    }
  };

  // Poll the deposit queue to convert from ICP to Cycle.
  // Inflight deposit should block canister topup, and vice versa.
  // Note that this is called from heartbeat, but can also be called manually by admin.
  public shared (arg) func poll() : async () {
    assert(arg.caller == Principal.fromActor(self) or arg.caller == OWNER);

    // Only start working on the next deposit if we are not stopping.
    if (Option.isNull(depositing) and not stopping) {
      switch (Queue.popFront(deposits_v2)) {
        case null return;
        case (?deposit) {
          // We must TRAP if there is a topup in progress to avoid changing deposit queue.
          assert(Option.isNull(topping_up));
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
        ignore log("BeforeTransfer " # debug_show({ user = user.id; deposit = deposit.token }));
        try {
          depositing := ?(deposit, #MintCalled);
          switch (deposit.token) {
            case (#ICP(icp)) {
              let result = await ICPLedger.transfer({
                    to = Blob.fromArray(account);
                    fee = { e8s = ICP_FEE };
                    memo = TOP_UP_CANISTER_MEMO;
                    from_subaccount = ?Blob.fromArray(from_subaccount);
                    amount = { e8s = icp.e8s - ICP_FEE };
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
            };
            case (#TCYCLES(cycles)) {
              let result = await CyclesLedger.withdraw({
                    to = Principal.fromActor(self);
                    from_subaccount = ?Blob.fromArray(from_subaccount);
                    amount = cycles - TCYCLES_FEE;
                    created_at_time = null;
                  });
              ignore log("AfterWithdraw " # debug_show({ result = result; }));
              switch result {
                case (#Err(err)) {
                  Util.setUserStatus(user, ?#DepositError(debug_show(err)));
                };
                case (#Ok(_)) {
                  tipjar.funded := tipjar.funded + cycles;
                  let beneficiary = Option.get(Option.chain(user.delegate, findUser), user);
                  let old_cycle = beneficiary.balance.cycle;
                  ignore Util.setUserCycle(beneficiary, beneficiary.balance.cycle + cycles);
                  ignore log("TopUpCycle " # debug_show({
                    user = beneficiary.id; delegate = beneficiary.id != user.id;
                    old = old_cycle; new = beneficiary.balance.cycle; }));
                  Util.setUserStatus(user, ?#DepositSuccess);
                }
              };
              depositing := null;
            }
          }
        } catch(err) {
          // TODO: notify user?
          ignore log("AfterTransfer " # show_error(err));
          depositing := null;
          Util.setUserStatus(user, ?#DepositError(Error.message(err)));
        };
      };
      case (?(deposit, #Notify(block_height))) {
        let user = deposit.user;
        let starting_cycles = Cycles.balance();
        ignore log("BeforeNotify " #
          debug_show({ user = user.id; deposit = deposit.token; starting_cycles = starting_cycles; }));
        try {
          depositing := ?(deposit, #NotifyCalled);
          let result = await CMC.notify_top_up({
                block_index = block_height;
                canister_id = Principal.fromActor(self);
              });
          switch result {
            case (#Err(err)) {
              ignore log("AfterNotify " #
                debug_show({ block_index = block_height; err = err; }));
              Util.setUserStatus(user, ?#DepositError(debug_show(err)));
            };
            case (#Ok(result)) {
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
            }
          }
        } catch(err) {
          Util.setUserStatus(user, ?#DepositError(Error.message(err)));
          ignore log("AfterNotify " # show_error(err))
        };
        depositing := null;
      };
      case (_) ();
    }
  };

  // When we are ready to topup a canister, we add it to the topup_queue.
  var topup_queue : Queue<Canister> = Queue.empty<Canister>();

  // The canister that we are currently trying to topup.
  var topping_up : ?Canister = null;

  // Poll the topup queue to top up the next canister.
  // Inflight topup should block user deposit, and vice versa.
  // Note that this is called from heartbeat, but can also be called manually by admin.
  public shared (arg) func topup() : async () {
    // Do nothing if we are already doing a topup, or caller is not self or admin.
    if (Option.isSome(topping_up) or
        not (arg.caller == Principal.fromActor(self) or arg.caller == OWNER)) return;

    switch (Queue.popFront(topup_queue)) {
      case null { return };
      case (?canister) {
        let log = logger("topup");
        let average = Util.roundUp(Util.getCanisterAverageCycle(canister));
        let cycle = Util.getCanisterCycle(canister);
        await log("checking canister " # debug_show(canister.id));
        if (cycle + MIN_CYCLE_GAP <= average) {
          let gap = Nat.sub(average, cycle);
          // can't allow tipjar to go below MIN_RESERVE.
          if (gap + MIN_RESERVE > Cycles.balance()) return;
          let donation = Util.deductCanisterDonation(canister, gap);
          if (donation == 0) { return };
          if (donation > gap) { return };                // Can't fail
          if (tipjar.funded < donation) {                // Can't fail
            ignore log("ConsistencyError " #
              debug_show({ funded = tipjar.funded; donation = donation }));
            return
          };
          if (tipjar.allocated < donation) {             // Can't fail
            ignore log("ConsistencyError " #
              debug_show({ allocated = tipjar.allocated; donation = donation }));
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
            ignore log("BeforeDeposit " #
              debug_show({ canister = canister.id; cycle = donation }));
            let management : Management = actor("aaaaa-aa");
            try {
              Cycles.add<system>(donation);
              await management.deposit_cycles({canister_id = canister.id});
              ignore log("AfterDeposit")
            } catch (err) {
              ignore log("AfterDeposit " # show_error(err))
            };
            topping_up := null;
          } else {
            ignore log("SelfDeposit "
              # debug_show({ canister = canister.id; cycle = donation }));
          }
        }
      }
    }
  };

  // Check and record next canister's cycle balance if enough time has elapsed
  // since last check. It is only meant to be called from self or owner.
  // Note that this function must not TRAP.
  public shared (arg) func check() : async () {
    assert(arg.caller == Principal.fromActor(self) or arg.caller == OWNER);
    let log = logger("check");

    // Check next canister to see if it needs to be topped up. Note that
    // all canisters are always arranged in the order of last_checked.
    switch (Queue.first(all_canisters())) {
      case null ();
      case (?canister) {
        if (canister.last_checked + CHECK_INTERVAL <= Time.now()) {
          canister.last_checked := Time.now();
          ignore Queue.rotate(all_canisters());
          ignore log("BeforeCheck " # debug_show({ canister = canister.id }));
          // Get canister's current cycle balance.
          // Note that the tipjar canister itself requires special handling.
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
          Util.addCanisterCycleCheck(canister, cycle);
          ignore log("AfterCheck " # debug_show({ cycle = cycle }));
          if (cycle + MIN_CYCLE_GAP <= Util.roundUp(Util.getCanisterAverageCycle(canister))) {
            ignore log("EnqueueTopUp " # debug_show({ canister = canister.id }));
            ignore Queue.pushBack(topup_queue, canister);
          }
        }
      }
    }
  };

  // To prevent re-entry of timer function
  var timer_in_progress = false;

  system func timer(setGlobalTimer : Nat64 -> ()) : async () {
    // Do nothing if we are stopping.
    if (stopping or timer_in_progress) return;
    timer_in_progress := true;

    // let log = logger("timer");

    // Check next canister's cycle balance
    try { await check() } catch(_) {};

    // Always try to poll to finish the current depositing process.
    try { await poll() } catch(_) {};

    // Always try to topup to finish queued topup jobs.
    try { await topup() } catch(_) {};

    timer_in_progress := false;
    let now = Time.now();
    setGlobalTimer(Nat64.fromIntWrap(now + POLLING_PERIOD));
  };

  //////////////////////////////////////////////////////////////////////////
  // Stats
  //////////////////////////////////////////////////////////////////////////

  type Stats = { donors: Nat; canisters: Nat; funded: Nat; allocated: Nat; donated: Nat; info: Text };
  type DepositingInfo = { id: Principal; token: DepositToken; stage: Stage };

  func depositingInfo() : ?DepositingInfo {
    Option.map(depositing, func(d: Depositing) : DepositingInfo {
      { id = d.0.user.id; token = d.0.token; stage = d.1 }
    })
  };

  // Return system stats, with extra info if the caller is admin.
  public shared query (msg) func stats() : async Stats {
    let info = if (msg.caller == OWNER) {
            debug_show({
              owner = OWNER;
              stopping = stopping;
              timer_in_progress = timer_in_progress;
              depositing = depositingInfo();
              topping_up = Option.map(topping_up, func(c: Canister) : Principal { c.id });
              pending_deposit = Queue.size(deposits_v2);
              pending_topup = Queue.size(topup_queue);
              balance = selfBalance();
              canisters = Array.map(Queue.toArray(all_canisters()),
                            func (x:Canister):Principal {x.id});
            })} else "";
    { donors = Queue.size(all_users());
      canisters = Queue.size(all_canisters());
      funded = tipjar.funded;
      allocated = tipjar.allocated;
      donated = tipjar.donated;
      info = info;
    }
  };

  //////////////////////////////////////////////////////////////////////////
  // Backup
  //////////////////////////////////////////////////////////////////////////
  public shared (arg) func export_users() : async [Util.UserInfo] {
    assert(arg.caller == OWNER);
    Array.map(Queue.toArray(all_users()), userInfo)
  };

  public shared (arg) func export_canisters() : async [Util.CanisterInfo] {
    assert(arg.caller == OWNER);
    Array.map(Queue.toArray(all_canisters()), Util.canisterInfo)
  };

  system func postupgrade() {
    for (x in Queue.toIter(deposits)) {
      ignore Queue.pushBack(deposits_v2, { user = x.user; token = #ICP(x.icp) })
    };
    deposits := Queue.empty();
  }
}
