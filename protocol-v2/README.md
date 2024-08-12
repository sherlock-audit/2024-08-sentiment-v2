## Setup

### Clone and Build

```shell
git clone https://github.com/sentimentxyz/protocol-v2.git
forge b
```

### Test

```shell
forge t --force # recompile and run all tests
forge t --nmt "Fork" # skip fork tests
forge t --nmt "invariant" # skip invariant tests
forge t --nmt "Fork|invariant" # skip both
```

Forked tests require a `FORK_TEST_CONFIG` param to be set in `.env` and valid params in the corresponding JSON config file.

Sample `fork-test-config.json`:
```json
{
    "minLtv": 0,
    "liquidationFee": 0,
    "owner": "0x000000000000000000000000000000000000dEaD",
    "pool": "0x000000000000000000000000000000000000dEaD",
    "positionManager": "0x000000000000000000000000000000000000dEaD",
    "riskEngine": "0x000000000000000000000000000000000000dEaD",
    "usdc": "0x000000000000000000000000000000000000dEaD",
    "sender": "0x000000000000000000000000000000000000dEaD"
}
```

### Remappings

Project remappings are defined in `foundry.toml`. If your LSP is unable to detect these, try copying them to
`remappings.txt` and recompiling.

### Scripts

Scripts requires the `SCRIPT_CONFIG` to be set in `.env` and a valid config file. For broadcasted transactions, the
private key specified via `PRIVATE_KEY` in `.env` is used.

`SCRIPT_CONFIG` points to a JSON file with multiple objects. Each object represents the name of the script which uses
the paramaters specified by the object.

Sample `script-config.json` with paramaters for `InitializePool.s.sol`:
```json
{
    "InitializePool": {
            "pool": "0x0000000000000000000000000000000000000000",
            "owner": "0x0000000000000000000000000000000000000000",
            "asset": "0x0000000000000000000000000000000000000000",
            "rateModel": "0x0000000000000000000000000000000000000000",
            "interestFee": 0,
            "originationFee": 0,
            "poolCap": 0 
    }
}
```

### .env
Summarizing the above, the `.env` needs the following:
```bash
SCRIPT_CONFIG='<script-config>.json'
FORK_TEST_CONFIG='<fork-test-config>.json'
PRIVATE_KEY=<private-key-for-broadcast-txns>
```