// Copyright (c) Spellbound Studios. All rights reserved.

using System;

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class DeferredBinding : IStateBinding<CountingSlot> {
        private readonly Func<State> _resolve;

        public DeferredBinding(CountingSlot slot, Func<State> resolve) {
            Slot = slot;
            _resolve = resolve;
        }

        public int ResolveCount { get; private set; }

        public CountingSlot Slot { get; }

        public State Variant {
            get {
                ResolveCount++;

                return _resolve();
            }
        }
    }
}
