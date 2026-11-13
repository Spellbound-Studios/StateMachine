// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class SingleStateMachine : IStateMachine {
        public SingleStateMachine(State state) => CurrentState = state;

        public State CurrentState { get; }

        public uint CurrentStateHash => CurrentState != null ? CurrentState.Hash : 0u;

        public bool IsInState<TVariant>() where TVariant : State => CurrentState is TVariant;

        public bool IsInState(uint stateHash) => CurrentStateHash != 0u && CurrentStateHash == stateHash;
    }
}
