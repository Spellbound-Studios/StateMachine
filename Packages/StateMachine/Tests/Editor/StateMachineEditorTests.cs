// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateMachineEditorTests {
        [Test]
        public void FrontDoorTypeExists() {
            Assert.IsNotNull(typeof(StateMachineKit));
        }
    }
}
