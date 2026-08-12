# R.E.A.L. observability and control model

Logs, screenshots, and a debug console are not three interchangeable layers. Logs and screenshots are evidence modalities; a console is a control surface. R.E.A.L. defines eight runtime capabilities so each interface and artifact has an explicit role. The first five provide observation; the final three close the experiment loop.

| Capability | Type | Question answered | Typical products |
|---|---|---|---|
| Identity | observation | Which exact runtime produced this evidence? | build/content revision, run/session, tick, seed, scene, config profile |
| Timeline | observation | What happened, and in what order? | structured events/logs, warnings, errors, performance samples |
| Semantic state | observation | What did the game mean at this point? | schema-backed snapshots, entity/target registry, deltas, anomalies |
| Numeric explainability | observation | Why did this number become that number? | units, value provenance, formula/intermediate traces, invariant violations |
| Visual evidence | observation | What did the player actually see? | clean screenshots, annotated screenshots, video, target-to-pixel geometry |
| Semantic commands | control | Can an agent perform a named experiment safely? | semantic console, allowlisted actions, temporary overrides, editor selection |
| Reproduction | replay | Can the same situation be reconstructed? | action trace, checkpoints, build identity, seed, deterministic replay |
| Verdict | judgment | Did the behavior satisfy the contract? | assertions, health gates, pass/fail/inconclusive, evidence references |

The causal loop is:

```text
semantic command -> timeline -> state + numeric trace + visual artifact -> verdict
        ^                                                               |
        +-------------------- reproduction/replay -----------------------+
```

Identity fields correlate every step. Numeric explainability belongs beside semantic state rather than being hidden in prose logs: the game and its headless simulator must use the same authoritative formulas.

## Storage and learning tiers

Runtime planes should not be confused with how long evidence is retained:

| Tier | Lifetime | Owner |
|---|---|---|
| L0 | current process | developer console and engine logger |
| L1 | one run/session | R.E.A.L. evidence bundle |
| L2 | automation campaign | harness/evaluator run memory, comparisons, recovery cursor |
| L3 | cross-project | durable lessons and context in Theseus or another knowledge system |

R.E.A.L. owns L1. It emits enough identity and correlation fields for L2 and L3, but does not own orchestration or long-term memory.

## Minimum viable instrumented game

A new game should expose all of the following before it is considered agent-debuggable:

1. stable build, session, tick, and seed identity;
2. structured transition events rather than prose-only logging;
3. semantic snapshots through a thin game adapter;
4. an explainable numeric core with units, provenance, formula traces, and executable invariants;
5. screenshots correlated to snapshots and commands;
6. allowlisted semantic actions with explicit command IDs;
7. a replay recipe or checkpoint sufficient to reproduce a defect;
8. machine-readable assertions and an explicit verdict.

The Web runtime implements this as browser/Node ES modules. The Godot runtime implements the same contract through autoloads, JSONL, screenshots, and the loopback action executor.
