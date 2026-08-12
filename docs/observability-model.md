# R.E.A.L. observability and control model

Logs, screenshots, and a debug console are not three interchangeable layers. Logs and screenshots are evidence modalities; a console is a control surface. R.E.A.L. separates six runtime planes so each artifact has an explicit role.

| Plane | Question answered | Typical products |
|---|---|---|
| Timeline | What happened, and in what order? | structured events, warnings, errors, performance samples |
| Semantic state | What did the game mean at this point? | schema-backed snapshots, entity registry, numeric deltas, anomalies |
| Visual evidence | What did the player actually see? | clean screenshots, annotated screenshots, video, target-to-pixel geometry |
| Control | Can an agent perform a named experiment safely? | semantic console, allowlisted runtime actions, scenario setup, editor selection |
| Reproduction | Can the same situation be reconstructed? | build/content revision, seed, action trace, checkpoints, replay |
| Verdict | Did the behavior satisfy the contract? | assertions, health gates, pass/fail/inconclusive, evidence references |

The causal loop is:

```text
control/action -> timeline -> semantic snapshot + visual artifact -> verdict
       ^                                                        |
       +---------------- reproduction/replay -------------------+
```

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
4. screenshots correlated to snapshots and commands;
5. allowlisted semantic actions with explicit command IDs;
6. a replay recipe or checkpoint sufficient to reproduce a defect;
7. machine-readable assertions and an explicit verdict.

The Web runtime implements this as browser/Node ES modules. The Godot runtime implements the same contract through autoloads, JSONL, screenshots, and the loopback action executor.
