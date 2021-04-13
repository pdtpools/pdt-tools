
## Transaction Scripts

Creating a transaction using the `cardano-cli` is more complex than it ought to be. We discovered this while registering our stake pool (`PDT1`) and thought that at least some of it could, and should, be improved; this is our attempt using wrapper scripts.

As you likely are aware if you've gotten this far, drafting, signing and submitting are done separately so that signing can occur on an air-gapped machine. While drafting is really the only step that is complex, we've created scripts for each step to be consistent, both in usage and logging:

* `draftTx.sh`
* `signTx.sh`
* `submitTx.sh`
