import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Nat64 "mo:core/Nat64";
import Option "mo:core/Option";
import Principal "mo:core/Principal";
import Result "mo:core/Result";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import PriorityQueue "mo:core/PriorityQueue";
import Queue "mo:mutable-queue/Queue";
import Util "../tipjar/Util";

// ─── Assertion helpers ───

func fail(msg : Text) : None {
  Runtime.trap("FAIL: " # msg);
};

func eqNat(a : Nat, b : Nat, msg : Text) {
  if (a != b) { fail(msg # " expected=" # debug_show(b) # " got=" # debug_show(a)) };
};

func eqNat64(a : Nat64, b : Nat64, msg : Text) {
  if (a != b) { fail(msg # " expected=" # debug_show(b) # " got=" # debug_show(a)) };
};

func eqText(a : Text, b : Text, msg : Text) {
  if (a != b) { fail(msg # " expected=" # debug_show(b) # " got=" # debug_show(a)) };
};

func eqBool(a : Bool, b : Bool, msg : Text) {
  if (a != b) { fail(msg # " expected=" # debug_show(b) # " got=" # debug_show(a)) };
};

func isSome<T>(o : ?T, msg : Text) {
  if (Option.isNull(o)) { fail(msg # " expected Some") };
};

func isNull<T>(o : ?T, msg : Text) {
  if (Option.isSome(o)) { fail(msg # " expected null") };
};

func pass(msg : Text) {
  Debug.print("PASS: " # msg);
};

// ─── Helper: create test principals ───

let p1 = Principal.fromText("2ibo7-dia");
let p2 = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
let p3 = Principal.fromText("k7h5q-jyaaa-aaaan-qaaaq-cai");

// ─── Helpers ───

func makeCanister(id : Principal, cycle : Nat) : Util.Canister {
  let now : Int = 0;
  {
    id = id;
    first_checked = now;
    var last_checked = now;
    var last_donated = now;
    cycle_balances = Queue.make(cycle);
    usage = Queue.empty();
    donors = Queue.empty();
    var error = null;
  }
};

// ═══════════════════════════════════════════════════════════
// Test: findUser / findOrCreateNewUser
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test findUser / findOrCreateNewUser ---");

let users : Queue.Queue<Util.User> = Queue.empty();
let u3 = Util.findOrCreateNewUser(users, p1);
eqNat(Principal.toBlob(u3.id).size(), Principal.toBlob(p1).size(), "findOrCreateNewUser id");
eqNat(Queue.size(users), 1, "findOrCreateNewUser pushes user");
let found = Util.findUser(users, p1);
isSome(found, "findUser finds existing user");
let notFound = Util.findUser(users, p2);
isNull(notFound, "findUser returns null for non-existent");

// findOrCreateNewUser again should not duplicate
let _u3again = Util.findOrCreateNewUser(users, p1);
eqNat(Queue.size(users), 1, "findOrCreateNewUser does not duplicate");
pass("findUser / findOrCreateNewUser");

// ═══════════════════════════════════════════════════════════
// Test: delegateUser
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test delegateUser ---");

let dUser1 = Util.newUser(p1);
let dResult1 = Util.delegateUser(dUser1, p2);
eqBool(dResult1, true, "delegateUser returns true first time");
switch (dUser1.delegate) {
  case (?d) { eqNat(Principal.toBlob(d).size(), Principal.toBlob(p2).size(), "delegateUser sets delegate") };
  case null { fail("delegateUser delegate should not be null") };
};
let dResult2 = Util.delegateUser(dUser1, dUser1.id);
eqBool(dResult2, false, "delegateUser returns false when already delegated");
pass("delegateUser");

// ═══════════════════════════════════════════════════════════
// Test: transferAccount
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test transferAccount ---");

let tFrom = Util.newUser(p1);
let tTo = Util.newUser(p2);
ignore Util.setUserCycle(tFrom, 1_000_000);
ignore Util.setUserCycle(tTo, 500_000);
ignore Util.delegateUser(tFrom, p2);

Util.transferAccount(tFrom, tTo);
eqNat(tFrom.balance.cycle, 0, "transferAccount zeroes from_user cycles");
eqNat(tTo.balance.cycle, 1_500_000, "transferAccount adds cycles to to_user");
pass("transferAccount basic");

// ═══════════════════════════════════════════════════════════
// Test: transferAccount with allocations
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test transferAccount with allocations ---");

let taFrom = Util.newUser(p1);
let taTo = Util.newUser(p2);
ignore Util.setUserCycle(taFrom, 2_000_000);
ignore Util.delegateUser(taFrom, p2);

let taCanister : Util.Canister = makeCanister(p2, 0);
let taAlloc : Util.Allocation = {
  canister = taCanister;
  var alias = ?"test-alloc";
  var allocated = 1_000_000;
  var donated = 0;
};
ignore Queue.pushBack(taFrom.allocations, taAlloc);
ignore Queue.pushBack(taCanister.donors, { id = p1; allocation = taAlloc });

Util.transferAccount(taFrom, taTo);
let taTransferred = Util.findAllocation(taTo, p2);
isSome(taTransferred, "transferAccount transfers allocations");
pass("transferAccount with allocations");

// ═══════════════════════════════════════════════════════════
// Test: getCanisterCycle
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test getCanisterCycle ---");

let c1 = makeCanister(p1, 100_000_000);
eqNat(Util.getCanisterCycle(c1), 100_000_000, "getCanisterCycle returns last balance");

Util.addCanisterCycleCheck(c1, 200_000_000);
eqNat(Util.getCanisterCycle(c1), 200_000_000, "getCanisterCycle returns updated last balance");
pass("getCanisterCycle");

// ═══════════════════════════════════════════════════════════
// Test: getCanisterAllocation / getCanisterDonated
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test getCanisterAllocation / getCanisterDonated ---");

let c2 = makeCanister(p1, 0);
eqNat(Util.getCanisterAllocation(c2), 0, "getCanisterAllocation empty");
eqNat(Util.getCanisterDonated(c2), 0, "getCanisterDonated empty");

let uaUser1 = Util.newUser(p1);
ignore Util.setUserCycle(uaUser1, 5_000_000);
let _uaResult1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(uaUser1, c2, ?"alloc1", 2_000_000);

let uaUser2 = Util.newUser(p2);
ignore Util.setUserCycle(uaUser2, 3_000_000);
let _uaResult2 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(uaUser2, c2, ?"alloc2", 1_500_000);

eqNat(Util.getCanisterAllocation(c2), 3_500_000, "getCanisterAllocation sums allocations");
eqNat(Util.getCanisterDonated(c2), 0, "getCanisterDonated is 0 initially");

let deducted = Util.deductCanisterDonation(c2, 1_750_000);
eqNat(deducted, 1_750_000, "deductCanisterDonation returns total deducted");
eqNat(Util.getCanisterDonated(c2), 1_750_000, "getCanisterDonated reflects deductions");
pass("getCanisterAllocation / getCanisterDonated");

// ═══════════════════════════════════════════════════════════
// Test: roundUp
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test roundUp ---");

eqNat(Util.roundUp(0), 0, "roundUp(0)");
eqNat(Util.roundUp(1), 1_000_000_000_000, "roundUp(1)");
eqNat(Util.roundUp(500_000_000_001), 1_000_000_000_000, "roundUp(500B+1)");
eqNat(Util.roundUp(1_000_000_000_000), 1_000_000_000_000, "roundUp(1TC)");
eqNat(Util.roundUp(1_000_000_000_001), 2_000_000_000_000, "roundUp(1TC+1)");
eqNat(Util.roundUp(1_500_000_000_000), 2_000_000_000_000, "roundUp(1.5TC)");
eqNat(Util.roundUp(3_000_000_000_000), 3_000_000_000_000, "roundUp(3TC)");
pass("roundUp");

// ═══════════════════════════════════════════════════════════
// Test: getCanisterAverageCycle
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test getCanisterAverageCycle ---");

let cAvg = makeCanister(p1, 300);
Util.addCanisterCycleCheck(cAvg, 400);
Util.addCanisterCycleCheck(cAvg, 300);
eqNat(Util.getCanisterAverageCycle(cAvg), 333, "getCanisterAverageCycle");
pass("getCanisterAverageCycle");

// ═══════════════════════════════════════════════════════════
// Test: addCanisterCycleCheck respects MAX_HISTORY (30)
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test addCanisterCycleCheck MAX_HISTORY ---");

let cMax = makeCanister(p1, 0);
var i : Nat = 0;
while (i < 35) {
  Util.addCanisterCycleCheck(cMax, i * 100);
  i += 1;
};
eqNat(Queue.size(cMax.cycle_balances), 30, "cycle_balances respects MAX_HISTORY=30");
pass("addCanisterCycleCheck MAX_HISTORY");

// ═══════════════════════════════════════════════════════════
// Test: findCanister / findOrAddCanister
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test findCanister / findOrAddCanister ---");

let canisters : PriorityQueue.PriorityQueue<Util.Canister> = PriorityQueue.empty();
let cAdd = Util.findOrAddCanister(canisters, p1, 10_000_000);
eqNat(Principal.toBlob(cAdd.id).size(), Principal.toBlob(p1).size(), "findOrAddCanister creates canister");
eqNat(PriorityQueue.size(canisters), 1, "findOrAddCanister pushes to queue");

let cFound = Util.findCanister(canisters, p1);
isSome(cFound, "findCanister finds existing canister");

let cNotFound = Util.findCanister(canisters, p2);
isNull(cNotFound, "findCanister returns null for non-existent");

// findOrAddCanister again should not duplicate
let _cAdd2 = Util.findOrAddCanister(canisters, p1, 20_000_000);
eqNat(PriorityQueue.size(canisters), 1, "findOrAddCanister does not duplicate");
pass("findCanister / findOrAddCanister");

// ═══════════════════════════════════════════════════════════
// Test: PriorityQueue pops canister with smallest last_checked
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test PriorityQueue pop ordering ---");

let pqCanisters : PriorityQueue.PriorityQueue<Util.Canister> = PriorityQueue.empty();

// Create canisters with different last_checked values.
// compareCanister uses Int.compare(y.last_checked, x.last_checked) so the
// smallest last_checked should be popped first.
let pqC1 : Util.Canister = { id = p1; first_checked = 0; var last_checked = 1000; var last_donated = 0; cycle_balances = Queue.empty(); usage = Queue.empty(); donors = Queue.empty(); var error = null };
let pqC2 : Util.Canister = { id = p2; first_checked = 0; var last_checked = 500;  var last_donated = 0; cycle_balances = Queue.empty(); usage = Queue.empty(); donors = Queue.empty(); var error = null };
let pqC3 : Util.Canister = { id = p3; first_checked = 0; var last_checked = 1500; var last_donated = 0; cycle_balances = Queue.empty(); usage = Queue.empty(); donors = Queue.empty(); var error = null };

// Push in arbitrary order (not sorted by last_checked)
PriorityQueue.push(pqCanisters, Util.compareCanister, pqC3);
PriorityQueue.push(pqCanisters, Util.compareCanister, pqC1);
PriorityQueue.push(pqCanisters, Util.compareCanister, pqC2);
eqNat(PriorityQueue.size(pqCanisters), 3, "PriorityQueue has 3 canisters");

// Pop 1: should be pqC2 (last_checked = 500, smallest)
let pqPop1 = PriorityQueue.pop(pqCanisters, Util.compareCanister);
isSome(pqPop1, "pop returns some");
eqBool(switch (pqPop1) { case (?c) { c.id == p2 }; case null { false } }, true, "first pop is p2 (smallest last_checked=500)");
eqNat(PriorityQueue.size(pqCanisters), 2, "PriorityQueue has 2 after pop");

// Pop 2: should be pqC1 (last_checked = 1000)
let pqPop2 = PriorityQueue.pop(pqCanisters, Util.compareCanister);
isSome(pqPop2, "pop returns some second time");
eqBool(switch (pqPop2) { case (?c) { c.id == p1 }; case null { false } }, true, "second pop is p1 (last_checked=1000)");
eqNat(PriorityQueue.size(pqCanisters), 1, "PriorityQueue has 1 after pop");

// Pop 3: should be pqC3 (last_checked = 1500, largest)
let pqPop3 = PriorityQueue.pop(pqCanisters, Util.compareCanister);
isSome(pqPop3, "pop returns some third time");
eqBool(switch (pqPop3) { case (?c) { c.id == p3 }; case null { false } }, true, "third pop is p3 (largest last_checked=1500)");
eqNat(PriorityQueue.size(pqCanisters), 0, "PriorityQueue empty after all pops");

// Pop on empty returns null
let pqPop4 = PriorityQueue.pop(pqCanisters, Util.compareCanister);
isNull(pqPop4, "pop on empty returns null");
pass("PriorityQueue pop ordering");

// ═══════════════════════════════════════════════════════════
// Test: setAllocation - new allocation
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test setAllocation new ---");

let sUser = Util.newUser(p1);
ignore Util.setUserCycle(sUser, 10_000_000);
let sCanister = makeCanister(p2, 0);

let sResult = Util.setAllocation(sUser, sCanister, ?"my-canister", 5_000_000);
switch (sResult) {
  case (#ok(alloc)) {
    eqNat(alloc.allocated, 5_000_000, "setAllocation new sets allocated");
    switch (alloc.alias) {
      case (?s) { eqText(s, "my-canister", "setAllocation new sets alias") };
      case null { fail("setAllocation new alias should not be null") };
    };
    eqNat(sUser.balance.cycle, 5_000_000, "setAllocation new deducts from balance");
    eqNat(Queue.size(sCanister.donors), 1, "setAllocation new adds donor");
    eqNat(Queue.size(sUser.allocations), 1, "setAllocation new adds allocation");
  };
  case (#err(_)) { fail("setAllocation new should succeed") };
};
pass("setAllocation new");

// ═══════════════════════════════════════════════════════════
// Test: setAllocation - update existing
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test setAllocation update ---");

let uUser = Util.newUser(p1);
ignore Util.setUserCycle(uUser, 10_000_000);
let uCanister = makeCanister(p2, 0);

let _uResult1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(uUser, uCanister, ?"old-alias", 7_000_000);

let uResult2 = Util.setAllocation(uUser, uCanister, ?"new-alias", 5_000_000);
switch (uResult2) {
  case (#ok(alloc)) {
    eqNat(alloc.allocated, 5_000_000, "setAllocation update changes allocated");
    switch (alloc.alias) {
      case (?s) { eqText(s, "new-alias", "setAllocation update changes alias") };
      case null { fail("setAllocation update alias should not be null") };
    };
    eqNat(uUser.balance.cycle, 5_000_000, "setAllocation update adjusts balance");
    eqNat(Queue.size(uUser.allocations), 1, "setAllocation update no duplicate");
  };
  case (#err(_)) { fail("setAllocation update should succeed") };
};
pass("setAllocation update");

// ═══════════════════════════════════════════════════════════
// Test: setAllocation - insufficient balance
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test setAllocation insufficient ---");

let iUser = Util.newUser(p1);
ignore Util.setUserCycle(iUser, 1_000);
let iCanister = makeCanister(p2, 0);

let iResult = Util.setAllocation(iUser, iCanister, null, 10_000_000);
switch (iResult) {
  case (#err(maxCycle)) {
    eqNat(maxCycle, 1_000, "setAllocation insufficient returns max usable");
  };
  case (#ok(_)) { fail("setAllocation should fail with insufficient balance") };
};
pass("setAllocation insufficient");

// ═══════════════════════════════════════════════════════════
// Test: setAllocation - increase
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test setAllocation increase ---");

let incUser = Util.newUser(p1);
ignore Util.setUserCycle(incUser, 10_000_000);
let incCanister = makeCanister(p2, 0);

let _incR1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(incUser, incCanister, null, 3_000_000);

let incR2 = Util.setAllocation(incUser, incCanister, null, 8_000_000);
switch (incR2) {
  case (#ok(alloc)) {
    eqNat(alloc.allocated, 8_000_000, "setAllocation increase works");
    eqNat(incUser.balance.cycle, 2_000_000, "setAllocation increase deducts correctly");
  };
  case (#err(_)) { fail("setAllocation increase should succeed") };
};
pass("setAllocation increase");

// ═══════════════════════════════════════════════════════════
// Test: setAllocation - decrease (refund)
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test setAllocation decrease ---");

let decUser = Util.newUser(p1);
ignore Util.setUserCycle(decUser, 10_000_000);
let decCanister = makeCanister(p2, 0);

let _decR1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(decUser, decCanister, null, 8_000_000);
eqNat(decUser.balance.cycle, 2_000_000, "balance after initial allocation");

let decR2 = Util.setAllocation(decUser, decCanister, null, 3_000_000);
switch (decR2) {
  case (#ok(alloc)) {
    eqNat(alloc.allocated, 3_000_000, "setAllocation decrease works");
    eqNat(decUser.balance.cycle, 7_000_000, "setAllocation decrease refunds");
  };
  case (#err(_)) { fail("setAllocation decrease should succeed") };
};
pass("setAllocation decrease");

// ═══════════════════════════════════════════════════════════
// Test: removeDonor
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test removeDonor ---");

let rUser1 = Util.newUser(p1);
let rUser2 = Util.newUser(p2);
ignore Util.setUserCycle(rUser1, 5_000_000);
ignore Util.setUserCycle(rUser2, 3_000_000);
let rCanister = makeCanister(p1, 0);

let _rAlloc1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(rUser1, rCanister, null, 2_000_000);
let _rAlloc2 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(rUser2, rCanister, null, 1_000_000);
eqNat(Queue.size(rCanister.donors), 2, "two donors added");

let removed = Util.removeDonor(rCanister, p1);
isSome(removed, "removeDonor finds and removes donor");
eqNat(Queue.size(rCanister.donors), 1, "removeDonor reduces donor count");

// donors should only have p2 now
let remaining = Queue.toArray(rCanister.donors);
eqNat(Principal.toBlob(remaining[0].id).size(), Principal.toBlob(p2).size(), "only second donor remains");

let removedNone = Util.removeDonor(rCanister, p3);
isNull(removedNone, "removeDonor returns null for non-existent");
pass("removeDonor");

// ═══════════════════════════════════════════════════════════
// Test: deductCanisterDonation - proportional
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test deductCanisterDonation proportional ---");

let dedUser1 = Util.newUser(p1);
let dedUser2 = Util.newUser(p2);
ignore Util.setUserCycle(dedUser1, 10_000_000);
ignore Util.setUserCycle(dedUser2, 10_000_000);
let dedCanister = makeCanister(p1, 0);

let _dedR1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(dedUser1, dedCanister, null, 6_000_000);
let _dedR2 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(dedUser2, dedCanister, null, 4_000_000);

let dedTotal = Util.deductCanisterDonation(dedCanister, 5_000_000);
eqNat(dedTotal, 5_000_000, "deductCanisterDonation deducts full gap");
eqNat(Util.getCanisterDonated(dedCanister), 5_000_000, "total donated equals gap");

let a1After = Util.findAllocation(dedUser1, p1);
let a2After = Util.findAllocation(dedUser2, p1);
switch (a1After) {
  case (?a) {
    eqNat(a.allocated, 3_000_000, "User1 remaining allocation");
    eqNat(a.donated, 3_000_000, "User1 donated amount");
  };
  case null { fail("User1 allocation not found") };
};
switch (a2After) {
  case (?a) {
    eqNat(a.allocated, 2_000_000, "User2 remaining allocation");
    eqNat(a.donated, 2_000_000, "User2 donated amount");
  };
  case null { fail("User2 allocation not found") };
};
pass("deductCanisterDonation proportional");

// ═══════════════════════════════════════════════════════════
// Test: deductCanisterDonation - zero gap
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test deductCanisterDonation zero ---");

let zeroCanister = makeCanister(p1, 0);
eqNat(Util.deductCanisterDonation(zeroCanister, 0), 0, "deductCanisterDonation 0 gap");
pass("deductCanisterDonation zero gap");

// ═══════════════════════════════════════════════════════════
// Test: deductCanisterDonation - gap larger than total
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test deductCanisterDonation cap ---");

let capUser = Util.newUser(p1);
ignore Util.setUserCycle(capUser, 5_000_000);
let capCanister = makeCanister(p1, 0);
let _capR : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(capUser, capCanister, null, 5_000_000);

eqNat(Util.deductCanisterDonation(capCanister, 10_000_000), 5_000_000, "deductCanisterDonation caps at total");
pass("deductCanisterDonation cap");

// ═══════════════════════════════════════════════════════════
// Test: findAllocation
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test findAllocation ---");

let fUser = Util.newUser(p1);
ignore Util.setUserCycle(fUser, 10_000_000);
let fCanister = makeCanister(p1, 0);

let _fR : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(fUser, fCanister, null, 1_000_000);

let foundA = Util.findAllocation(fUser, p1);
isSome(foundA, "findAllocation finds existing");
let notFoundA = Util.findAllocation(fUser, p2);
isNull(notFoundA, "findAllocation returns null for non-existent");
pass("findAllocation");

// ═══════════════════════════════════════════════════════════
// Test: addDonation respects MAX_HISTORY (30)
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test addDonation MAX_HISTORY ---");

let dMaxCan = makeCanister(p1, 0);
var j : Nat = 0;
while (j < 35) {
  Util.addDonation(dMaxCan, j * 10);
  j += 1;
};
eqNat(Queue.size(dMaxCan.usage), 30, "addDonation respects MAX_HISTORY=30");
pass("addDonation MAX_HISTORY");

// ═══════════════════════════════════════════════════════════
// Test: toHex
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test toHex ---");

let hexBlob = Blob.fromArray([0 : Nat8, 255, 170, 16]);
eqText(Util.toHex(hexBlob), "00ffaa10", "toHex converts blob to hex");

let emptyBlob = Blob.fromArray(Array.empty<Nat8>());
eqText(Util.toHex(emptyBlob), "", "toHex of empty blob is empty");

let singleByte = Blob.fromArray([10 : Nat8]);
eqText(Util.toHex(singleByte), "0a", "toHex single byte");
pass("toHex");

// ═══════════════════════════════════════════════════════════
// Test: principalToSubAccount
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test principalToSubAccount ---");

let subAccount = Util.principalToSubAccount(p1);
eqNat(Blob.size(subAccount), 32, "principalToSubAccount returns 32-byte blob");
let subBytes = Blob.toArray(subAccount);
eqBool(subBytes[0] >= 1, true, "first byte of subaccount is non-zero");
pass("principalToSubAccount");

// ═══════════════════════════════════════════════════════════
// Test: allocationInfo
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test allocationInfo ---");

let aiUser = Util.newUser(p1);
ignore Util.setUserCycle(aiUser, 10_000_000);
let aiCanister = makeCanister(p2, 100_000);
Util.addCanisterCycleCheck(aiCanister, 200_000);
let aiResult = Util.setAllocation(aiUser, aiCanister, ?"test", 5_000_000);
switch (aiResult) {
  case (#ok(alloc)) {
    let aiInfo = Util.allocationInfo(alloc);
    eqNat(aiInfo.allocated, 5_000_000, "allocationInfo preserves allocated");
    eqNat(aiInfo.donated, 0, "allocationInfo preserves donated");
    eqText(aiInfo.alias, "test", "allocationInfo extracts alias");
    eqNat(Principal.toBlob(aiInfo.canister.id).size(), Principal.toBlob(p2).size(), "allocationInfo.canister.id");
  };
  case (#err(_)) { fail("setAllocation should succeed") };
};
pass("allocationInfo");

// ═══════════════════════════════════════════════════════════
// Test: allocationInfo with null alias
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test allocationInfo null alias ---");

let aiNullUser = Util.newUser(p1);
ignore Util.setUserCycle(aiNullUser, 10_000_000);
let aiNullCanister = makeCanister(p2, 100_000);
let aiNullResult = Util.setAllocation(aiNullUser, aiNullCanister, null, 5_000_000);
switch (aiNullResult) {
  case (#ok(alloc)) {
    let aiNullInfo = Util.allocationInfo(alloc);
    eqText(aiNullInfo.alias, "", "allocationInfo null alias returns empty string");
  };
  case (#err(_)) { fail("setAllocation should succeed") };
};
pass("allocationInfo null alias");

// ═══════════════════════════════════════════════════════════
// Test: canisterInfo
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test canisterInfo ---");

let ciCanister = makeCanister(p1, 1_000_000);
Util.addCanisterCycleCheck(ciCanister, 2_000_000);
Util.addCanisterCycleCheck(ciCanister, 1_500_000);
ciCanister.error := ?"test error";
let ciInfo = Util.canisterInfo(ciCanister);
eqNat(Principal.toBlob(ciInfo.id).size(), Principal.toBlob(p1).size(), "canisterInfo.id");
switch (ciInfo.error) {
  case (?e) { eqText(e, "test error", "canisterInfo.error") };
  case null { fail("canisterInfo error should be set") };
};
eqNat(ciInfo.last_checked_balance, 1_500_000, "canisterInfo.last_checked_balance");
eqNat(ciInfo.average_balance, 1_500_000, "canisterInfo.average_balance");
eqNat(ciInfo.usage.size(), 0, "canisterInfo.usage is empty initially");
pass("canisterInfo");

// ═══════════════════════════════════════════════════════════
// Test: userInfo
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test userInfo ---");

let uiUser = Util.newUser(p1);
ignore Util.setUserCycle(uiUser, 10_000_000);
ignore Util.setUserICP(uiUser, { e8s = 500_000_000 : Nat64 });
let uiCanister = makeCanister(p2, 0);
let _uiR : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(uiUser, uiCanister, ?"my-c", 5_000_000);

let uiInfo = Util.userInfo(uiUser);
eqNat(Principal.toBlob(uiInfo.id).size(), Principal.toBlob(p1).size(), "userInfo.id");
eqNat(uiInfo.balance.cycle, 5_000_000, "userInfo.balance.cycle");
eqNat64(uiInfo.balance.icp.e8s, 500_000_000, "userInfo.balance.icp.e8s");
eqNat(uiInfo.allocations.size(), 1, "userInfo.allocations count");
pass("userInfo");

// ═══════════════════════════════════════════════════════════
// Test: export
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test export ---");

let eUsers : Queue.Queue<Util.User> = Queue.empty();
let eUser1 = Util.findOrCreateNewUser(eUsers, p1);
ignore Util.setUserCycle(eUser1, 10_000);

let eCanisters : PriorityQueue.PriorityQueue<Util.Canister> = PriorityQueue.empty();
let _eC1 = Util.findOrAddCanister(eCanisters, p2, 5_000);

let exported = switch (Util.exportData(eUsers, eCanisters)) {
  case (#ok(d)) d;
  case (#err(e)) { fail("export should not error: " # e) }
};
eqNat(exported.users.size(), 1, "export users count");
eqNat(exported.canisters.size(), 1, "export canisters count");
eqNat(Principal.toBlob(exported.users[0].id).size(), Principal.toBlob(p1).size(), "export user id");
eqNat(Principal.toBlob(exported.canisters[0].id).size(), Principal.toBlob(p2).size(), "export canister id");
pass("export");

// ═══════════════════════════════════════════════════════════
// Test: transferAccount merge allocations
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test transferAccount merge ---");

let mFrom = Util.newUser(p1);
let mTo = Util.newUser(p2);
ignore Util.setUserCycle(mFrom, 20_000_000);
ignore Util.setUserCycle(mTo, 10_000_000);
ignore Util.delegateUser(mFrom, p2);

let mCan1 = makeCanister(p1, 0);
let mCan2 = makeCanister(p3, 0);

let _mR1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(mFrom, mCan1, null, 5_000_000);
let _mR2 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(mTo, mCan1, null, 3_000_000);
let _mR3 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(mFrom, mCan2, null, 2_000_000);

Util.transferAccount(mFrom, mTo);

let mToAlloc1 = Util.findAllocation(mTo, p1);
switch (mToAlloc1) {
  case (?a) {
    eqNat(a.allocated, 8_000_000, "transferAccount merges allocations");
  };
  case null { fail("merged allocation not found") };
};

let mToAlloc2 = Util.findAllocation(mTo, p3);
switch (mToAlloc2) {
  case (?a) {
    eqNat(a.allocated, 2_000_000, "transferAccount transfers new allocation");
  };
  case null { fail("transferred allocation not found") };
};
eqNat(mFrom.balance.cycle, 0, "transferAccount zeroes from_user balance");
pass("transferAccount merge allocations");

// ═══════════════════════════════════════════════════════════
// Test: import empty
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test import empty ---");

let emptyImported = switch (Util.importData([], [])) {
  case (#ok(d)) d;
  case (#err(e)) { fail("import empty should not error: " # e) }
};
eqNat(Queue.size(emptyImported.users), 0, "import empty users");
eqNat(PriorityQueue.size(emptyImported.canisters), 0, "import empty canisters");
pass("import empty");

// ═══════════════════════════════════════════════════════════
// Test: import round-trip
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test import round-trip ---");

let iUsers : Queue.Queue<Util.User> = Queue.empty();
let iUser1 = Util.findOrCreateNewUser(iUsers, p1);
ignore Util.setUserCycle(iUser1, 10_000_000);
ignore Util.setUserICP(iUser1, { e8s = 500_000_000 : Nat64 });
ignore Util.delegateUser(iUser1, p2);
Util.setUserStatus(iUser1, ?#DepositSuccess);

let iCanisters : PriorityQueue.PriorityQueue<Util.Canister> = PriorityQueue.empty();
let iCan1 = Util.findOrAddCanister(iCanisters, p2, 5_000_000);
Util.addCanisterCycleCheck(iCan1, 6_000_000);
iCan1.error := ?"test error";

let _iAlloc : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(iUser1, iCan1, ?"my-canister", 3_000_000);

let iExported = switch (Util.exportData(iUsers, iCanisters)) {
  case (#ok(d)) d;
  case (#err(e)) { fail("export round-trip should not error: " # e) }
};
let iImported = switch (Util.importData(iExported.users, iExported.canisters)) {
  case (#ok(d)) d;
  case (#err(e)) { fail("import round-trip should not error: " # e) }
};

eqNat(Queue.size(iImported.users), 1, "import users count");
eqNat(PriorityQueue.size(iImported.canisters), 1, "import canisters count");

let iFoundUser = Util.findUser(iImported.users, p1);
isSome(iFoundUser, "import finds user");
switch (iFoundUser) {
  case (?u) {
    eqBool(u.id == p1, true, "import user id");
    eqNat(u.balance.cycle, 7_000_000, "import user balance");
    eqNat64(u.balance.icp.e8s, 500_000_000, "import user icp");
    eqNat(Queue.size(u.allocations), 1, "import user allocations");
    switch (u.delegate) {
      case (?d) { eqBool(d == p2, true, "import user delegate") };
      case null { fail("import user delegate should be set") };
    };
    switch (u.status) {
      case (?#DepositSuccess) {};
      case _ { fail("import user status should be DepositSuccess") };
    };
  };
  case null { fail("import user should exist") };
};

let iFoundCanister = Util.findCanister(iImported.canisters, p2);
isSome(iFoundCanister, "import finds canister");
switch (iFoundCanister) {
  case (?c) {
    eqBool(c.id == p2, true, "import canister id");
    eqNat(Util.getCanisterCycle(c), 6_000_000, "import canister cycle");
    eqNat(Util.getCanisterAllocation(c), 3_000_000, "import canister allocation");
    eqNat(Util.getCanisterDonated(c), 0, "import canister donated");
    eqNat(Queue.size(c.donors), 1, "import canister donors");
    eqNat(Queue.size(c.cycle_balances), 1, "import canister cycle_balances");
    eqNat(Queue.size(c.usage), 0, "import canister usage");
    switch (c.error) {
      case (?e) { eqText(e, "test error", "import canister error") };
      case null { fail("import canister error should be set") };
    };
  };
  case null { fail("import canister should exist") };
};

pass("import round-trip");

// ═══════════════════════════════════════════════════════════
// Test: import reconstructs donors
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test import donors ---");

let idUsers : Queue.Queue<Util.User> = Queue.empty();
let idUser1 = Util.findOrCreateNewUser(idUsers, p1);
let idUser2 = Util.findOrCreateNewUser(idUsers, p2);
ignore Util.setUserCycle(idUser1, 10_000_000);
ignore Util.setUserCycle(idUser2, 10_000_000);

let idCanisters : PriorityQueue.PriorityQueue<Util.Canister> = PriorityQueue.empty();
let idCan1 = Util.findOrAddCanister(idCanisters, p3, 0);

let _idAlloc1 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(idUser1, idCan1, ?"alloc1", 4_000_000);
let _idAlloc2 : Result.Result<Util.Allocation, Util.Cycle> = Util.setAllocation(idUser2, idCan1, ?"alloc2", 6_000_000);

let idExported = switch (Util.exportData(idUsers, idCanisters)) {
  case (#ok(d)) d;
  case (#err(e)) { fail("export donors should not error: " # e) }
};
let idImported = switch (Util.importData(idExported.users, idExported.canisters)) {
  case (#ok(d)) d;
  case (#err(e)) { fail("import donors should not error: " # e) }
};

let idImportedCanister = Util.findCanister(idImported.canisters, p3);
isSome(idImportedCanister, "import donors canister exists");
switch (idImportedCanister) {
  case (?c) {
    eqNat(Queue.size(c.donors), 2, "import donors count");
    eqNat(Util.getCanisterAllocation(c), 10_000_000, "import donors total allocation");
    eqNat(Util.getCanisterDonated(c), 0, "import donors total donated");

    let idImportedUser1 = Util.findUser(idImported.users, p1);
    switch (idImportedUser1) {
      case (?u) {
        let a1 = Util.findAllocation(u, p3);
        isSome(a1, "import user1 allocation exists");
        switch (a1) {
          case (?a) {
            eqNat(a.allocated, 4_000_000, "import user1 allocation amount");
            switch (a.alias) {
              case (?s) { eqText(s, "alloc1", "import user1 allocation alias") };
              case null { fail("import user1 alias should be set") };
            };
          };
          case null { fail("import user1 allocation should exist") };
        };
      };
      case null { fail("import user1 should exist") };
    };
  };
  case null { fail("import donors canister should exist") };
};

pass("import donors");

// ═══════════════════════════════════════════════════════════
// Test: import usage history
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test import usage ---");

let uCanisters : PriorityQueue.PriorityQueue<Util.Canister> = PriorityQueue.empty();
let uCan1 = Util.findOrAddCanister(uCanisters, p1, 1_000);
Util.addDonation(uCan1, 100);
Util.addDonation(uCan1, 200);

let uUsers : Queue.Queue<Util.User> = Queue.empty();
let uExported = switch (Util.exportData(uUsers, uCanisters)) {
  case (#ok(d)) d;
  case (#err(e)) { fail("export usage should not error: " # e) }
};
let uImported = switch (Util.importData(uExported.users, uExported.canisters)) {
  case (#ok(d)) d;
  case (#err(e)) { fail("import usage should not error: " # e) }
};

let uImportedCanister = Util.findCanister(uImported.canisters, p1);
isSome(uImportedCanister, "import usage canister exists");
switch (uImportedCanister) {
  case (?c) {
    eqNat(Queue.size(c.usage), 2, "import usage history size");
    let usages = Queue.toArray(c.usage);
    eqNat(usages[0].cycle, 100, "import usage first entry");
    eqNat(usages[1].cycle, 200, "import usage second entry");
  };
  case null { fail("import usage canister should exist") };
};

pass("import usage");

// ═══════════════════════════════════════════════════════════
// Test: import error when canister is missing from top-level array
// ═══════════════════════════════════════════════════════════
Debug.print("--- Test import missing canister ---");

let fbUser : Util.UserInfo = {
  id = p1;
  delegate = null;
  balance = { icp = { e8s = 0 : Nat64 }; cycle = 0 };
  allocations = [
    {
      canister = {
        id = p2;
        first_checked = 0;
        last_checked = 0;
        last_checked_balance = 1_000_000;
        average_balance = 1_000_000;
        total_allocation = 5_000_000;
        total_donated = 0;
        usage = [];
        error = null;
      };
      alias = "missing-canister";
      allocated = 5_000_000;
      donated = 0;
    }
  ];
  last_updated = 0;
  status = null;
};

switch (Util.importData([fbUser], [])) {
  case (#ok(_)) { fail("import should error when canister is missing from top-level array") };
  case (#err(e)) {
    eqBool(Text.contains(e, #text "Canister not found in import"), true, "import missing canister error message");
  };
};

pass("import missing canister");

// ═══════════════════════════════════════════════════════════
// Summary
// ═══════════════════════════════════════════════════════════
Debug.print("=== All Util.mo tests passed ===");
