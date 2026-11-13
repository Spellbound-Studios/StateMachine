# Spellbound.StateMachine

Gives any game asset-defined states: a machine over a context, states as ScriptableObjects swapped in the inspector, a registry that finds them.

## Install

Add this line to `Packages/manifest.json`, replacing `<version>` with a release tag:

```
"com.spellboundstudios.statemachine": "https://github.com/Spellbound-Studios/StateMachine.git?path=/Packages/StateMachine#v<version>"
```

The Spellbound window in Core installs it for you.

## Front door

`StateMachineKit` is the entry point to everything this package offers.

```csharp
var machine = StateMachineKit.Create(this, configuration);
machine.ChangeState(Phase.Running);
machine.UpdateStateMachine();
```

A configuration is a list of bindings, each a slot of your enum and the `State` asset that fills it, and the slot the machine starts in: `StateMachineConfiguration<TStateKey>` is the package's own, filled in the inspector or in code, and any `IStateMachineConfiguration<TStateKey>` works. A state is a ScriptableObject that derives from `State`. Fill `StateMachineKit.Registry` with `StateMachineKit.UseStates(catalogue)` to resolve a state from its hash; the `StateCatalogue` inspector collects every `State` asset of the project.

## Rules

The binding rules are the line text at https://github.com/Spellbound-Studios/.github/tree/main/line
