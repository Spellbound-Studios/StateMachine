// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEngine;

namespace Spellbound.StateMachine.Tests {
    public sealed class MachineRunner : MonoBehaviour {
        public StateMachine<object, TickingSlot> Machine { get; set; }
        public int UpdateCalls { get; private set; }
        public int FixedUpdateCalls { get; private set; }

        private void Update() {
            if (Machine == null)
                return;

            UpdateCalls++;
            Machine.UpdateStateMachine();
        }

        private void FixedUpdate() {
            if (Machine == null)
                return;

            FixedUpdateCalls++;
            Machine.FixedUpdateStateMachine();
        }
    }
}
