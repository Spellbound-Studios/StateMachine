// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using Spellbound.Core.Logging;
using Spellbound.Core.Registries;

namespace Spellbound.StateMachine {
    public sealed class StateRegistry {
        private readonly HashRegistry<State> _registry = new();

        public StateRegistry() { }

        public StateRegistry(IReadOnlyList<State> states) => Use(states);

        public StateRegistry(StateCatalogue catalogue) => Use(catalogue);

        public int Count => _registry.Count;

        public IReadOnlyList<State> All => _registry.All;

        public void Use(IReadOnlyList<State> states) {
            if (states == null) {
                Log.Error("The state registry was given no list of states; it keeps the states it held.");

                return;
            }

            _registry.Clear();
            _registry.AddRange(states);
        }

        public void Use(StateCatalogue catalogue) {
            if (catalogue == null) {
                Log.Error("The state registry was given no catalogue; it keeps the states it held.");

                return;
            }

            Use(catalogue.States);
        }

        public void Add(State state) => _registry.Add(state);

        public void Clear() => _registry.Clear();

        public bool TryGet(uint hash, out State state) => _registry.TryGet(hash, out state);

        public State Get(uint hash) => _registry.Get(hash);

        public bool Contains(uint hash) => _registry.Contains(hash);

        public static void WriteState(ref Span<byte> buffer, State state) => RegistryPacker.Write(ref buffer, state);

        public State ReadState(ref ReadOnlySpan<byte> buffer) => RegistryPacker.Read(ref buffer, _registry);
    }
}
