// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using NUnit.Framework;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateMachineDisposeTests {
        private StateFixtures _fixtures;
        private FirstCountingState _first;
        private CountingConfiguration _configuration;
        private StateMachine<object, CountingSlot> _machine;

        [SetUp]
        public void SetUp() {
            _fixtures = new StateFixtures();
            _first = _fixtures.Create<FirstCountingState>("first");
            _configuration = _fixtures.Configuration(CountingSlot.Second,
                new CountingBinding(CountingSlot.First, _first),
                new CountingBinding(CountingSlot.Second, _fixtures.Create<SecondCountingState>("second")));
            _machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(new object(), _configuration));
        }

        [TearDown]
        public void TearDown() => _fixtures.DestroyAll();

        [Test]
        public void Dispose_ExitsTheActiveStateAndLeavesTheDriversEmpty() {
            var running = _machine.GetState<SecondCountingState>();
            var exitsBefore = running.ExitCount;

            _machine.Dispose();

            Assert.AreEqual(exitsBefore + 1, running.ExitCount);
            Assert.IsTrue(running == null);
            Assert.IsNull(_machine.GetCurrentVariant(CountingSlot.First));
            Assert.IsNull(_machine.GetCurrentVariant(CountingSlot.Second));
            Assert.IsNull(_machine.CurrentActiveDriver);
            Assert.IsNull(_machine.CurrentState);
            Assert.AreEqual(0u, _machine.CurrentStateHash);
            Assert.AreEqual(default(CountingSlot), _machine.CurrentStateKey);
        }

        [Test]
        public void Dispose_ThenRunningTheMachine_Throws() {
            _machine.Dispose();

            Assert.Throws<ObjectDisposedException>(() => _machine.ChangeState(CountingSlot.First));
            Assert.Throws<ObjectDisposedException>(() => _machine.ApplyVariant(CountingSlot.First, _first));
            Assert.Throws<ObjectDisposedException>(() => _machine.ApplyVariant<FirstCountingState>(CountingSlot.First));
            Assert.Throws<ObjectDisposedException>(() => _machine.UpdateStateMachine());
            Assert.Throws<ObjectDisposedException>(() => _machine.FixedUpdateStateMachine());
        }

        [Test]
        public void Dispose_ThenConfiguringTheMachine_Throws() {
            _machine.Dispose();

            Assert.Throws<ObjectDisposedException>(() => _machine.Configure(_configuration));
            Assert.Throws<ObjectDisposedException>(() => _machine.SetInitialVariant(CountingSlot.First, _first));
            Assert.Throws<ObjectDisposedException>(() => _machine.RegisterState(_first));
            Assert.Throws<ObjectDisposedException>(() =>
                _machine.RegisterStateDriver(CountingSlot.First, new StateDriver()));
            Assert.Throws<ObjectDisposedException>(() => _machine.RestoreDefault(CountingSlot.First));
        }

        [Test]
        public void Dispose_Twice_DoesNothingMore() {
            _machine.Dispose();

            Assert.DoesNotThrow(() => _machine.Dispose());
        }
    }
}
