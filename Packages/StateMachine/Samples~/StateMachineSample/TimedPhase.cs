// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEngine;

namespace Spellbound.StateMachine.Samples {
    public abstract class TimedPhase : State {
        [SerializeField] private float duration = 3f;
        [SerializeField] private Color colour = Color.white;

        private TrafficLightContext _trafficLight;
        private float _elapsed;

        protected abstract TrafficLightPhase NextPhase { get; }

        protected override void OnContextInitialized() => _trafficLight = (TrafficLightContext)Context;

        protected override void EnterStateLogic() {
            _elapsed = 0f;
            _trafficLight.Show(colour);
        }

        protected override void UpdateStateLogic() {
            _elapsed += Time.deltaTime;

            if (_elapsed >= duration)
                _trafficLight.ChangePhase(NextPhase);
        }

        protected override void FixedUpdateStateLogic() { }

        protected override void ExitStateLogic() { }
    }
}
