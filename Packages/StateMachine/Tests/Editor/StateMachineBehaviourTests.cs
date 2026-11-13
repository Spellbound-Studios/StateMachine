// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;
using Spellbound.Core.Logging;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateMachineBehaviourTests {
        private StateFixtures _fixtures;
        private object _context;

        [SetUp]
        public void SetUp() {
            _fixtures = new StateFixtures();
            _context = new object();
        }

        [TearDown]
        public void TearDown() => _fixtures.DestroyAll();

        [Test]
        public void StateMachine_EntersInitialState() {
            var second = _fixtures.Create<SecondCountingState>("second");
            var configuration = _fixtures.Configuration(CountingSlot.Second,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, second));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            Assert.AreEqual(CountingSlot.Second, machine.CurrentStateKey);
            Assert.IsTrue(machine.IsInState<SecondCountingState>());
            Assert.AreNotEqual(0u, second.Hash);
            Assert.AreEqual(second.Hash, machine.CurrentStateHash);
            var entered = machine.GetState<SecondCountingState>();
            Assert.AreEqual(1, entered.EnterCount);
            Assert.AreEqual(1, entered.InitializeCount);
            Assert.AreSame(_context, entered.Context);
            Assert.AreEqual(0, machine.GetState<FirstCountingState>().EnterCount);
        }

        [Test]
        public void StateMachine_TransitionsOnRequest() {
            var secondAsset = _fixtures.Create<SecondCountingState>("second");
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, secondAsset));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            machine.ChangeState(CountingSlot.Second);
            machine.UpdateStateMachine();
            machine.FixedUpdateStateMachine();

            var first = machine.GetState<FirstCountingState>();
            var second = machine.GetState<SecondCountingState>();
            Assert.AreEqual(CountingSlot.Second, machine.CurrentStateKey);
            Assert.IsTrue(machine.IsInState(secondAsset.Hash));
            Assert.AreEqual(1, first.EnterCount);
            Assert.AreEqual(1, first.ExitCount);
            Assert.AreEqual(1, second.EnterCount);
            Assert.AreEqual(1, second.UpdateCount);
            Assert.AreEqual(1, second.FixedUpdateCount);
            Assert.AreEqual(0, first.UpdateCount);
        }

        [Test]
        public void StateMachine_RefusesUnboundState_LogsError() {
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));
            var recording = new RecordingLogSink(LogLevel.Error);

            using (Log.SuspendSinks()) {
                using (Log.AddScopedSink(recording, null, LogLevel.Verbose))
                    machine.ChangeState((CountingSlot)99);
            }

            Assert.AreEqual(1, recording.CountOf(LogLevel.Error));
            Assert.IsTrue(recording.Contains(LogLevel.Error, "No state driver registered"));
            Assert.AreEqual(CountingSlot.First, machine.CurrentStateKey);
            Assert.IsTrue(machine.IsInState<FirstCountingState>());
            Assert.AreEqual(0, machine.GetState<FirstCountingState>().ExitCount);
        }

        [Test]
        public void StateMachine_ConfigurationSwap_ChangesBoundStates() {
            var firstConfiguration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")));
            var third = _fixtures.Create<ThirdCountingState>("third");
            var secondConfiguration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, third));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, firstConfiguration));
            var first = machine.GetState<FirstCountingState>();

            machine.Configure(secondConfiguration);

            Assert.IsTrue(machine.IsInState<ThirdCountingState>());
            Assert.AreEqual(third.Hash, machine.CurrentStateHash);
            Assert.AreSame(machine.GetState<ThirdCountingState>(), machine.GetCurrentVariant(CountingSlot.First));
            Assert.AreEqual(1, first.ExitCount);
            Assert.IsNull(machine.GetState<FirstCountingState>());
            Assert.AreEqual(1, machine.GetState<ThirdCountingState>().EnterCount);
        }

        [Test]
        public void StateMachine_SecondConfigure_LeavesTheSlotsItDoesNotBindEmpty() {
            var firstConfiguration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, _fixtures.Create<SecondCountingState>("second")));
            var secondConfiguration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<ThirdCountingState>("third")));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, firstConfiguration));
            var recording = new RecordingLogSink(LogLevel.Error);
            var second = machine.GetState<SecondCountingState>();

            machine.Configure(secondConfiguration);

            using (Log.SuspendSinks()) {
                using (Log.AddScopedSink(recording, null, LogLevel.Verbose)) {
                    machine.ChangeState(CountingSlot.Second);
                    machine.RestoreDefault(CountingSlot.Second);
                }
            }

            Assert.IsNull(machine.GetCurrentVariant(CountingSlot.Second));
            Assert.AreEqual(2, recording.CountOf(LogLevel.Error));
            Assert.IsTrue(recording.Contains(LogLevel.Error, "No state is bound to slot Second"));
            Assert.IsTrue(recording.Contains(LogLevel.Error, "No default variant recorded for slot Second"));
            Assert.AreEqual(CountingSlot.First, machine.CurrentStateKey);
            Assert.IsTrue(machine.IsInState<ThirdCountingState>());
            Assert.AreEqual(0, second.EnterCount);
        }

        [Test]
        public void StateMachine_ConfigureWithAnUnboundInitialSlot_ChangesNothing() {
            var firstConfiguration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, _fixtures.Create<SecondCountingState>("second")));
            var secondConfiguration = _fixtures.Configuration(CountingSlot.Second,
                new CountingBinding(CountingSlot.First, _fixtures.Create<ThirdCountingState>("third")));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, firstConfiguration));
            var running = machine.GetState<FirstCountingState>();
            var waiting = machine.GetState<SecondCountingState>();
            var recording = new RecordingLogSink(LogLevel.Error);

            using (Log.SuspendSinks()) {
                using (Log.AddScopedSink(recording, null, LogLevel.Verbose))
                    machine.Configure(secondConfiguration);
            }

            Assert.AreEqual(1, recording.CountOf(LogLevel.Error));
            Assert.IsTrue(recording.Contains(LogLevel.Error, "which no binding fills"));
            Assert.AreEqual(CountingSlot.First, machine.CurrentStateKey);
            Assert.AreSame(running, machine.CurrentState);
            Assert.AreEqual(0, running.ExitCount);
            Assert.AreSame(waiting, machine.GetCurrentVariant(CountingSlot.Second));
            Assert.IsNull(machine.GetState<ThirdCountingState>());
        }

        [Test]
        public void StateMachine_ChangeStateIntoTheActiveSlot_NeitherExitsNorEnters() {
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));
            var running = machine.GetState<FirstCountingState>();

            machine.ChangeState(CountingSlot.First);

            Assert.AreEqual(1, running.EnterCount);
            Assert.AreEqual(0, running.ExitCount);
        }

        [Test]
        public void StateMachine_ConfigureThatReachesNoDriver_LeavesTheKeyAtItsDefault() {
            var firstConfiguration = _fixtures.Configuration(CountingSlot.Second,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, _fixtures.Create<SecondCountingState>("second")));
            var unknown = (CountingSlot)99;
            var secondConfiguration = _fixtures.Configuration(unknown,
                new CountingBinding(unknown, _fixtures.Create<ThirdCountingState>("third")));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, firstConfiguration));
            var recording = new RecordingLogSink(LogLevel.Error);

            using (Log.SuspendSinks()) {
                using (Log.AddScopedSink(recording, null, LogLevel.Verbose))
                    machine.Configure(secondConfiguration);
            }

            Assert.AreEqual(2, recording.CountOf(LogLevel.Error));
            Assert.AreEqual(default(CountingSlot), machine.CurrentStateKey);
            Assert.IsNull(machine.CurrentState);
        }

        [Test]
        public void StateMachine_SetInitialVariantWithNoVariant_LogsAnError() {
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));
            var recording = new RecordingLogSink(LogLevel.Error);

            using (Log.SuspendSinks()) {
                using (Log.AddScopedSink(recording, null, LogLevel.Verbose))
                    machine.SetInitialVariant(CountingSlot.Second, null);
            }

            Assert.AreEqual(1, recording.CountOf(LogLevel.Error));
            Assert.IsTrue(recording.Contains(LogLevel.Error, "SetInitialVariant called with a null variant"));
            Assert.IsNull(machine.GetCurrentVariant(CountingSlot.Second));
        }

        [Test]
        public void StateMachine_IsInState_IsFalseForAStateThatIsNotRunning() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, first),
                new CountingBinding(CountingSlot.Second, second));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            Assert.IsTrue(machine.IsInState(first.Hash));
            Assert.IsFalse(machine.IsInState(second.Hash));
            Assert.IsTrue(machine.IsInState<FirstCountingState>());
            Assert.IsFalse(machine.IsInState<SecondCountingState>());
        }

        [Test]
        public void StateMachine_RegistersClonesAndLeavesTheAssetUntouched() {
            var source = _fixtures.Create<FirstCountingState>("first");
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, source));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            Assert.AreNotSame(source, machine.CurrentState);
            Assert.AreEqual(0, source.EnterCount);
            Assert.AreEqual(source.Hash, machine.CurrentState.Hash);
        }
    }
}
