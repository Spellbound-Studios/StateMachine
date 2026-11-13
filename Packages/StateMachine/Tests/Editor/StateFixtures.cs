// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using Object = UnityEngine.Object;

namespace Spellbound.StateMachine.Editor.Tests {
    public sealed class StateFixtures {
        private const string ParentFolder = "Assets";
        private const string FolderName = "StateMachineTestStates";
        private const string Folder = ParentFolder + "/" + FolderName;

        private readonly List<IDisposable> _disposables = new();
        private readonly List<Object> _created = new();

        public T Create<T>(string identity) where T : State {
            if (!AssetDatabase.IsValidFolder(Folder))
                AssetDatabase.CreateFolder(ParentFolder, FolderName);

            var path = Folder + "/" + identity + ".asset";
            AssetDatabase.CreateAsset(ScriptableObject.CreateInstance<T>(), path);
            AssetDatabase.SaveAssets();
            Resources.UnloadAsset(AssetDatabase.LoadAssetAtPath<T>(path));

            return AssetDatabase.LoadAssetAtPath<T>(path);
        }

        public CountingConfiguration Configuration(CountingSlot initialState, params CountingBinding[] bindings) =>
            DestroyAfterTest(CountingConfiguration.Create(initialState, bindings));

        public T DisposeAfterTest<T>(T disposable) where T : IDisposable {
            _disposables.Add(disposable);

            return disposable;
        }

        public T DestroyAfterTest<T>(T created) where T : Object {
            _created.Add(created);

            return created;
        }

        public void DestroyAll() {
            foreach (var disposable in _disposables)
                disposable?.Dispose();

            _disposables.Clear();

            foreach (var created in _created) {
                if (created != null)
                    Object.DestroyImmediate(created);
            }

            _created.Clear();

            if (AssetDatabase.IsValidFolder(Folder))
                AssetDatabase.DeleteAsset(Folder);
        }
    }
}
