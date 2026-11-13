// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine {
    public interface IStateMachine {
        State CurrentState { get; }
        uint CurrentStateHash { get; }
        bool IsInState<TVariant>() where TVariant : State;
        bool IsInState(uint stateHash);
    }
}
