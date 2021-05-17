import Cycles "mo:base/ExperimentalCycles";

actor {
    public query func remaining_cycles() : async Nat {
        return Cycles.balance()
    };
};
