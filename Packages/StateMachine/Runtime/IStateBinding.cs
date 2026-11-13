// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine {
    public interface IStateBinding<out TStateKey> {
        TStateKey Slot { get; }
        State Variant { get; }
    }
}
