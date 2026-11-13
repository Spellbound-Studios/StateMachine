// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using Spellbound.Core.Logging;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;

namespace Spellbound.StateMachine.Editor {
    internal sealed class StateCatalogueBuildCheck : IPreprocessBuildWithReport {
        public int callbackOrder => 0;

        internal IReadOnlyList<State> UnlistedStates { get; private set; } = Array.Empty<State>();

        public void OnPreprocessBuild(BuildReport report) => UnlistedStates = WarnOfUnlistedStates();

        internal static IReadOnlyList<State> WarnOfUnlistedStates() {
            var listed = new HashSet<State>();

            foreach (var guid in AssetDatabase.FindAssets("t:" + nameof(StateCatalogue))) {
                var catalogue = AssetDatabase.LoadAssetAtPath<StateCatalogue>(AssetDatabase.GUIDToAssetPath(guid));

                if (catalogue == null)
                    continue;

                foreach (var state in catalogue.States) {
                    if (state != null)
                        listed.Add(state);
                }
            }

            var unlisted = new List<State>();

            foreach (var state in StateCatalogueCollector.FindProjectStates()) {
                if (listed.Contains(state))
                    continue;

                unlisted.Add(state);
                Log.Warn($"The state asset {AssetDatabase.GetAssetPath(state)} is in no StateCatalogue, so a registry "
                         + "filled from the catalogues cannot resolve its hash in this build.");
            }

            return unlisted;
        }
    }
}
