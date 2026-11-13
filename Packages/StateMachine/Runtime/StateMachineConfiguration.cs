// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using UnityEngine;

namespace Spellbound.StateMachine {
    [Serializable]
    public sealed class StateMachineConfiguration<TStateKey> : IStateMachineConfiguration<TStateKey>
        where TStateKey : Enum {
        [SerializeField] private TStateKey initialState;
        [SerializeField] private List<StateBinding<TStateKey>> bindings = new();

        public StateMachineConfiguration() { }

        public StateMachineConfiguration(TStateKey initialState, params StateBinding<TStateKey>[] bindings) {
            this.initialState = initialState;

            if (bindings != null)
                this.bindings.AddRange(bindings);
        }

        public IReadOnlyList<IStateBinding<TStateKey>> Bindings => bindings;
        public TStateKey InitialState => initialState;
    }
}
