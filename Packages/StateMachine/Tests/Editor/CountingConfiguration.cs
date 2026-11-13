// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections.Generic;
using UnityEngine;

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class CountingConfiguration : ScriptableObject, IStateMachineConfiguration<CountingSlot> {
        [SerializeField] private List<CountingBinding> bindings = new();
        [SerializeField] private CountingSlot initialState;

        public IReadOnlyList<IStateBinding<CountingSlot>> Bindings => bindings;
        public CountingSlot InitialState => initialState;

        public static CountingConfiguration Create(CountingSlot initialState, params CountingBinding[] bindings) {
            var configuration = CreateInstance<CountingConfiguration>();
            configuration.initialState = initialState;
            configuration.bindings.AddRange(bindings);

            return configuration;
        }
    }
}
