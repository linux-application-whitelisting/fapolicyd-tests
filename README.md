# fapolicyd tests

This repository contains a set of tests and plans for the fapolicyd component. Tests are written with the use of [beakerlib](https://github.com/beakerlib/beakerlib) and [TMT Metadata Specification](https://tmt.readthedocs.io/en/latest/spec.html).

## Gating guidelines

Tests are divided into tiers. The tiers then indicate a priority for our **gating process**.

* **`tier: 1`**: Critical tests that must pass for any code merge.
* **`tier: 2`**: Important but non-critical tests.
* **`tier: 3`**: Non-critical tests.

## Plans

How to list existing test plans:
```
$ tmt plans
Found 6 plans: /Plans/ci, /Plans/destructive-plan, /Plans/e2e_ci, /Plans/ima-integrity, /Plans/rpmverify and /update/plan.
```

## Usage

How to run CI tests on localhost:
```
# tmt run provision -h local prepare plans -n /Plans/ci discover execute
# tmt run -l report -h display -v
```

## Test plan execution on the Testing Farm

The procedure below is not a complete copy&paste solution, it's rather a guideline how test plans are currently executed.

Still, it may be handy to export some `testing-farm` related parameters via an environment variable.

Don't forget to replace TF_COMPOSE with a valid compose (e.g. Fedora-42) and DISTRO with the corresponding distribution (e.g. fedora-42).

```
export TF_REQUEST_PARAMS="--git-url https://github.com/linux-application-whitelisting/fapolicyd-tests.git  --git-ref main --compose TF_COMPOSE --context distro=DISTRO"
```

List of available Testing Farm composes can be found [here](https://api.testing-farm.io/v0.1/composes/).

### E2E test plan on all architectures

```
testing-farm request $TF_REQUEST_PARAMS --hardware memory='>= 2 GiB' --hardware disk.size='>= 10 GB' --plan '/Plans/e2e_ci' --arch aarch64,ppc64le,s390x,x86_64
```

### Destructive test plan on the x86_64 architecture

```
testing-farm request $TF_REQUEST_PARAMS --plan '/Plans/destructive-plan'
```

### Single test instead of a whole test plan

```
testing-farm request --context "distro=centos-stream-10 arch=x86_64" --git-url https://src.fedoraproject.org/tests/selinux.git --compose CentOS-Stream-10 --git-ref main --arch x86_64 --plan /plans/failing --test /selinux-policy/fapolicyd-and-similar
```

The upstream SELinux tests repository also contains a fapolicyd test [here](https://src.fedoraproject.org/tests/selinux/blob/main/f/selinux-policy/fapolicyd-and-similar).

