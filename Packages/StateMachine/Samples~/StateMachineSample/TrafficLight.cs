// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEngine;
using UnityEngine.Rendering;

namespace Spellbound.StateMachine.Samples {
    public sealed class TrafficLight : MonoBehaviour {
        [SerializeField] private Light lamp;
        [SerializeField] private Renderer lens;
        [SerializeField] private Renderer ground;
        [SerializeField] private Material lampMaterialBuiltIn;
        [SerializeField] private Material lampMaterialUniversal;
        [SerializeField] private Material groundMaterialBuiltIn;
        [SerializeField] private Material groundMaterialUniversal;
        [SerializeField] private StateCatalogue states;
        [SerializeField] private StateMachineConfiguration<TrafficLightPhase> configuration = new();

        private StateMachine<TrafficLightContext, TrafficLightPhase> _machine;

        public StateRegistry Registry { get; private set; }

        private void Awake() {
            UsePipelineMaterials();
            Registry = states != null ? new StateRegistry(states) : new StateRegistry();
            _machine = StateMachineKit.Create(new TrafficLightContext(lamp, lens, ChangePhase), configuration);
        }

        private void Update() => _machine.UpdateStateMachine();

        private void OnDestroy() => _machine?.Dispose();

        private void ChangePhase(TrafficLightPhase phase) => _machine.ChangeState(phase);

        private void UsePipelineMaterials() {
            var isUniversal = GraphicsSettings.currentRenderPipeline != null;

            if (lens != null)
                lens.sharedMaterial = isUniversal ? lampMaterialUniversal : lampMaterialBuiltIn;

            if (ground != null)
                ground.sharedMaterial = isUniversal ? groundMaterialUniversal : groundMaterialBuiltIn;
        }
    }
}
