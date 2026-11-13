# Changelog

## [Unreleased]

- `StateMachineConfiguration<TStateKey>` and `StateBinding<TStateKey>`, the default configuration and binding: plain serialisable classes a MonoBehaviour holds as a field and fills in the inspector, or that code builds in one line for `StateMachineKit.Create`.
- The machine copies each state asset once, keyed by the asset's hash, so two assets of one class with different tuning are two states and `CurrentStateHash` names the asset that runs. `GetState<TVariant>()` looks only at the copies the slots hold now: when they hold one copy of exactly that type it returns it; otherwise the running state if its exact type is `TVariant`; otherwise null, so an abstract base never comes back.
- `ChangeState` refuses a slot that holds no state with an error. A second `Configure` exits the active state, empties every slot, resets `CurrentStateKey` and forgets the defaults before it binds; a configuration whose initial slot no binding fills is refused with an error and changes nothing. `RegisterStateDriver` on a slot that holds a state moves the state to the new driver, and on the active slot exits the old driver and enters the new one; a null driver is refused with an error.
- `Dispose` empties every slot and resets `CurrentStateKey`; a second call does nothing, and every member that changes or drives a disposed machine throws `ObjectDisposedException`.
- `StateRegistry.Use` given no catalogue or no list logs an error and keeps its states. Before each player build the internal `StateCatalogueBuildCheck` warns under Core's warning define (SPELLBOUND_LOG_WARNING) of every `State` asset no `StateCatalogue` lists, naming its path; it writes nothing.
- `StateCatalogueInspector`, `StateCatalogueBuildCheck` and `StateCatalogueCollector.FindProjectStates` are internal; Unity finds the inspector and the build check itself. `SetInitialVariant` with a null variant logs an error.
- The sample `StateMachineSample` is a traffic light: three phase states, a catalogue read into the light's own registry, a longer green variant, a built-in and a URP pair of materials, and one scene.

Names that change for a game moving from Controller's state machine:

| Controller | StateMachine |
|---|---|
| namespace `Spellbound.Controller` | namespace `Spellbound.StateMachine` |
| `BaseSoState` | `State` |
| `BaseSoState.Ctx`, a public field | `State.Context`, a read-only property |
| `BaseSoState.OnCtxInitialized()` | `State.OnContextInitialized()` |
| `BaseStateDriver` | `StateDriver` |
| `BaseStateDriver.ActiveDriver` | `StateDriver.IsActive` |
| `IStateMachineConfig<TStateEnum>` | `IStateMachineConfiguration<TStateKey>` |
| `StateMachine<TContext, TStateEnum>.ctx` | `StateMachine<TContext, TStateKey>.Context` |
| `StateMachine<TContext, TStateEnum>.CurrentStateType` | `StateMachine<TContext, TStateKey>.CurrentStateKey` |
| `new StateMachine<TContext, TStateEnum>(ctx)` then `Configure(config)` | `StateMachineKit.Create(context, configuration)`; the constructor and `Configure` remain |
| the static `StateRegistry.Get`, `TryGet`, `Contains`, `Count`, `All` and `ReadState` | the same members on `StateMachineKit.Registry`; `StateRegistry.WriteState` stays static |
| states loaded from `Resources/States` | `StateMachineKit.UseStates(catalogue)` with a `StateCatalogue` asset or a list of states |

The type parameter `TStateEnum` is `TStateKey`, and parameters named `ctx`, `config` and `stateType` are `context`, `configuration` and `stateKey`.

## [0.0.0] - 2026-11-12

- `StateMachine<TContext, TStateKey>` over a context and an enum of slots, made by `StateMachineKit.Create(context, configuration)` from an `IStateMachineConfiguration<TStateKey>` of `IStateBinding<TStateKey>` bindings; it enters the initial slot, changes slot on request and refuses a slot the enum does not hold with an error through Core's `Log`.
- `State`, the abstract ScriptableObject over Core's `HashedScriptableObject`, and `StateDriver`, which drives the state filling one slot.
- `StateRegistry` over Core's `HashRegistry<State>` and `RegistryPacker`, filled from a `StateCatalogue` asset or a list the game hands in, with no `Resources` read; `StateMachineKit.Registry` is the shared one.
- The `StateCatalogue` inspector collects every `State` asset of the project.
- The operation `statemachine states --offset --limit` lists the shared registry's states by hash and name.
