// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;
using UnityEditor;
using UnityEngine;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateCatalogueCollectorTests {
        private const string Folder = "Assets/StateMachineCollectorFixtures";

        private StateFixtures _fixtures;

        [SetUp]
        public void SetUp() {
            _fixtures = new StateFixtures();

            if (!AssetDatabase.IsValidFolder(Folder))
                AssetDatabase.CreateFolder("Assets", "StateMachineCollectorFixtures");
        }

        [TearDown]
        public void TearDown() {
            _fixtures.DestroyAll();
            AssetDatabase.DeleteAsset(Folder);
        }

        [Test]
        public void StateCatalogueCollector_FillsCatalogueFromProjectStates() {
            var first = ScriptableObject.CreateInstance<FirstCountingState>();
            AssetDatabase.CreateAsset(first, Folder + "/First.asset");
            var second = ScriptableObject.CreateInstance<SecondCountingState>();
            AssetDatabase.CreateAsset(second, Folder + "/Second.asset");
            var catalogue = ScriptableObject.CreateInstance<StateCatalogue>();
            AssetDatabase.CreateAsset(catalogue, Folder + "/Catalogue.asset");
            AssetDatabase.SaveAssets();

            var collected = StateCatalogueCollector.Collect(catalogue);

            CollectionAssert.Contains(catalogue.States, first);
            CollectionAssert.Contains(catalogue.States, second);
            Assert.AreEqual(collected, catalogue.States.Count);
            CollectionAssert.AllItemsAreUnique(catalogue.States);
        }

        [Test]
        public void StateCatalogueCollector_CollectedHashesComeFromAssetGuids() {
            var first = ScriptableObject.CreateInstance<FirstCountingState>();
            var path = Folder + "/First.asset";
            AssetDatabase.CreateAsset(first, path);
            AssetDatabase.SaveAssets();
            Resources.UnloadAsset(first);
            var loaded = AssetDatabase.LoadAssetAtPath<FirstCountingState>(path);
            var catalogue = _fixtures.DestroyAfterTest(ScriptableObject.CreateInstance<StateCatalogue>());

            StateCatalogueCollector.Collect(catalogue);
            var registry = new StateRegistry(catalogue);

            Assert.AreEqual(AssetDatabase.AssetPathToGUID(path), loaded.Guid);
            Assert.AreNotEqual(0u, loaded.Hash);
            Assert.AreSame(loaded, registry.Get(loaded.Hash));
        }

        [Test]
        public void StateCatalogueBuildCheck_BeforeABuild_RecordsTheStatesNoCatalogueLists() {
            var unlisted = ScriptableObject.CreateInstance<SecondCountingState>();
            AssetDatabase.CreateAsset(unlisted, Folder + "/Unlisted.asset");
            AssetDatabase.SaveAssets();
            var check = new StateCatalogueBuildCheck();

            check.OnPreprocessBuild(null);

            CollectionAssert.Contains(check.UnlistedStates, unlisted);
        }

        [Test]
        public void StateCatalogueBuildCheck_ReturnsTheStatesNoCatalogueLists_AndWritesNothing() {
            var listed = ScriptableObject.CreateInstance<FirstCountingState>();
            AssetDatabase.CreateAsset(listed, Folder + "/Listed.asset");
            var unlisted = ScriptableObject.CreateInstance<SecondCountingState>();
            AssetDatabase.CreateAsset(unlisted, Folder + "/Unlisted.asset");
            var catalogue = ScriptableObject.CreateInstance<StateCatalogue>();
            AssetDatabase.CreateAsset(catalogue, Folder + "/Catalogue.asset");
            var serializedCatalogue = new SerializedObject(catalogue);
            var list = serializedCatalogue.FindProperty("states");
            list.arraySize = 1;
            list.GetArrayElementAtIndex(0).objectReferenceValue = listed;
            serializedCatalogue.ApplyModifiedPropertiesWithoutUndo();
            AssetDatabase.SaveAssets();

            var found = StateCatalogueBuildCheck.WarnOfUnlistedStates();

            CollectionAssert.Contains(found, unlisted);
            CollectionAssert.DoesNotContain(found, listed);
            Assert.AreEqual(1, catalogue.States.Count);
            Assert.AreSame(listed, catalogue.States[0]);
            Assert.IsFalse(EditorUtility.IsDirty(catalogue));
        }
    }
}
