# Spellbound.StateMachine

StateMachine gives any game asset-defined states. A machine runs over a context, which is any class the states act on, and an enum whose values are the machine's slots. Each slot is filled by a state, and a state is a ScriptableObject asset, so a designer swaps the state that fills a slot in the inspector without touching code.

## Making a machine

Write an enum of slots and hand the machine a configuration: its bindings, each a slot and the state that fills it, and the slot it starts in. The package's own configuration does it in one line:

```csharp
var machine = StateMachineKit.Create(this, new StateMachineConfiguration<Phase>(Phase.Idle, new StateBinding<Phase>(Phase.Idle, idle), new StateBinding<Phase>(Phase.Running, running)));
```

`StateMachineConfiguration<TStateKey>` and `StateBinding<TStateKey>` are plain serialisable classes, so a MonoBehaviour can hold the configuration as a field and a designer fills it in the inspector:

```csharp
[SerializeField] private StateMachineConfiguration<Phase> configuration = new();

private void Awake() => _machine = StateMachineKit.Create(this, configuration);
```

A game that wants its own shape, for example a ScriptableObject shared by several owners, implements `IStateMachineConfiguration<TStateKey>` (its `Bindings` and its `InitialState`) and `IStateBinding<TStateKey>` (a `Slot` and a `Variant`) instead.

The machine makes its own copy of each state asset it is given, one per asset, hands each copy the context, and enters the initial slot. The shared asset is never changed, so every owner runs its own copies, and two assets of one class with different tuning are two states. `GetState<TVariant>()` looks only at the copies the slots hold now: when they hold one copy of exactly that type it returns it; otherwise the running state if its exact type is `TVariant`; otherwise null, so an abstract base never comes back.

## Running a machine

- `ChangeState(slot)` leaves the active slot and enters another one.
- `ApplyVariant(slot, state)` and `ApplyVariant<TVariant>(slot)` swap the state that fills a slot; the change takes effect at once when the slot is active. `RestoreDefault(slot)` puts back the state the configuration named.
- `UpdateStateMachine()` and `FixedUpdateStateMachine()` drive the active state; call them from the owner's `Update` and `FixedUpdate`.
- `Configure(configuration)` on a running machine exits the active state, empties every slot, resets `CurrentStateKey` and forgets the defaults, then binds the new configuration; a slot it leaves out holds no state. A configuration whose initial slot no binding fills is refused with an error and changes nothing.
- `Dispose()` exits the active state, empties every slot, resets `CurrentStateKey` and destroys the machine's copies; call it from the owner's `OnDestroy`. A disposed machine throws `ObjectDisposedException` from every member that changes or drives it.

`IStateMachine` answers `CurrentState`, `CurrentStateHash` and `IsInState` for code that knows neither the context nor the enum.

A request for a slot the enum does not hold or a slot that holds no state, a null configuration or a null variant (in `SetInitialVariant` too) is refused: the machine logs an error through Core's `Log` and stays as it was. A binding with no variant is skipped, with a warning under Core's warning define: Core compiles `Log.Warn` only under SPELLBOUND_LOG_WARNING.

## Writing a state

Derive from `State` and implement `EnterStateLogic`, `UpdateStateLogic`, `FixedUpdateStateLogic` and `ExitStateLogic`. Override `OnContextInitialized` to cast `Context` to your own type once, and `OnStateInitialize` for any other setup. `StateDriver` drives the state filling one slot; derive from it and pass it to `RegisterStateDriver` to change how a slot runs. On a slot that already holds a state, the new driver takes the state over, and on the active slot the old driver exits and the new one enters.

## Finding a state by its hash

A state's hash comes from its asset's GUID, so it stays the same wherever the asset sits. `StateMachineKit.Registry` resolves a hash to a state once the game fills it:

```csharp
StateMachineKit.UseStates(catalogue);
var state = StateMachineKit.Registry.Get(hash);
```

`Get` logs an error through Core's `Log` for a hash it does not hold and returns null; `TryGet` answers false without a word. `UseStates` given no catalogue or no list logs an error and keeps the states the registry held.

A `StateCatalogue` asset lists the states. Its inspector button "Collect the project's states" fills it from every `State` asset in the project; that button is the only thing that writes a catalogue. Before each player build the package's build check warns under Core's warning define (SPELLBOUND_LOG_WARNING) of every `State` asset that no catalogue lists, naming its path, and writes nothing, so a curated catalogue stays as its author left it. A game may hand in any other list of states instead, or make its own `StateRegistry` from one. `StateRegistry.WriteState` and `ReadState` pack a state as its four-byte hash for a save or a message. The registry never reads from `Resources`.

The shared registry is cleared at `RuntimeInitializeLoadType.SubsystemRegistration`, and Unity does not order methods that share a load type, so fill it at `RuntimeInitializeLoadType.BeforeSceneLoad` or later: an `Awake` or a `Start` is always safe. The operation `statemachine states [--offset <integer>] [--limit <integer>]` lists its states by hash and name.
