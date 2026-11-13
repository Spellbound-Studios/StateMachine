// Copyright (c) Spellbound Studios. All rights reserved.

using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine.UIElements;

namespace Spellbound.StateMachine.Editor {
    [CustomEditor(typeof(StateCatalogue))]
    internal sealed class StateCatalogueInspector : UnityEditor.Editor {
        private const string CollectLabel = "Collect the project's states";

        public override VisualElement CreateInspectorGUI() {
            var root = new VisualElement();
            InspectorElement.FillDefaultInspector(root, serializedObject, this);
            root.Add(new Button(Collect) { text = CollectLabel });

            return root;
        }

        private void Collect() {
            foreach (var selected in targets) {
                if (selected is StateCatalogue catalogue)
                    StateCatalogueCollector.Collect(catalogue);
            }

            serializedObject.Update();
        }
    }
}
