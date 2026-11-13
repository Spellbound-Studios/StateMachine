# StateMachine Sample

The scene `TrafficLight` holds one traffic light that cycles from red to green to amber and back, in the built-in pipeline or URP.
Each phase is a `State` asset with its own duration and colour; the light's `TrafficLight` component names them in its configuration.
`TrafficLight` makes its machine with `StateMachineKit.Create` and fills its own `StateRegistry` from `StateCatalogue.asset` in `Awake`, leaving the shared registry alone.
It picks the built-in or the URP pair of materials for the lamp and the ground at `Awake` and tints the lamp through a property block; drag `LongGreenPhase.asset` onto the Green binding to swap in a longer green.
The sample uses only the package's public surface.
