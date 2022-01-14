import AccountId "mo:accountid/AccountId";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Prelude "mo:base/Prelude";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";

import Queue "mo:mutable-queue/Queue";

module Util {

  let MAX_CYCLE_HISTORY = 10;

  public type Queue<T> = Queue.Queue<T>;
  public type Cycle = Nat;

  public type Token = { e8s: Nat64 };

  public type Balance = { icp: { var e8s: Nat64 }; var cycle: Cycle };

  public type BalanceInfo = { icp: Token; cycle: Cycle };

  public type Allocation = {
    canister: Canister;
    var alias: ?Text;
    var allocated: Cycle;
    var donated: Cycle;
  };

  public type AllocationInput = {
    canister: Principal;
    alias: ?Text;
    allocated: Cycle;
  };

  public type AllocationInfo = {
    canister: CanisterInfo;
    alias: Text;
    allocated: Cycle;
    donated: Cycle;
  };

  public type UserStatus = {
    #DepositingCycle;
    #DepositSuccess;
    #DepositError: Text;
  };

  public type User = {
    id: Principal;
    var delegate: ?Principal; // all balance should go to the delegate
    balance: Balance;
    allocations: Queue<Allocation>;
    var last_updated: Time.Time;
    var status: ?UserStatus;
  };

  public type UserInfo = {
    id: Principal;
    account: Text;
    balance: BalanceInfo;
    allocations: [AllocationInfo];
    last_updated: Time.Time;
    status: ?UserStatus;
  };

  public type Donor = {
    id: Principal;
    allocation: Allocation;
  };

  public type Usage = {
    cycle: Cycle;
    period: Time.Time;
  };

  public type Canister = {
    id: Principal;
    first_checked: Time.Time;
    var last_checked: Time.Time;
    var last_donated: Time.Time;
    cycle_balances: Queue<Cycle>;
    usage: Queue<Usage>;
    donors: Queue<Donor>;
    var error: ?Text;
  };

  public type CanisterInfo = {
    id: Principal;
    first_checked: Time.Time;
    last_checked: Time.Time;
    last_checked_balance: Cycle;
    average_balance: Cycle;
    total_allocation: Cycle;
    total_donated: Cycle;
    usage: [Usage];
    error: ?Text;
  };

  func unwrap<T>(x: ?T) : T {
    switch x {
      case null { Prelude.unreachable() };
      case (?x_) { x_ };
    }
  };

  public func balanceInfo(balance: Balance) : BalanceInfo {
    { icp = { e8s = balance.icp.e8s }; cycle = balance.cycle }
  };

  public func canisterInfo(canister: Canister) : CanisterInfo {
    { id = canister.id;
      first_checked = canister.first_checked;
      last_checked = canister.last_checked;
      last_checked_balance = getCanisterCycle(canister);
      average_balance = getCanisterDailyAverage(canister);
      total_allocation = getCanisterAllocation(canister);
      total_donated = getCanisterDonated(canister);
      usage = Queue.toArray(canister.usage);
      error = canister.error;
    }
  };

  public func allocationInfo(allocation: Allocation) : AllocationInfo {
    { canister = canisterInfo(allocation.canister);
      alias = Option.get(allocation.alias, "");
      allocated = allocation.allocated;
      donated = allocation.donated; }
  };

  public func userInfo(self: Principal, user: User) : UserInfo {
    let subaccount = Util.principalToSubAccount(user.id);
    let account = toHex(AccountId.fromPrincipal(self, ?subaccount));
    { id = user.id;
      account = account;
      balance = balanceInfo(user.balance);
      allocations = Iter.toArray(Iter.map(Queue.toIter(user.allocations), allocationInfo));
      last_updated = user.last_updated;
      status = user.status;
    }
  };

  // Convert principal id to subaccount id.
  public func principalToSubAccount(id: Principal) : [Nat8] {
    let p = Blob.toArray(Principal.toBlob(id));
    Array.tabulate(32, func(i : Nat) : Nat8 {
      if (i >= p.size() + 1) 0
      else if (i == 0) (Nat8.fromNat(p.size()))
      else (p[i - 1])
    })
  };

  // Return false if it is already delegated.
  public func delegateUser(user: User, delegate: Principal) : Bool {
    switch (user.delegate) {
      case null { user.delegate := ?delegate; true };
      case (?_) { false };
    }
  };

  // transfer everything except ICP
  public func transferAccount(from_user: User, to_user: User) {
    assert(Option.get(Option.map(from_user.delegate, 
      func (id: Principal) : Bool { id == to_user.id }), false));
    let now = Time.now();
    to_user.balance.cycle := to_user.balance.cycle + from_user.balance.cycle;
    from_user.balance.cycle := 0;
    from_user.last_updated := now;
    to_user.last_updated := now;
    label L loop {
      switch (Queue.popFront(from_user.allocations)) {
        case null { break L; };
        case (?alloc) {
          let donor = removeDonor(alloc.canister, from_user.id);
          assert(Option.isSome(donor));
          switch (findAllocation(to_user, alloc.canister.id)) {
            case null {
              ignore Queue.pushBack(to_user.allocations, alloc);
              ignore Queue.pushBack(alloc.canister.donors,
                { id = to_user.id; allocation = alloc })
            };
            case (?existing_alloc) {
              existing_alloc.allocated := existing_alloc.allocated + alloc.allocated;
              existing_alloc.donated := existing_alloc.donated + alloc.donated;
            }
          }
        }
      }
    }
  };

  public func findUser(users: Queue<User>, id: Principal) : ?User {
    Queue.find(users, eqId(id))
  };

  public func newUser(id: Principal) : User {
    { id = id;
      var delegate = null;
      balance = { icp = { var e8s = 0 : Nat64 }; var cycle = 0 };
      allocations = Queue.empty();
      var last_updated = 0;
      var status = null;
    };
  };

  public func findOrCreateNewUser(users: Queue<User>, id: Principal) : User {
    switch (findUser(users, id)) {
      case (?user) user;
      case null {
        let user = newUser(id);
        user.last_updated := Time.now();
        ignore Queue.pushFront(user, users);
        user
      }
    }
  };

  public func setUserStatus(user: User, status: ?UserStatus) {
      user.status := status;
      user.last_updated := Time.now();
  };

  public func setUserICP(user: User, icp: Token) : Bool {
    if (icp.e8s != user.balance.icp.e8s) {
      user.balance.icp.e8s := icp.e8s;
      user.last_updated := Time.now();
      true
    } else false
  };

  public func setUserCycle(user: User, cycle: Cycle) : Bool {
    if (cycle != user.balance.cycle) {
      user.balance.cycle := cycle;
      user.last_updated := Time.now();
      true
    } else false
  };

  public func getCanisterCycle(canister: Canister) : Cycle {
    unwrap(Queue.last(canister.cycle_balances))
  };

  public func getCanisterAllocation(canister: Canister) : Cycle {
    Queue.fold(canister.donors, 0, 
      func(s: Cycle, alloc: Donor) : Cycle { s + alloc.allocation.allocated });
  };

  public func getCanisterDonated(canister: Canister) : Cycle {
    Queue.fold(canister.donors, 0, 
        func(s: Cycle, alloc: Donor) : Cycle { s + alloc.allocation.donated });
  };

  // Round up cycle to avoid falling average trap
  public func roundUp(cycle: Cycle) : Cycle {
    (cycle + 999_999_999_999) / 1_000_000_000_000 * 1_000_000_000_000
  };

  public func getCanisterDailyAverage(canister: Canister) : Cycle {
    let cycles = canister.cycle_balances;
    Queue.fold(cycles, 0, Nat.add) / Queue.size(cycles)
  };

  public func setCanisterCycle(canister: Canister, cycle: Cycle) {
    while (Queue.size(canister.cycle_balances) >= MAX_CYCLE_HISTORY) {
      ignore Queue.popFront(canister.cycle_balances);
    };
    ignore Queue.pushBack(canister.cycle_balances, cycle);
    canister.last_checked := Time.now();
  };

  public func deductCanisterDonation(canister: Canister, gap: Cycle) : ?Cycle {
    if (gap == 0) { return null };
    let total_allocated = getCanisterAllocation(canister);
    if (total_allocated == 0) { return null };
    var total = 0;
    for (donor in Queue.toIter(canister.donors)) {
      let allocation = donor.allocation;
      var to_donate = gap * allocation.allocated / total_allocated;
      if (to_donate > allocation.allocated) {
        to_donate := allocation.allocated;
      };
      total := total + to_donate;
      allocation.allocated := allocation.allocated - to_donate;
      allocation.donated := allocation.donated + to_donate;
    };
    ?total
  };

  public func findAllocation(user: User, canister_id: Principal) : ?Allocation {
    Queue.find(user.allocations, func (alloc: Allocation) : Bool { alloc.canister.id == canister_id })
  };

  // Return max usable cycle if it is less than required.
  public func setAllocation(user: User, canister: Canister, alias: ?Text, amount: Cycle) : Result.Result<Allocation, Cycle> {
    let now = Time.now();
    func setAlias(alloc: Allocation) {
      let set = switch (alloc.alias, alias) {
        case (_, null) false;
        case (?s, ?t) { if (s != t) { alloc.alias := alias; true } else false };
        case (null, ?_) { alloc.alias := alias; true };
      };
      if set {
        user.last_updated := now;
      }
    };
    switch (findAllocation(user, canister.id)) {
      case (?alloc) {
        var total = alloc.allocated + user.balance.cycle;
        if (total >= amount) {
          ignore setUserCycle(user, total - amount);
          alloc.allocated := amount;
          setAlias(alloc);
          #ok(alloc)
        } else (#err(total));
      };
      case null {
        if (user.balance.cycle >= amount) {
          ignore setUserCycle(user, user.balance.cycle - amount);
          let alloc : Allocation = { canister = canister; var alias = null; 
                                     var allocated = amount; var donated = 0 };
          let donor : Donor = { id = user.id; allocation = alloc };
          ignore Queue.pushFront(donor, canister.donors);
          ignore Queue.pushFront(alloc, user.allocations);
          user.last_updated := Time.now();
          setAlias(alloc);
          #ok(alloc)
        } else { 
          #err(user.balance.cycle)
        }
      };
    }
  };

  public func removeDonor(canister: Canister, id: Principal) : ?Donor {
    Queue.removeOne(canister.donors, eqId(id))
  };

  public func addDonation(canister: Canister, cycle: Cycle) {
    while (Queue.size(canister.usage) >= MAX_CYCLE_HISTORY) {
      ignore Queue.popFront(canister.usage);
    };
    let now = Time.now();
    ignore Queue.pushBack(canister.usage, 
      { cycle = cycle; period = now - canister.last_donated });
    canister.last_donated := now;
  };

  public func findCanister(canisters: Queue<Canister>, id: Principal) : ?Canister {
    Queue.find(canisters, eqId(id))
  };

  public func findOrAddCanister(canisters: Queue<Canister>, id: Principal, cycle: Cycle) : Canister {
    switch (findCanister(canisters, id)) {
      case (?canister) canister;
      case null {
        let now = Time.now();
        let canister : Canister = {
              id = id;
              first_checked = now;
              var last_checked = now;
              var last_donated = now;
              cycle_balances = Queue.make(cycle);
              usage = Queue.empty();
              donors = Queue.empty();
              var error = null;
            };
        ignore Queue.pushFront(canister, canisters);
        canister
      }
    }
  };

  public func eqId(id: Principal) : { id: Principal } -> Bool {
    func (x: { id: Principal }) { x.id == id }
  };

  let hexChars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];

  public func toHex(arr: [Nat8]): Text {
    Text.join("", Iter.map<Nat8, Text>(Iter.fromArray(arr), func (x: Nat8) : Text {
      let a = Nat8.toNat(x / 16);
      let b = Nat8.toNat(x % 16);
      hexChars[a] # hexChars[b]
    }))
  };
}
