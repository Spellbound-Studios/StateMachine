// Copyright (c) Spellbound Studios. All rights reserved.

using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using NUnit.Framework;
using UnityEditor;
using UnityEngine;
using UnityEngine.TestTools;

namespace Spellbound.StateMachine.Editor.Tests {
    public class StateRegistryTests {
        private const string ResourcesParent = "Assets/StateMachineResourcesFixture";
        private const string ResourcesFolder = ResourcesParent + "/Resources";
        private const string StatesFolder = ResourcesFolder + "/States";
        private const string UnlistedName = "StateMachineUnlistedState";
        private const uint UnknownHash = 12345u;

        private StateFixtures _fixtures;

        [SetUp]
        public void SetUp() => _fixtures = new StateFixtures();

        [TearDown]
        public void TearDown() {
            StateMachineKit.Registry.Clear();
            _fixtures.DestroyAll();

            if (AssetDatabase.IsValidFolder(ResourcesParent))
                AssetDatabase.DeleteAsset(ResourcesParent);
        }

        [Test]
        public void StateRegistry_CustomImplementation() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var handBuilt = new State[] { first, second };
            var unlisted = CreateResourcesState();

            StateMachineKit.UseStates(handBuilt);

            Assert.IsNotNull(Resources.Load<State>("States/" + UnlistedName));
            Assert.AreNotEqual(0u, unlisted.Hash);
            Assert.IsFalse(StateMachineKit.Registry.Contains(unlisted.Hash));
            Assert.AreEqual(2, StateMachineKit.Registry.Count);
            Assert.AreSame(first, StateMachineKit.Registry.Get(first.Hash));
            Assert.IsTrue(StateMachineKit.Registry.TryGet(second.Hash, out var found));
            Assert.AreSame(second, found);

            var replacement = _fixtures.Create<ThirdCountingState>("third");
            StateMachineKit.UseStates(new State[] { replacement });

            Assert.AreEqual(1, StateMachineKit.Registry.Count);
            Assert.IsFalse(StateMachineKit.Registry.Contains(first.Hash));
            Assert.IsFalse(StateMachineKit.Registry.Contains(unlisted.Hash));
            Assert.IsTrue(StateMachineKit.Registry.Contains(replacement.Hash));
        }

        [Test]
        public void StateRegistry_ReadsFromCatalogue() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var catalogue = _fixtures.DestroyAfterTest(ScriptableObject.CreateInstance<StateCatalogue>());
            var serializedCatalogue = new SerializedObject(catalogue);
            var list = serializedCatalogue.FindProperty("states");
            list.arraySize = 1;
            list.GetArrayElementAtIndex(0).objectReferenceValue = first;
            serializedCatalogue.ApplyModifiedPropertiesWithoutUndo();

            var registry = new StateRegistry(catalogue);

            Assert.AreEqual(1, registry.Count);
            Assert.AreSame(first, registry.Get(first.Hash));
        }

        [Test]
        public void StateRegistry_RoundTripsThroughRegistryPacker() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var second = _fixtures.Create<SecondCountingState>("second");
            var registry = new StateRegistry(new State[] { first, second });
            var bytes = new byte[8];

            var writer = new Span<byte>(bytes);
            StateRegistry.WriteState(ref writer, second);
            StateRegistry.WriteState(ref writer, null);
            var reader = new ReadOnlySpan<byte>(bytes);

            Assert.AreEqual(0, writer.Length);
            Assert.AreSame(second, registry.ReadState(ref reader));
            Assert.IsNull(registry.ReadState(ref reader));
            Assert.AreEqual(0, reader.Length);
        }

        [Test]
        public void StateRegistry_GetOfAnUnknownHash_LogsAnErrorAndReturnsNull() {
            var registry = new StateRegistry(new State[] { _fixtures.Create<FirstCountingState>("first") });

            LogAssert.Expect(LogType.Error, new Regex("no entry for hash " + UnknownHash));

            Assert.IsNull(registry.Get(UnknownHash));
        }

        [Test]
        public void StateRegistry_TryGetOfAnUnknownHash_IsSilent() {
            var registry = new StateRegistry(new State[] { _fixtures.Create<FirstCountingState>("first") });

            var found = registry.TryGet(UnknownHash, out var state);

            Assert.IsFalse(found);
            Assert.IsNull(state);
            LogAssert.NoUnexpectedReceived();
        }

        [Test]
        public void StateRegistry_UseOfNothing_LogsAnErrorAndKeepsItsStates() {
            var first = _fixtures.Create<FirstCountingState>("first");
            var registry = new StateRegistry(new State[] { first });

            LogAssert.Expect(LogType.Error, new Regex("was given no catalogue"));
            registry.Use((StateCatalogue)null);
            LogAssert.Expect(LogType.Error, new Regex("was given no list of states"));
            registry.Use((IReadOnlyList<State>)null);

            Assert.AreEqual(1, registry.Count);
            Assert.AreSame(first, registry.Get(first.Hash));
        }

        private static State CreateResourcesState() {
            AssetDatabase.CreateFolder("Assets", "StateMachineResourcesFixture");
            AssetDatabase.CreateFolder(ResourcesParent, "Resources");
            AssetDatabase.CreateFolder(ResourcesFolder, "States");
            var path = StatesFolder + "/" + UnlistedName + ".asset";
            AssetDatabase.CreateAsset(ScriptableObject.CreateInstance<ThirdCountingState>(), path);
            AssetDatabase.SaveAssets();
            Resources.UnloadAsset(AssetDatabase.LoadAssetAtPath<State>(path));

            return AssetDatabase.LoadAssetAtPath<State>(path);
        }
    }
}
