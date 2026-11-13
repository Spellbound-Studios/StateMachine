// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections.Generic;

namespace Spellbound.StateMachine.Tests {
    public sealed class TickingConfiguration : IStateMachineConfiguration<TickingSlot> {
        public TickingConfiguration(TickingSlot initialState, params IStateBinding<TickingSlot>[] bindings) {
            InitialState = initialState;
            Bindings = bindings;
        }

        public IReadOnlyList<IStateBinding<TickingSlot>> Bindings { get; }
        public TickingSlot InitialState { get; }
    }
}
