// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine.Tests {
    public sealed class TickingBinding : IStateBinding<TickingSlot> {
        public TickingBinding(TickingSlot slot, State variant) {
            Slot = slot;
            Variant = variant;
        }

        public TickingSlot Slot { get; }
        public State Variant { get; }
    }
}
