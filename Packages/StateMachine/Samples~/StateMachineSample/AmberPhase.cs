// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEngine;

namespace Spellbound.StateMachine.Samples {
    [CreateAssetMenu(fileName = "AmberPhase", menuName = "Spellbound/StateMachine/Samples/AmberPhase")]
    public sealed class AmberPhase : TimedPhase {
        protected override TrafficLightPhase NextPhase => TrafficLightPhase.Red;
    }
}
