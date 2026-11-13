// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Spellbound.StateMachine.Tests {
    public class StateMachinePlayModeTests {
        private const int Frames = 6;

        private TickingState _asset;
        private StateMachine<object, TickingSlot> _machine;
        private MachineRunner _runner;

        [TearDown]
        public void TearDown() {
            if (_runner != null) {
                _runner.Machine = null;
                Object.Destroy(_runner.gameObject);
            }

            _machine?.Dispose();
            _machine = null;

            if (_asset != null)
                Object.Destroy(_asset);
        }

        [UnityTest]
        public IEnumerator StateMachine_DrivenForFrames_CountsUpdatesAndFixedUpdates() {
            _asset = ScriptableObject.CreateInstance<TickingState>();
            var configuration = new TickingConfiguration(TickingSlot.Running,
                new TickingBinding(TickingSlot.Running, _asset));
            _machine = StateMachineKit.Create(new object(), configuration);
            _runner = new GameObject(nameof(MachineRunner)).AddComponent<MachineRunner>();
            _runner.Machine = _machine;

            for (var frame = 0; frame < Frames; frame++)
                yield return null;

            yield return new WaitForFixedUpdate();

            var running = _machine.GetState<TickingState>();
            Assert.AreEqual(TickingSlot.Running, _machine.CurrentStateKey);
            Assert.AreEqual(1, running.EnterCount);
            Assert.GreaterOrEqual(running.UpdateCount, Frames - 1);
            Assert.AreEqual(_runner.UpdateCalls, running.UpdateCount);
            Assert.Greater(running.FixedUpdateCount, 0);
            Assert.AreEqual(_runner.FixedUpdateCalls, running.FixedUpdateCount);
            Assert.AreEqual(0, _asset.UpdateCount);
        }
    }
}
