# Notes on the design and implementation of Tip Jar

A random collection of notes reflecting on the design and development of the Tip Jar canister.

## Do canisters dream of electric tables?

One of the early goals of this project is to eventually make the Tip Jar canister immutable.
So I decided not to focus too much on upgrades.
This led to some design decisions that may appear unusual to trained eyes, so it is worth a discussion.

Instead of maintaining lookup tables for users and canisters, I use direct object references.

```
User ---*--> Allocation ---1--> Canister

Canister ---*--> Donor ---1--> User

---*-->    one to many relation
---1-->    one to one relation
```

If I were to design data schema for a database, I'd normalize the above relations into several tables.
But this time I chose instead to maintain a graph of objects referencing each other directly.

An immediate benefit is that I don't have to deal with table lookup failures in my code, because there is no indirection, no reference by id, and so on.
I felt relieved to have eliminated a whole class of error handling and assertions from the code base.

The downside, however, is that if I were to change an object type in a non-compatible way, upgrading the canister will fail.
Recent versions of the [motoko] compiler can do a safety check to detect sub-type violations when upgrading stable variables, but still, it will require manual effort to implement a `postupgrade` procedure to carefully migrate data from old schemas to new ones.
I had to do this a couple times, but it wasn't as bad as I had thought.

This experiment offers a glimpse of the future: when we have orthogonal persistence, do old practices such as data "normalization" still make sense?

## Linear lookups

As another experiment, I also decided against using a hash table to store users and canisters.
A common wisdom is that O(1) lookup is important.
But since I already use direct object references, there are very few occasions that still require looking up things by their ids.
Doing a linear search is not bad, especially when the number of elements is on the scale of thousands instead of millions.

Besides, I could build a cache using a table or map structure when lookup speed becomes important.
Since Tip Jar will not support deletion, keeping the cache up-to-date will be trivial.

As an aside, I'd recommend using `TrieMap` instead of `HashMap` because the latter has an unpredictable insertion cost: it may exceed the per-call cycle limit when a table has to be rehashed!

## Atomicity and job queue

One tricky part of implementing the Tip Jar canister is converting ICP to cycles.
But the problem is that there is no direct method of knowing how much cycle is received by the target canister as the result of such as conversion.
The workaround I use here is to calculate the difference in cycle balance before and after the conversion.
This requires locking down the canister and preventing other cycle related activities (e.g. sending cycles to top-up other canisters) when such a conversion is still in process.

The handling of ICP to cycles conversion is a delicate process.
It goes through 4 stages:

- `Mint` and `MintCalled`: Before and after sending ICP to CMC (Cycle Minting Canister) to start the minting.
- `Notify` and `NotifyCalled`: Before and after calling notify on ledger to in order to receive the minted cycles.

Note that `MintCalled` and `NotifyCalled` are necessary to help remember a message has already been sent to avoid any potential re-entrance problems.

I chose to implement the ICP to cycle conversion process with one job queue, and canister topping up with another job queue.
In retrospect these two probably should be merged into a single job queue, then I don't need to worry about the inter-locking between the two queues.

A final note is that when there is an outstanding conversion in process, we should not stop the canister or upgrade it.
The Internet Computer platform will prevent a canister from being upgraded when there are pending callbacks (waiting to receive replies from messages sent to other canisters).
But it is a good practice to implement a `stop` function to prevent such callbacks from being created in the first place before we stop the canister for an upgrade.

Since I don't plan to upgrade this canister often, I didn't bother to use stable variables for job queues.
Calling the `stop` function first will give me enough time to wait until all queues are cleared before attempting an upgrade.

[motoko]: https://github.com/dfinity/motoko
