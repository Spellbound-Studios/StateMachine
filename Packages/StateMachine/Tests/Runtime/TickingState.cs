// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine.Tests {
    public sealed class TickingState : State {
        public int EnterCount { get; private set; }
        public int UpdateCount { get; private set; }
        public int FixedUpdateCount { get; private set; }

        protected override void EnterStateLogic() => EnterCount++;

        protected override void UpdateStateLogic() => UpdateCount++;

        protected override void FixedUpdateStateLogic() => FixedUpdateCount++;

        protected override void ExitStateLogic() { }
    }
}
