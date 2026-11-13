// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using UnityEngine;

namespace Spellbound.StateMachine.Samples {
    public sealed class TrafficLightContext {
        private static readonly int BaseColorProperty = Shader.PropertyToID("_BaseColor");
        private static readonly int ColorProperty = Shader.PropertyToID("_Color");

        private readonly Action<TrafficLightPhase> _changePhase;
        private readonly MaterialPropertyBlock _properties = new();

        public TrafficLightContext(Light light, Renderer renderer, Action<TrafficLightPhase> changePhase) {
            Light = light;
            Renderer = renderer;
            _changePhase = changePhase;
        }

        public Light Light { get; }

        public Renderer Renderer { get; }

        public void Show(Color colour) {
            Light.color = colour;
            Renderer.GetPropertyBlock(_properties);
            _properties.SetColor(BaseColorProperty, colour);
            _properties.SetColor(ColorProperty, colour);
            Renderer.SetPropertyBlock(_properties);
        }

        public void ChangePhase(TrafficLightPhase phase) => _changePhase(phase);
    }
}
