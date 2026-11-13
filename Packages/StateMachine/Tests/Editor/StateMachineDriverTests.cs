// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateMachineDriverTests {
        private StateFixtures _fixtures;
        private StateMachine<object, CountingSlot> _machine;

        [SetUp]
        public void SetUp() {
            _fixtures = new StateFixtures();
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, _fixtures.Create<SecondCountingState>("second")));
            _machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(new object(), configuration));
        }

        [TearDown]
        public void TearDown() => _fixtures.DestroyAll();

        [Test]
        public void RegisterStateDriver_OnAConfiguredSlot_MovesTheSlotsStateToTheNewDriver() {
            var bound = _machine.GetState<SecondCountingState>();
            var driver = new CountingDriver();

            _machine.RegisterStateDriver(CountingSlot.Second, driver);
            _machine.ChangeState(CountingSlot.Second);
            _machine.UpdateStateMachine();

            Assert.AreSame(bound, driver.CurrentVariant);
            Assert.AreSame(driver, _machine.CurrentActiveDriver);
            Assert.AreEqual(1, bound.EnterCount);
            Assert.AreEqual(1, driver.UpdateCount);
            Assert.AreEqual(1, bound.UpdateCount);
        }

        [Test]
        public void RegisterStateDriver_OnTheActiveSlot_ExitsTheOldDriverAndEntersTheNewOne() {
            var running = _machine.GetState<FirstCountingState>();
            var previous = _machine.CurrentActiveDriver;
            var driver = new CountingDriver();

            _machine.RegisterStateDriver(CountingSlot.First, driver);
            _machine.UpdateStateMachine();

            Assert.AreSame(driver, _machine.CurrentActiveDriver);
            Assert.AreSame(running, driver.CurrentVariant);
            Assert.IsTrue(driver.IsActive);
            Assert.IsFalse(previous.IsActive);
            Assert.IsNull(previous.CurrentVariant);
            Assert.AreEqual(1, driver.ActivationCount);
            Assert.AreEqual(1, running.ExitCount);
            Assert.AreEqual(2, running.EnterCount);
            Assert.AreEqual(1, driver.UpdateCount);
            Assert.AreEqual(1, running.UpdateCount);
        }
    }
}
