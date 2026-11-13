// Copyright (c) Spellbound Studios. All rights reserved.

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class CountingDriver : StateDriver {
        public int ActivationCount { get; private set; }
        public int UpdateCount { get; private set; }
        public int FixedUpdateCount { get; private set; }
        public int VariantChangeCount { get; private set; }

        public override void ChangeVariant(State newVariant) {
            VariantChangeCount++;
            base.ChangeVariant(newVariant);
        }

        public override void OnBecomeActive() {
            ActivationCount++;
            base.OnBecomeActive();
        }

        public override void DriveUpdate() {
            UpdateCount++;
            base.DriveUpdate();
        }

        public override void DriveFixedUpdate() {
            FixedUpdateCount++;
            base.DriveFixedUpdate();
        }
    }
}
