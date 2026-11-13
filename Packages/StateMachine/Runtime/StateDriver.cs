// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine {
    public class StateDriver {
        protected State CurrentStateVariant;
        protected bool IsActiveDriver;

        public State CurrentVariant => CurrentStateVariant;
        public bool IsActive => IsActiveDriver;

        public virtual void ChangeVariant(State newVariant) {
            if (CurrentStateVariant != null && IsActiveDriver)
                CurrentStateVariant.OnExit();

            CurrentStateVariant = newVariant;

            if (CurrentStateVariant != null && IsActiveDriver)
                CurrentStateVariant.OnEnter();
        }

        public virtual void OnBecomeActive() {
            IsActiveDriver = true;

            if (CurrentStateVariant != null)
                CurrentStateVariant.OnEnter();
        }

        public virtual void OnBecomeInactive() {
            if (CurrentStateVariant != null)
                CurrentStateVariant.OnExit();

            IsActiveDriver = false;
        }

        public virtual void DriveUpdate() {
            if (IsActiveDriver && CurrentStateVariant != null)
                CurrentStateVariant.OnUpdate();
        }

        public virtual void DriveFixedUpdate() {
            if (IsActiveDriver && CurrentStateVariant != null)
                CurrentStateVariant.OnFixedUpdate();
        }
    }
}
