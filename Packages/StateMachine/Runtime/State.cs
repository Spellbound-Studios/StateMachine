// Copyright (c) Spellbound Studios. All rights reserved.

using Spellbound.Core.Registries;

namespace Spellbound.StateMachine {
    public abstract class State : HashedScriptableObject {
        public object Context { get; private set; }

        public virtual void InitializeWithContext(object context) {
            Context = context;
            OnContextInitialized();
            OnStateInitialize();
        }

        protected virtual void OnContextInitialized() { }

        protected virtual void OnStateInitialize() { }

        public void OnEnter() => EnterStateLogic();

        public void OnUpdate() => UpdateStateLogic();

        public void OnFixedUpdate() => FixedUpdateStateLogic();

        public void OnExit() => ExitStateLogic();

        protected abstract void EnterStateLogic();

        protected abstract void UpdateStateLogic();

        protected abstract void FixedUpdateStateLogic();

        protected abstract void ExitStateLogic();
    }
}
