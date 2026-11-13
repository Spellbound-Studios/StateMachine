// Copyright (c) Spellbound Studios. All rights reserved.

using System.Globalization;
using NUnit.Framework;
using Spellbound.Core;
using Spellbound.Core.Observations;
using Spellbound.Core.Operations;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateMachineOperationsTests {
        private StateFixtures _fixtures;

        [SetUp]
        public void SetUp() {
            _fixtures = new StateFixtures();
            StateMachineKit.Registry.Clear();
        }

        [TearDown]
        public void TearDown() {
            StateMachineKit.Registry.Clear();
            _fixtures.DestroyAll();
        }

        [Test]
        public void States_OfAnEmptyRegistry_ListsNothing() {
            var lines = Lines(Text("statemachine states"));

            Assert.AreEqual("succeeded: 0 states in the registry", lines[0]);
            Assert.AreEqual(1, lines.Length);
        }

        [Test]
        public void States_OfThreeStates_ListsThree() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var third = _fixtures.Create<ThirdCountingState>("third");
            StateMachineKit.UseStates(new State[] { first, second, third });

            var text = Text("statemachine states");

            StringAssert.StartsWith("succeeded: 3 states in the registry\n", text);
            StringAssert.Contains(Row(first), text);
            StringAssert.Contains(Row(second), text);
            StringAssert.Contains(Row(third), text);
        }

        [Test]
        public void States_WithOffsetAndLimit_ListsOnePage() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var third = _fixtures.Create<ThirdCountingState>("third");
            StateMachineKit.UseStates(new State[] { first, second, third });

            var text = Text("statemachine states --offset 1 --limit 1");

            StringAssert.StartsWith("succeeded: 3 states in the registry, 1 listed from 1\n", text);
            StringAssert.Contains(Row(second), text);
            StringAssert.DoesNotContain(Row(first), text);
            StringAssert.DoesNotContain(Row(third), text);
        }

        [Test]
        public void States_WithANegativeOffset_IsRefused() {
            StringAssert.Contains("--offset is 0 or more", Text("statemachine states --offset -1"));
        }

        [Test]
        public void Help_ListsTheStatesOperation() {
            var text = Text("core help --group statemachine");

            StringAssert.Contains("statemachine states [--offset <integer> = 0] [--limit <integer> = 50]", text);
            StringAssert.Contains("[reads, anyone]", text);
        }

        private static string Text(string line) =>
            CoreKit.Operations.Run(line, OperationCaller.Development(), ObservationContext.Discard).Result.Text;

        private static string[] Lines(string text) => text.Split('\n');

        private static string Row(State state) => state.Hash.ToString(CultureInfo.InvariantCulture);
    }
}
