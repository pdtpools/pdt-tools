
## Transaction Scripts

Creating a transaction with the `cardano-cli` is more complex than it ought to be. We discovered this while following the excellent [CoinCashew](https://www.coincashew.com/coins/overview-ada/guide-how-to-build-a-haskell-stakepool-node) steps to register our stake pool ([PDT1](https://pdtpools.io/)) and thought that at least some of it could be improved; this is our attempt using wrapper scripts. 

As you are likely aware if you've gotten here, drafting, signing and submitting are done separately so that signing can occur on an air-gapped machine. While drafting is really the only step that is complex, we've created scripts for each step to be consistent, both in usage and logging:

* `draftTx.sh`
* `signTx.sh`
* `submitTx.sh`

Each requires use of a `--name` option that is used to name the transaction and log file (the latter will include the actual `cardano-cli` commands issued). For exmple, say you're creating a key deposit transaction and you specify `--name key-deposit` in all three steps. The first step would result in `key-deposit.draft` and `key-deposit.log` files. The second would expect the `key-deposit.draft` file and produce a `key-deposit.signed` file as well as append to the `key-deposit.log` file. Finally, the third would expect the `key-deposit.signed` file and append to the `key-deposit.log` file.

The draft and sign steps have no permanent effect and can even be repeated; however, the submit step is clearly different. To enable experimenting with the entire flow, the `submitTx.sh` script supports a `--dry-run` option which will cause it to skip the actual submit command but log it anyway.
  
TODO
