# fapolicyd tests

This repository contains set of test for fapolicyd.
Tests are written using [beakerlib](https://github.com/beakerlib/beakerlib) with [TMT Metadata Specification](https://tmt.readthedocs.io/en/latest/spec.html).


## Gating Guidelines
Test tiers define a test's priority for our **gating process**.

**FIXME**
* **`tier: 1`**: Critical tests that must pass for any code merge. 
* **`tier: 2`**: Important but non-critical tests.
* **`tier: 3`**: Non-critical tests.

All other tier metadata (e.g., `tag:Tier1`) is now deprecated.

## Plans

    $ tmt plans
    Found 4 plans: /Plans/ci, /Plans/destructive-plan, /Plans/ima-integrity and /update/plan.

## Usage

Run `ci` on `localhost`:

    # tmt run provision -h local prepare plans -n /Plans/ci discover execute
    # tmt run -l report -h display -v

