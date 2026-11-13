// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEngine;

namespace Spellbound.StateMachine.Samples {
    [CreateAssetMenu(fileName = "RedPhase", menuName = "Spellbound/StateMachine/Samples/RedPhase")]
    public sealed class RedPhase : TimedPhase {
        protected override TrafficLightPhase NextPhase => TrafficLightPhase.Green;
    }
}
