# Spellbound.StateMachine

## Purpose

Gives any game asset-defined states: a machine over a context, states as ScriptableObjects swapped in the inspector, a registry that finds them.

## Front door

`StateMachineKit.Create(context, configuration)` makes a `StateMachine<TContext, TStateKey>` over a context (any class) and an enum of slots, wires it from an `IStateMachineConfiguration<TStateKey>` (its `Bindings` and `InitialState`) and enters the initial slot. Each slot has a `StateDriver`; each binding (`IStateBinding<TStateKey>`, a `Slot` and a `Variant`) fills a slot with a `State` asset. `StateMachineConfiguration<TStateKey>` and `StateBinding<TStateKey>` are the defaults: plain serialisable classes that a MonoBehaviour holds as a field and fills in the inspector, or that code builds in one line. The machine runs its own copy of every state asset it is given, one per asset, keyed by the asset's hash (a state made in code, with hash 0, is copied once per object), so a shared asset is never changed and two assets of one class with different tuning are two states. `GetState<TVariant>()` looks only at the copies the slots hold now: when they hold one copy of exactly that type it returns it; otherwise the running state if its exact type is the one asked for; otherwise null, so an abstract base never comes back. `ChangeState` activates another slot, `ApplyVariant` and `RestoreDefault` swap the state filling a slot, `UpdateStateMachine` and `FixedUpdateStateMachine` drive the active state. A second `Configure` exits the active state, empties every slot, resets `CurrentStateKey` and forgets the defaults before it binds, so a slot the new configuration leaves out holds no state; a configuration whose initial slot no binding fills is refused with an error and changes nothing. `RegisterStateDriver` on a slot that holds a state moves the state to the new driver; on the active slot it exits the old driver and enters the new one. `Dispose` exits the active state, empties every slot, resets `CurrentStateKey` and destroys the copies; after it every member that changes or drives the machine throws an ObjectDisposedException. `IStateMachine` answers `CurrentState`, `CurrentStateHash` and `IsInState` without the context or the enum.

`State` is an abstract ScriptableObject over Core's `HashedScriptableObject`: its hash comes from the asset's GUID, wherever the asset sits. `StateMachineKit.Registry` is a `StateRegistry` over Core's `HashRegistry<State>`, filled with `StateMachineKit.UseStates` from a `StateCatalogue` asset or any list of states the game hands in; `StateRegistry.WriteState` and `ReadState` pack a state as its four-byte hash through Core's `RegistryPacker`. A game can also make its own `StateRegistry` from a list. `Get` logs an error through Core's `Log` for an unknown hash and returns null; `TryGet` is silent; `Use` given no catalogue or no list logs an error and keeps the states it held. The catalogue's inspector button "Collect the project's states" fills it from every `State` asset in the project (`StateCatalogueCollector.Collect`), the only place the package writes a catalogue. Before each player build the package's build check warns under Core's warning define (SPELLBOUND_LOG_WARNING) of every `State` asset no catalogue lists, naming its path, and never writes. `statemachine states` lists the shared registry's states by hash and name.

<!-- spellbound:operations 7fab6592 -->
com.spellboundstudios.statemachine
Operations of the group `statemachine`, run as `<group> <operation> [arguments]`:
- `statemachine states [--offset <integer> = 0] [--limit <integer> = 50]`: Lists the states of the shared registry by name and hash, in registry order. [reads, anyone]
  - `--offset`: How many states to skip from the start. Default: 0.
  - `--limit`: How many states to list. Default: 50.
<!-- /spellbound:operations -->

<!-- spellbound:samples 16b4e41a -->
Samples in `Samples~`, imported from the Package Manager's Samples tab:
- StateMachine Sample: Shows the package's front door in use. (`Samples~/StateMachineSample`)
<!-- /spellbound:samples -->

<!-- spellbound:depends 64c552e8 -->
Depends on:
- `com.spellboundstudios.core` in [1.1.9,3.0.0)
<!-- /spellbound:depends -->

<!-- spellbound:pipeline 433e4b11 -->
Agents run these operation lines from the Unity command line when `com.unity.pipeline` is installed in [0.0.0,1.0.0): find the command with `unity command --query spellbound` and pass it one line. The ranges Core's Pipeline bridge accepts are in Core's AGENTS.md.
<!-- /spellbound:pipeline -->

## Rules

The binding rules are the line text at https://github.com/Spellbound-Studios/.github/tree/main/line

- The machine and the registry log through Core's `Log`; a request for a slot the enum does not hold or a slot that holds no state, a null configuration or a null variant (in `SetInitialVariant` too) is refused with an error and changes nothing, and a binding with no variant is skipped, with a warning under Core's warning define. Core compiles `Log.Info` and `Log.Warn` only under SPELLBOUND_LOG_INFO and SPELLBOUND_LOG_WARNING; errors always log.
- No `Resources` read: states reach the registry only through a catalogue or a list the game hands in.
- `StateMachineKit.Registry` is the one static state of the runtime assembly and is cleared on SubsystemRegistration. Unity does not order methods that share a load type, so the game fills it at `RuntimeInitializeLoadType.BeforeSceneLoad` or later (an Awake or Start method is later), never at SubsystemRegistration.
- Nothing of a character, a body, a rig, locomotion or input enters this package.

## Not for

- Moving a character, reading input or driving animation: those belong to Character and to the game.
- Concrete states: a game or a sample writes them over `State`.
- Saving or sending a state: the registry packs a state's hash, and Persistence or a transport carries the bytes.

## Gaps

None.

## Ledger

The waivers and answers of this package are in the dev project's `Assets/_Project/Ledger/StateMachine.asset`.
