
## Transaction Scripts

Creating a transaction using the `cardano-cli` is more complex than it ought to be. We discovered this while registering our stake pool (`PDT1`) and thought that at least some of it could be improved; this is our attempt using wrapper scripts.

As you are likely aware if you've gotten here, drafting, signing and submitting are done separately so that signing can occur on an air-gapped machine. While drafting is really the only step that is complex, we've created scripts for each step to be consistent, both in usage and logging:

* `draftTx.sh`
* `signTx.sh`
* `submitTx.sh`

Each requires use of the `--name` option to provide a name that is used to name the transaction and log files. 
