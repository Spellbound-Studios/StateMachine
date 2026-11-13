// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using UnityEngine;

namespace Spellbound.StateMachine {
    public static class StateMachineKit {
        public static StateRegistry Registry { get; } = new();

        public static StateMachine<TContext, TStateKey> Create<TContext, TStateKey>(TContext context,
            IStateMachineConfiguration<TStateKey> configuration) where TContext : class where TStateKey : Enum {
            var machine = new StateMachine<TContext, TStateKey>(context);
            machine.Configure(configuration);

            return machine;
        }

        public static void UseStates(StateCatalogue catalogue) => Registry.Use(catalogue);

        public static void UseStates(IReadOnlyList<State> states) => Registry.Use(states);

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetForPlaySession() => Registry.Clear();
    }
}
