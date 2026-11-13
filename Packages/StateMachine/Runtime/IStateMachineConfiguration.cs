// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections.Generic;

namespace Spellbound.StateMachine {
    public interface IStateMachineConfiguration<TStateKey> {
        IReadOnlyList<IStateBinding<TStateKey>> Bindings { get; }
        TStateKey InitialState { get; }
    }
}
