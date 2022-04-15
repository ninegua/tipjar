# Canister Tip Jar

https://tipjar.rocks (which redirects to https://k25co-pqaaa-aaaab-aaakq-cai.ic0.app)

Donate [cycles] to your favorite [canisters] on the [Internet Computer] and keep them live and healthy!


**Features and Roadmap**

- [x] Deposit ICPs that are automatically converted into cycles.
- [x] Name and choose your favorite canisters to contribute to.
- [x] Monitor canister cycle level and top up whenever it goes lower than the daily average.
- [x] Deduct cycle funds to make donations based on the contribution percentage of each user.
- [x] Support Internet Identity login.
- [x] Support "add to home screen" on mobile browsers.
- [x] Support import of PEM file for those who do not have or use Internet Identity.
- [ ] Blacklist canisters that attempt to rug pull.
- [ ] [Canister list pagination and search box](https://github.com/ninegua/tipjar/issues/3).
- [ ] [Allow canister controllers to authorize their own donation page](https://github.com/ninegua/tipjar/issues/2).
- [ ] [Support canister bundles and identification](https://github.com/ninegua/tipjar/issues/2).
- [ ] Support one time donation in addition to daily automatic ones.

**Got questions? We have answers!**

Please check out the list of [Frequently Asked Questions](FAQ.md).

I also wrote down [some random notes](NOTES.md) on the design decisions in making this app.

**Releases**

- Version 0.0.0 (retired)

  A technical demo that shows ICPs can be automatically converted into Cycles.

- Version 0.0.1 (live)

  There could still be bugs to iron out over time, please [report issues on GitHub](https://github.com/ninegua/tipjar/issues).
  Source code is already released.

- Version 0.1.0
 
  Ready when existing features are sufficiently tested.

- Version 0.2.0

  Complete features for both donors and canister developers.

- Version 0.3.0

  Feature freeze. Only bug fixes will be implemented.

- Version 0.4.0

  The day when TipJar becomes immutable by having the [black hole] as its only controller!

**Local deployment**

If you want to run tipjar locally in your [dfx] environment, you will need [GNU make], [curl], and a working [vessel] installation too.

```
dfx start --background
make deploy
```

This will start a dfx replica, download necessary files, and deploy all canisters locally.


[cycles]: https://smartcontracts.org/docs/developers-guide/concepts/tokens-cycles.html
[black hole]: https://github.com/ninegua/ic-blackhole
[canisters]: https://sdk.dfinity.org/docs/developers-guide/concepts/canisters-code.html
[Internet Computer]: https://dashboard.internetcomputer.org
[GNU make]: https://www.gnu.org/software/make
[curl]: https://curl.se
[dfx]: https://smartcontracts.org/docs/quickstart/1-quickstart.html
[vessel]: https://github.com/dfinity/vessel
