#!/usr/bin/env python3
"""Parse `forge test --json` output from stdin and write one file per test
under gas/<ContractName>/<testName>.txt containing the gas used."""

import json
import sys
import pathlib

GAS_DIR = pathlib.Path("gas")

data = json.load(sys.stdin)
for suite, info in data.items():
    contract = suite.split(":")[1]
    for test_name, result in info["test_results"].items():
        name = test_name.rstrip("()")
        gas = result["kind"]["Unit"]["gas"]
        path = GAS_DIR / contract / f"{name}.txt"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"{gas}\n")
