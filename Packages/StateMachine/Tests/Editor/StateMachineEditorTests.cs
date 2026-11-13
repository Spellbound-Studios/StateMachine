// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateMachineEditorTests {
        private StateFixtures _fixtures;

        [SetUp]
        public void SetUp() => _fixtures = new StateFixtures();

        [TearDown]
        public void TearDown() => _fixtures.DestroyAll();

        [Test]
        public void StateMachineKit_CreateWithTheDefaultConfiguration_StartsInTheInitialState() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(new object(),
                new StateMachineConfiguration<CountingSlot>(CountingSlot.Second,
                    new StateBinding<CountingSlot>(CountingSlot.First, first),
                    new StateBinding<CountingSlot>(CountingSlot.Second, second))));

            Assert.AreEqual(CountingSlot.Second, machine.CurrentStateKey);
            Assert.AreEqual(second.Hash, machine.CurrentStateHash);
            Assert.AreEqual(1, machine.GetState<SecondCountingState>().EnterCount);
            Assert.AreEqual(first.Hash, machine.GetCurrentVariant(CountingSlot.First).Hash);
        }
    }
}
