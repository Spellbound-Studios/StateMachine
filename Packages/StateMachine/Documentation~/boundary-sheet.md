# Boundary sheet

## Concern

Gives any game asset-defined states: a machine over a context, states as ScriptableObjects swapped in the inspector, a registry that finds them.

## Package

`com.spellboundstudios.statemachine`, assembly `Spellbound.StateMachine`, with `Spellbound.StateMachine.Editor` for the catalogue tools.

## Motivating use

A character's movement modes and a game's round phases both run as states that designers tune and swap as assets. The machine lived inside the character package, so a game that wanted phases without a character had to copy it.

## Library side

### Primitives

- `State`, the abstract ScriptableObject over Core's `HashedScriptableObject`.
- The state's hash, taken from its asset's GUID, which names a state in a save or a message.

### Operations

- `StateMachine<TContext, TStateKey>`: enters, changes, swaps, drives and disposes the states filling an enum of slots, on its own copies.
- `StateRegistry`: resolves a hash to a state and packs a state as its hash through Core's `HashRegistry<State>` and `RegistryPacker`.
- `statemachine states`: lists the shared registry.

### Policies

- `StateDriver`: how one slot runs its state.
- `IStateBinding<TStateKey>`: which state fills a slot.
- `IStateMachineConfiguration<TStateKey>`: the bindings and the slot a machine starts in.
- `StateCatalogue`: which states the registry holds.

### Front door

`StateMachineKit.Create(context, configuration)` makes a configured machine in one line. `StateMachineKit.UseStates` fills the shared registry, `StateMachineKit.Registry` reads it.

### Sample

`Samples~/StateMachineSample`: a traffic light whose red, green and amber phases are state assets, with a longer green to swap in the inspector.

## Extension points

Each with its default.

- `StateDriver`: the class itself; derive and pass to `RegisterStateDriver`.
- `IStateBinding<TStateKey>`: `StateBinding<TStateKey>`.
- `IStateMachineConfiguration<TStateKey>`: `StateMachineConfiguration<TStateKey>`.
- The registry's states: a `StateCatalogue` filled by `StateCatalogueCollector` through its inspector button, with the build check warning, under Core's warning define, before each build of a state no catalogue lists; any list of states instead.
- `State`: no default; every concrete state belongs to the game or the sample.

## Tunable values

None in the package. Durations, colours and every other value a state needs are fields on the game's own state assets.

## Presentation the consumer can replace

The catalogue inspector adds one button below the default inspector. The package draws nothing at runtime.

## Game side

- Every concrete state, the context it acts on and the enum of slots.
- When the machine is driven: the owner calls `UpdateStateMachine` and `FixedUpdateStateMachine`.
- When the registry is filled: at `BeforeSceneLoad` or later.

## Not for

- Concrete states: a game or the sample writes them over `State`.
- Input, movement, bodies, rigs or animation.
- Any game noun: the package names slots, states, variants and drivers only.
- Saving or sending: the registry packs a hash, and Persistence or a transport carries the bytes.

## Stranger test

A farming sim's crop stages, a racing game's race phases and a card game's turn steps are each an enum of slots filled by state assets. None of them edits the package.

## Existing systems reused

Core's `HashedScriptableObject`, `HashRegistry`, `RegistryPacker`, `Log` and operations.

## Gaps outside scope

None.
