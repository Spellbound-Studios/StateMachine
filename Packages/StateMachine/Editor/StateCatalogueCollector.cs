// Copyright (c) Spellbound Studios. All rights reserved.

using System.Collections.Generic;
using UnityEditor;

namespace Spellbound.StateMachine.Editor {
    public static class StateCatalogueCollector {
        private const string StatesProperty = "states";

        internal static IReadOnlyList<State> FindProjectStates() {
            var found = new List<State>();
            var seen = new HashSet<State>();

            foreach (var guid in AssetDatabase.FindAssets("t:" + nameof(State))) {
                var path = AssetDatabase.GUIDToAssetPath(guid);

                foreach (var asset in AssetDatabase.LoadAllAssetsAtPath(path)) {
                    if (asset is State state && seen.Add(state))
                        found.Add(state);
                }
            }

            found.Sort((first, second) => string.CompareOrdinal(AssetDatabase.GetAssetPath(first) + first.name,
                AssetDatabase.GetAssetPath(second) + second.name));

            return found;
        }

        public static int Collect(StateCatalogue catalogue) {
            if (catalogue == null)
                return 0;

            var states = FindProjectStates();
            var serializedCatalogue = new SerializedObject(catalogue);
            var list = serializedCatalogue.FindProperty(StatesProperty);
            list.arraySize = states.Count;

            for (var i = 0; i < states.Count; i++)
                list.GetArrayElementAtIndex(i).objectReferenceValue = states[i];

            serializedCatalogue.ApplyModifiedProperties();
            EditorUtility.SetDirty(catalogue);

            return states.Count;
        }
    }
}
