// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using UnityEngine;

namespace Spellbound.StateMachine.Editor.Tests {
    [Serializable]
    public sealed class CountingBinding : IStateBinding<CountingSlot> {
        [SerializeField] private CountingSlot slot;
        [SerializeField] private State variant;

        public CountingBinding(CountingSlot slot, State variant) {
            this.slot = slot;
            this.variant = variant;
        }

        public CountingSlot Slot => slot;
        public State Variant => variant;
    }
}
