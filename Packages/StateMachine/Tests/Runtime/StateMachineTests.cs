// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Spellbound.StateMachine.Tests {
    public class StateMachineTests {
        private TickingState _asset;
        private StateMachine<object, TickingSlot> _machine;

        [TearDown]
        public void TearDown() {
            _machine?.Dispose();
            _machine = null;

            if (_asset != null)
                Object.Destroy(_asset);
        }

        [UnityTest]
        public IEnumerator StateMachine_TickedOnTwoFrames_UpdatesItsStateTwice() {
            _asset = ScriptableObject.CreateInstance<TickingState>();
            _machine = StateMachineKit.Create(new object(),
                new StateMachineConfiguration<TickingSlot>(TickingSlot.Running,
                    new StateBinding<TickingSlot>(TickingSlot.Running, _asset)));
            var firstFrame = Time.frameCount;

            _machine.UpdateStateMachine();
            yield return null;
            _machine.UpdateStateMachine();
            yield return null;

            var running = _machine.GetState<TickingState>();
            Assert.Greater(Time.frameCount, firstFrame);
            Assert.AreEqual(TickingSlot.Running, _machine.CurrentStateKey);
            Assert.AreEqual(1, running.EnterCount);
            Assert.AreEqual(2, running.UpdateCount);
            Assert.AreEqual(0, _asset.UpdateCount);
        }
    }
}
