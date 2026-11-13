// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEngine;

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class TunedCountingState : CountingState {
        [SerializeField] private int tuning;

        public int Tuning {
            get => tuning;
            set => tuning = value;
        }
    }
}
