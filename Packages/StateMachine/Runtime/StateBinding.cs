// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using UnityEngine;

namespace Spellbound.StateMachine {
    [Serializable]
    public sealed class StateBinding<TStateKey> : IStateBinding<TStateKey> where TStateKey : Enum {
        [SerializeField] private TStateKey slot;
        [SerializeField] private State variant;

        public StateBinding() { }

        public StateBinding(TStateKey slot, State variant) {
            this.slot = slot;
            this.variant = variant;
        }

        public TStateKey Slot => slot;
        public State Variant => variant;
    }
}
