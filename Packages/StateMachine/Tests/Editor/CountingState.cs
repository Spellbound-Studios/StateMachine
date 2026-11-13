// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine.Editor.Tests {
    public abstract class CountingState : State {
        public int EnterCount { get; private set; }
        public int ExitCount { get; private set; }
        public int UpdateCount { get; private set; }
        public int FixedUpdateCount { get; private set; }
        public int InitializeCount { get; private set; }

        protected override void OnStateInitialize() => InitializeCount++;

        protected override void EnterStateLogic() => EnterCount++;

        protected override void UpdateStateLogic() => UpdateCount++;

        protected override void FixedUpdateStateLogic() => FixedUpdateCount++;

        protected override void ExitStateLogic() => ExitCount++;
    }
}
