// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections.Generic;

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class CodeConfiguration : IStateMachineConfiguration<CountingSlot> {
        private readonly List<IStateBinding<CountingSlot>> _bindings = new();

        public CodeConfiguration(CountingSlot initialState) => InitialState = initialState;

        public IReadOnlyList<IStateBinding<CountingSlot>> Bindings => _bindings;

        public CountingSlot InitialState { get; }

        public CodeConfiguration Bind(CountingSlot slot, State variant) {
            _bindings.Add(new CountingBinding(slot, variant));

            return this;
        }
    }
}
