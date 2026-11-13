// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEngine;

namespace Spellbound.StateMachine.Samples {
    [CreateAssetMenu(fileName = "GreenPhase", menuName = "Spellbound/StateMachine/Samples/GreenPhase")]
    public sealed class GreenPhase : TimedPhase {
        protected override TrafficLightPhase NextPhase => TrafficLightPhase.Amber;
    }
}
