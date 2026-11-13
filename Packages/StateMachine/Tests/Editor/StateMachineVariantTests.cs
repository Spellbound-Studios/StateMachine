// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;
using UnityEngine;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateMachineVariantTests {
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
        public void StateMachine_TwoAssetsOfOneClass_RunTheirOwnCopies() {
            var gentle = _fixtures.Create<TunedCountingState>("gentle");
            gentle.Tuning = 1;
            var strong = _fixtures.Create<TunedCountingState>("strong");
            strong.Tuning = 2;
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, gentle),
                new CountingBinding(CountingSlot.Second, strong));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            var firstCopy = (TunedCountingState)machine.GetCurrentVariant(CountingSlot.First);
            var secondCopy = (TunedCountingState)machine.GetCurrentVariant(CountingSlot.Second);
            Assert.AreNotSame(firstCopy, secondCopy);
            Assert.AreEqual(1, firstCopy.Tuning);
            Assert.AreEqual(2, secondCopy.Tuning);
            Assert.AreEqual(gentle.Hash, machine.CurrentStateHash);
            Assert.AreSame(firstCopy, machine.GetState<TunedCountingState>());

            machine.ChangeState(CountingSlot.Second);

            Assert.AreEqual(strong.Hash, machine.CurrentStateHash);
            Assert.AreEqual(1, secondCopy.EnterCount);
            Assert.AreEqual(1, firstCopy.ExitCount);
            Assert.AreSame(secondCopy, machine.GetState<TunedCountingState>());
        }

        [Test]
        public void StateMachine_GetState_ReturnsTheOnlyCopyOfATypeWhereverItRuns() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var configuration = _fixtures.Configuration(CountingSlot.Second,
                new CountingBinding(CountingSlot.First, first),
                new CountingBinding(CountingSlot.Second, second));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            Assert.AreSame(machine.GetCurrentVariant(CountingSlot.First), machine.GetState<FirstCountingState>());
            Assert.IsNull(machine.GetState<ThirdCountingState>());
        }

        [Test]
        public void StateMachine_GetState_FindsACopySetForAnotherSlotWhileTheMachineRunsAnother() {
            var strong = _fixtures.Create<TunedCountingState>("strong");
            var stronger = _fixtures.Create<TunedCountingState>("stronger");
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, strong));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            machine.SetInitialVariant(CountingSlot.Second, stronger);

            var found = machine.GetState<TunedCountingState>();
            Assert.IsNotNull(found);
            Assert.AreEqual(stronger.Hash, found.Hash);
            Assert.AreSame(machine.GetCurrentVariant(CountingSlot.Second), found);
        }

        [Test]
        public void StateMachine_GetState_NeverReturnsAnAbstractBase() {
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            Assert.IsNull(machine.GetState<CountingState>());
            Assert.IsNull(machine.GetState<State>());
        }

        [Test]
        public void StateMachine_StateWithNoAsset_IsCopiedOnceAcrossTwoConfigures() {
            var unsaved = _fixtures.DestroyAfterTest(ScriptableObject.CreateInstance<FirstCountingState>());
            var configuration = new CodeConfiguration(CountingSlot.First).Bind(CountingSlot.First, unsaved);
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));
            var copy = machine.GetState<FirstCountingState>();

            machine.Configure(configuration);

            Assert.AreEqual(0u, unsaved.Hash);
            Assert.AreSame(copy, machine.GetState<FirstCountingState>());
            Assert.AreEqual(1, copy.InitializeCount);
            Assert.AreEqual(2, copy.EnterCount);
        }

        [Test]
        public void StateMachine_TwoBindingsOnOneSlot_TheFirstWins() {
            var configuration = new CodeConfiguration(CountingSlot.First)
                .Bind(CountingSlot.First, _fixtures.Create<FirstCountingState>("first"))
                .Bind(CountingSlot.First, _fixtures.Create<ThirdCountingState>("third"));

            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));

            Assert.IsTrue(machine.IsInState<FirstCountingState>());
            Assert.IsInstanceOf<FirstCountingState>(machine.GetCurrentVariant(CountingSlot.First));
        }

        [Test]
        public void StateMachine_ApplyVariantByType_PutsTheHeldCopyInTheSlot() {
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, _fixtures.Create<FirstCountingState>("first")),
                new CountingBinding(CountingSlot.Second, _fixtures.Create<ThirdCountingState>("third")));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));
            var third = machine.GetState<ThirdCountingState>();

            machine.ApplyVariant<ThirdCountingState>(CountingSlot.First);

            Assert.AreSame(third, machine.CurrentActiveDriver.CurrentVariant);
            Assert.IsTrue(machine.IsInState<ThirdCountingState>());
            Assert.AreEqual(1, third.EnterCount);
        }

        [Test]
        public void StateMachine_ApplyVariant_PutsTheNewCopyInTheSlotsDriver() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var third = _fixtures.Create<ThirdCountingState>("third");
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, first));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));
            var original = machine.GetState<FirstCountingState>();

            machine.ApplyVariant(CountingSlot.First, third);

            var applied = machine.CurrentActiveDriver.CurrentVariant;
            Assert.IsInstanceOf<ThirdCountingState>(applied);
            Assert.AreNotSame(third, applied);
            Assert.AreEqual(third.Hash, applied.Hash);
            Assert.AreEqual(third.Hash, machine.CurrentStateHash);
            Assert.AreEqual(1, ((CountingState)applied).EnterCount);
            Assert.AreEqual(1, original.ExitCount);
        }

        [Test]
        public void StateMachine_RestoreDefault_PutsTheConfiguredCopyBack() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var third = _fixtures.Create<ThirdCountingState>("third");
            var configuration = _fixtures.Configuration(CountingSlot.First,
                new CountingBinding(CountingSlot.First, first));
            var machine = _fixtures.DisposeAfterTest(StateMachineKit.Create(_context, configuration));
            var original = machine.GetState<FirstCountingState>();
            machine.ApplyVariant(CountingSlot.First, third);
            var applied = machine.GetState<ThirdCountingState>();

            machine.RestoreDefault(CountingSlot.First);

            Assert.AreSame(original, machine.CurrentActiveDriver.CurrentVariant);
            Assert.AreEqual(first.Hash, machine.CurrentStateHash);
            Assert.AreEqual(2, original.EnterCount);
            Assert.AreEqual(1, applied.ExitCount);
            Assert.IsNull(machine.GetState<ThirdCountingState>());
        }
    }
}
