// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;

namespace Spellbound.StateMachine.Tests {
    public class StateMachineTests {
        [Test]
        public void FrontDoorTypeExists() {
            Assert.IsNotNull(typeof(StateMachineKit));
        }
    }
}
