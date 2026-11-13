// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections.Generic;

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class RecordingState : State {
        private readonly List<string> _calls = new();

        public IReadOnlyList<string> Calls => _calls;

        public RecordingContext TypedContext { get; private set; }

        protected override void OnContextInitialized() {
            TypedContext = Context as RecordingContext;
            _calls.Add("context");
        }

        protected override void OnStateInitialize() => _calls.Add("initialize");

        protected override void EnterStateLogic() => _calls.Add("enter");

        protected override void UpdateStateLogic() => _calls.Add("update");

        protected override void FixedUpdateStateLogic() => _calls.Add("fixed update");

        protected override void ExitStateLogic() => _calls.Add("exit");
    }
}
