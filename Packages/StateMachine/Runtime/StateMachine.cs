// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using Spellbound.Core.Logging;
using UnityEngine;
using Object = UnityEngine.Object;

namespace Spellbound.StateMachine {
    public sealed class StateMachine<TContext, TStateKey> : IStateMachine, IDisposable
        where TContext : class where TStateKey : Enum {
        private readonly Dictionary<TStateKey, StateDriver> _stateDrivers = new();
        private readonly Dictionary<uint, State> _copiesByHash = new();
        private readonly Dictionary<State, State> _unhashedCopies = new();
        private readonly List<State> _copies = new();
        private readonly Dictionary<TStateKey, State> _defaultVariants = new();
        private bool _isDisposed;

        public StateMachine(TContext context) {
            Context = context;
            InitializeStateDrivers();
        }

        public StateDriver CurrentActiveDriver { get; private set; }

        public TContext Context { get; }

        public TStateKey CurrentStateKey { get; private set; }

        public State CurrentState => GetCurrentRunningState();

        public uint CurrentStateHash {
            get {
                var state = GetCurrentRunningState();

                return state != null ? state.Hash : 0u;
            }
        }

        public void Configure(IStateMachineConfiguration<TStateKey> configuration) {
            ThrowIfDisposed();

            if (configuration == null) {
                Log.Error("Configure called with a null configuration; the state machine has no states.");

                return;
            }

            ConfigureFromBindings(configuration.Bindings, configuration.InitialState);
        }

        public void Configure<TBinding>(List<TBinding> bindings, TStateKey initialState)
            where TBinding : class, IStateBinding<TStateKey> {
            ThrowIfDisposed();
            ConfigureFromBindings(bindings, initialState);
        }

        public void SetInitialVariant(TStateKey stateKey, State initialVariant) {
            ThrowIfDisposed();

            if (!_stateDrivers.TryGetValue(stateKey, out var driver)) {
                Log.Error($"No state driver found for state key: {stateKey}");

                return;
            }

            if (initialVariant == null) {
                Log.Error($"SetInitialVariant called with a null variant for slot {stateKey}; ignoring.");

                return;
            }

            var instance = RegisterState(initialVariant);
            _defaultVariants[stateKey] = instance;
            driver.ChangeVariant(instance);
        }

        public State RegisterState(State source) {
            ThrowIfDisposed();

            if (source == null) {
                Log.Error("Attempted to register a null state.");

                return null;
            }

            var hash = source.Hash;

            if (hash != 0u && _copiesByHash.TryGetValue(hash, out var existing))
                return existing;

            if (hash == 0u && _unhashedCopies.TryGetValue(source, out existing))
                return existing;

            var instance = Object.Instantiate(source);
            instance.name = source.name;

            if (hash != 0u) {
                _copiesByHash[hash] = instance;
            } else {
                _unhashedCopies[source] = instance;
                _unhashedCopies[instance] = instance;
            }

            _copies.Add(instance);
            instance.InitializeWithContext(Context);

            return instance;
        }

        public void RegisterStateDriver(TStateKey stateKey, StateDriver stateDriver) {
            ThrowIfDisposed();

            if (stateDriver == null) {
                Log.Error($"RegisterStateDriver called with a null driver for {stateKey}; ignoring.");

                return;
            }

            if (!_stateDrivers.TryGetValue(stateKey, out var previous)) {
                _stateDrivers[stateKey] = stateDriver;

                return;
            }

            if (previous == stateDriver)
                return;

            var wasActive = previous == CurrentActiveDriver;

            if (wasActive)
                previous.OnBecomeInactive();

            var variant = previous.CurrentVariant;

            if (variant != null)
                previous.ChangeVariant(null);

            _stateDrivers[stateKey] = stateDriver;

            if (variant != null)
                stateDriver.ChangeVariant(variant);

            if (!wasActive)
                return;

            CurrentActiveDriver = stateDriver;
            stateDriver.OnBecomeActive();
        }

        public void ChangeState(TStateKey newStateKey) {
            ThrowIfDisposed();

            if (!_stateDrivers.TryGetValue(newStateKey, out var newDriver)) {
                Log.Error($"No state driver registered for state key: {newStateKey}");

                return;
            }

            if (CurrentActiveDriver == newDriver)
                return;

            if (newDriver.CurrentVariant == null) {
                Log.Error($"No state is bound to slot {newStateKey}; the machine stays where it is.");

                return;
            }

            CurrentActiveDriver?.OnBecomeInactive();
            CurrentActiveDriver = newDriver;
            CurrentStateKey = newStateKey;
            CurrentActiveDriver.OnBecomeActive();
        }

        public void ApplyVariant(TStateKey slot, State variant) {
            ThrowIfDisposed();

            if (!_stateDrivers.TryGetValue(slot, out var driver)) {
                Log.Error($"No state driver registered for state key: {slot}");

                return;
            }

            if (variant == null) {
                Log.Error($"ApplyVariant called with a null variant for slot {slot}; ignoring.");

                return;
            }

            driver.ChangeVariant(RegisterState(variant));
        }

        public void ApplyVariant<TVariant>(TStateKey slot) where TVariant : State {
            ThrowIfDisposed();
            var variant = GetState<TVariant>();

            if (variant == null) {
                Log.Error($"No registered variant of type {typeof(TVariant).Name}; list it in the configuration "
                          + "or apply it by reference first.");

                return;
            }

            ApplyVariant(slot, variant);
        }

        public void RestoreDefault(TStateKey slot) {
            ThrowIfDisposed();

            if (!_stateDrivers.TryGetValue(slot, out var driver)) {
                Log.Error($"No state driver registered for state key: {slot}");

                return;
            }

            if (_defaultVariants.TryGetValue(slot, out var defaultVariant) && defaultVariant != null) {
                driver.ChangeVariant(defaultVariant);

                return;
            }

            Log.Error($"No default variant recorded for slot {slot}; was the machine configured?");
        }

        public bool IsInState<TVariant>() where TVariant : State => GetCurrentRunningState() is TVariant;

        public bool IsInState(uint stateHash) {
            var state = GetCurrentRunningState();

            return state != null && state.Hash == stateHash;
        }

        public TVariant GetState<TVariant>() where TVariant : State {
            State only = null;
            var isAmbiguous = false;

            foreach (var driver in _stateDrivers.Values) {
                var held = driver.CurrentVariant;

                if (held == null || held.GetType() != typeof(TVariant))
                    continue;

                if (only == null)
                    only = held;
                else if (!ReferenceEquals(only, held))
                    isAmbiguous = true;
            }

            if (only != null && !isAmbiguous)
                return (TVariant)only;

            var running = GetCurrentRunningState();

            return running != null && running.GetType() == typeof(TVariant) ? (TVariant)running : null;
        }

        public State GetCurrentVariant(TStateKey stateKey) =>
            _stateDrivers.TryGetValue(stateKey, out var driver) ? driver.CurrentVariant : null;

        public State GetCurrentRunningState() => CurrentActiveDriver?.CurrentVariant;

        public void UpdateStateMachine() {
            ThrowIfDisposed();
            CurrentActiveDriver?.DriveUpdate();
        }

        public void FixedUpdateStateMachine() {
            ThrowIfDisposed();
            CurrentActiveDriver?.DriveFixedUpdate();
        }

        public void Dispose() {
            if (_isDisposed)
                return;

            _isDisposed = true;
            ClearBindings();

            foreach (var copy in _copies) {
                if (copy == null)
                    continue;

                if (Application.isPlaying)
                    Object.Destroy(copy);
                else
                    Object.DestroyImmediate(copy);
            }

            _copies.Clear();
            _copiesByHash.Clear();
            _unhashedCopies.Clear();
        }

        private void InitializeStateDrivers() {
            foreach (TStateKey stateKey in Enum.GetValues(typeof(TStateKey)))
                _stateDrivers[stateKey] = new StateDriver();
        }

        private void ConfigureFromBindings(IReadOnlyList<IStateBinding<TStateKey>> bindings, TStateKey initialState) {
            if (bindings == null) {
                Log.Error("Configure called with null bindings; the state machine has no states.");

                return;
            }

            if (!BindsSlot(bindings, initialState)) {
                Log.Error($"Configure called with initial state {initialState}, which no binding fills; the machine "
                          + "stays as it was.");

                return;
            }

            ClearBindings();
            var slotSeen = new HashSet<TStateKey>();

            for (var i = 0; i < bindings.Count; i++) {
                var binding = bindings[i];
                var source = binding?.Variant;

                if (source == null) {
                    Log.Warn($"State binding at index {i} has a null variant; skipping.");

                    continue;
                }

                RegisterState(source);

                if (slotSeen.Add(binding.Slot))
                    SetInitialVariant(binding.Slot, source);
            }

            ChangeState(initialState);
        }

        private static bool BindsSlot(IReadOnlyList<IStateBinding<TStateKey>> bindings, TStateKey slot) {
            for (var i = 0; i < bindings.Count; i++) {
                var binding = bindings[i];

                if (binding != null && EqualityComparer<TStateKey>.Default.Equals(binding.Slot, slot)
                    && binding.Variant != null)
                    return true;
            }

            return false;
        }

        private void ClearBindings() {
            CurrentActiveDriver?.OnBecomeInactive();
            CurrentActiveDriver = null;
            CurrentStateKey = default;

            foreach (var driver in _stateDrivers.Values) {
                if (driver.CurrentVariant != null)
                    driver.ChangeVariant(null);
            }

            _defaultVariants.Clear();
        }

        private void ThrowIfDisposed() {
            if (_isDisposed)
                throw new ObjectDisposedException(nameof(StateMachine<TContext, TStateKey>));
        }
    }
}
