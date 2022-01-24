# Frequently Asked Questions

## Why should I care?

*There is no free lunch. Neither are your favorite canisters.*

If they run out of cycles, you may find things (that you have grown accustomed to) are broken in unexpected ways.
Or even worse, by then as an end user you may have no means to get them back running even if you want to pay their bills!

So to help the developers of valuable canister services and to help your future self, start make plans now before it is too late!

## How does it work?

This service monitors the cycle balance of your recipient canisters on a daily basis, and will top up their cycles to their daily average of the last 10 days.
So as long as there are enough allocations for a canister, it should run in perpetuity, at least in theory.

As a donor you are free at any time to adjust the distribution and allocation of your funds.
Canisters will only receive from donors who have allocated funds to them. The amount deducted from a donor's balance is proportional to their allocation.

## Why am I getting an error when trying to add a canister?

Before a canister can receive cycles donation, it must set the [black hole canister]
`e3mmv-5qaaa-aaaah-aadma-cai` as one of its controllers.
This will enable third parties like the Tip Jar to monitor its canister status including remaining cycle balance.
Besides revealing such information to the public, doing so has no other side effects or security concerns because the black hole itself is immutable and cannot do any harm.

If there is a canister useful to you, please ask its developer to do this sooner than later.
The [dfx] command line is given below:

``` .shell
dfx canister --network=ic update-settings \
  --controller [its-current-controller-id] \
  --controller e3mmv-5qaaa-aaaah-aadma-cai \
  [CANISTER_ID]
```

## What is a temporary account?

A temporary account stores your account information (i.e. a randomly generated key pair) only in a browser's local storage.
Although it is convenient and requires no setup, you can't use the same account across different devices.
So if you happen to clear the browser's cache or reinstall your computer, you will not be able to get your account back.

Therefore it is strongly advised to log in with [Internet Identity] to prevent losing access.
Your cycle balance and canister lists in the temporary account will be merged into your authenticated account once you log in.

Alternatively you may also authenticate by importing a PEM file of an ed25519 private key.
This way you are on your own to back up and keep it secure.
You can use [dfx] to create such a PEM file on your computer.
For example, `dfx identity new [name]` will create a PEM file in `~/.config/dfx/identity/[name]/identity.pem`.

## How frequently is a canister topped up, with how many cycles?

Tip Jar monitors all canisters on a fixed interval, e.g. every 12 hours (or sooner, depending on the latest setting).
As soon as it notices the current balance of a canister is below the average of the last 10 days, it will send some cycles to bring it on par with the average.
The consequence of doing this means the average of last 10 days will always stay the same.

In the meantime, a canister can still be topped up by anyone, including its original developer.
So its cycle balance may increase beyond the 10 day average.
The long term effect is that the newer and higher balance will eventually bring up the average.
Having sufficient supply means a canister has more room to deal with irregular traffic patterns.

## What happens if a canister's controller drains its cycle level?

This will usually be considered as a [Rug Pull], which unfortunately cannot be prevented as long as the canister has a controller other than the [black hole canister].
Tip Jar does not vouch for a canister's authenticity or its long term viability, so please Do Your Own Research before deciding to back a project or its canisters.
Because cycles are not donated all at once, donors are free to modify their allocations at any time if they wish.

On a technical level, a sudden decrease of cycle level can still be caught, because there is a max amount of cycles that can be burned by a canister in a fixed amount of time.
So Tip Jar will attempt to blacklist them for 10 days if such activities are noticed.

## Tip Jar only supports deposit of cycles, will it support withdrawal of cycles in the future?

There is no plan to support withdrawal of funds once a deposit has been made.
So please plan ahead and donate responsibly.

## How trustworthy is Tip Jar itself? What happens if you run away with all donations?

Like with any crypto project, there is always a risk.
The short term plan is to make Tip Jar itself immutable once its code base becomes mature enough, likely within 6 months time.
You don't have to use this service before that happens, or only put in a small amount that you feel comfortable with.

## Are you a DAO? Wen airdrop?

My name is Paul Liu, and at the moment I'm Tip Jar's only developer.
I will accept code contributions and coordinate [its development on GitHub](https://github.com/ninegua/tipjar).

Apart from making Tip Jar immutable at some point down the road, I do not have plans to make it a DAO.
No, there will never be a token sale. If you see one, it must be a scam.

[black hole canister]: https://github.com/ninegua/ic-blackhole
[Rug Pull]: https://www.coingecko.com/en/glossary/rug-pulled
[dfx]: https://github.com/dfinity/sdk/
[Internet Identity]: https://identity.ic0.app
