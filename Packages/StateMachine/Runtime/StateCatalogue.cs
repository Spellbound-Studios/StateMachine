// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections.Generic;
using UnityEngine;

namespace Spellbound.StateMachine {
    [CreateAssetMenu(fileName = "StateCatalogue", menuName = "Spellbound/StateMachine/State Catalogue")]
    public sealed class StateCatalogue : ScriptableObject {
        [SerializeField] private List<State> states = new();

        public IReadOnlyList<State> States => states;
    }
}
