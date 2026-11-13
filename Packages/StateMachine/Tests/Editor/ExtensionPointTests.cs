// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using NUnit.Framework;

namespace Spellbound.StateMachine.Editor.Tests {
    public class ExtensionPointTests {
        private StateFixtures _fixtures;

        [SetUp]
        public void SetUp() => _fixtures = new StateFixtures();

        [TearDown]
        public void TearDown() => _fixtures.DestroyAll();

        [Test]
        public void IStateBinding_CustomImplementation() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var bindings = new List<DeferredBinding> {
                new(CountingSlot.First, () => first),
                new(CountingSlot.Second, () => second)
            };
            var machine = _fixtures.DisposeAfterTest(new StateMachine<object, CountingSlot>(new object()));

            machine.Configure(bindings, CountingSlot.Second);

            Assert.IsTrue(machine.IsInState<SecondCountingState>());
            Assert.AreEqual(second.Hash, machine.CurrentStateHash);
            Assert.AreEqual(first.Hash, machine.GetCurrentVariant(CountingSlot.First).Hash);
            Assert.Greater(bindings[0].ResolveCount, 0);
            Assert.Greater(bindings[1].ResolveCount, 0);
        }

        [Test]
        public void IStateMachineConfiguration_CustomImplementation() {
            var configuration = new CodeConfiguration(CountingSlot.Second)
                .Bind(CountingSlot.First, _fixtures.Create<FirstCountingState>("first"))
                .Bind(CountingSlot.Second, _fixtures.Create<ThirdCountingState>("third"));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(new object(), configuration));

            Assert.AreEqual(CountingSlot.Second, machine.CurrentStateKey);
            Assert.IsTrue(machine.IsInState<ThirdCountingState>());
            Assert.IsInstanceOf<FirstCountingState>(machine.GetCurrentVariant(CountingSlot.First));
        }

        [Test]
        public void State_CustomImplementation() {
            var context = new RecordingContext();
            var configuration = new CodeConfiguration(CountingSlot.First)
                .Bind(CountingSlot.First, _fixtures.Create<RecordingState>("recording"))
                .Bind(CountingSlot.Second, _fixtures.Create<SecondCountingState>("second"));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(context, configuration));
            var recording = machine.GetState<RecordingState>();

            machine.UpdateStateMachine();
            machine.FixedUpdateStateMachine();
            machine.ChangeState(CountingSlot.Second);
            machine.UpdateStateMachine();

            Assert.AreSame(context, recording.TypedContext);
            CollectionAssert.AreEqual(new[] { "context", "initialize", "enter", "update", "fixed update", "exit" },
                recording.Calls);
        }

        [Test]
        public void IStateMachine_CustomImplementation() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var registry = new StateRegistry(new State[] { first, second });
            IStateMachine handWritten = new SingleStateMachine(second);

            var resolved = ResolveThroughRegistry(handWritten, registry);

            Assert.AreSame(second, resolved);
            Assert.IsTrue(handWritten.IsInState<SecondCountingState>());
            Assert.IsFalse(handWritten.IsInState<FirstCountingState>());
            Assert.IsTrue(handWritten.IsInState(second.Hash));
            Assert.IsFalse(handWritten.IsInState(first.Hash));
            Assert.IsNull(ResolveThroughRegistry(new SingleStateMachine(null), registry));
        }

        [Test]
        public void StateDriver_CustomImplementation() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var configuration = new CodeConfiguration(CountingSlot.First).Bind(CountingSlot.First, first);
            var driver = new CountingDriver();
            var machine = _fixtures.DisposeAfterTest(new StateMachine<object, CountingSlot>(new object()));
            machine.RegisterStateDriver(CountingSlot.First, driver);

            machine.Configure(configuration);
            machine.UpdateStateMachine();
            machine.UpdateStateMachine();
            machine.FixedUpdateStateMachine();

            var running = machine.GetState<FirstCountingState>();
            Assert.AreSame(driver, machine.CurrentActiveDriver);
            Assert.AreSame(running, driver.CurrentVariant);
            Assert.AreEqual(1, driver.VariantChangeCount);
            Assert.AreEqual(1, driver.ActivationCount);
            Assert.AreEqual(2, driver.UpdateCount);
            Assert.AreEqual(1, driver.FixedUpdateCount);
            Assert.AreEqual(2, running.UpdateCount);
            Assert.AreEqual(1, running.FixedUpdateCount);
        }

        private static State ResolveThroughRegistry(IStateMachine machine, StateRegistry registry) {
            var bytes = new byte[4];
            var writer = new Span<byte>(bytes);
            StateRegistry.WriteState(ref writer, machine.CurrentState);
            var reader = new ReadOnlySpan<byte>(bytes);
            var resolved = registry.ReadState(ref reader);
            Assert.AreEqual(machine.CurrentStateHash, resolved != null ? resolved.Hash : 0u);

            return resolved;
        }
    }
}
