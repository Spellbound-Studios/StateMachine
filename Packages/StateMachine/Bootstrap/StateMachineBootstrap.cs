// Copyright (c) Spellbound Studios. All rights reserved.

#if !SPELLBOUND_CORE
using System.IO;
using UnityEditor;
using UnityEditor.PackageManager;
using UnityEngine;
using UnityEngine.UIElements;
using PackageInfo = UnityEditor.PackageManager.PackageInfo;

namespace Spellbound.StateMachine.Bootstrap {
    public sealed class StateMachineBootstrap : EditorWindow {
        private const string WindowKey = "Spellbound.Bootstrap.WindowShown";
        private const string LineKey = "Spellbound.Bootstrap.StateMachine";
        private const string AddressFile = "FoundationAddress.txt";
        private const string Foundation = "com.spellboundstudios.core";

        [InitializeOnLoadMethod]
        private static void Offer() {
            var address = Address();

            if (!SessionState.GetBool(LineKey, false)) {
                SessionState.SetBool(LineKey, true);
                Debug.LogWarning("StateMachine needs " + Foundation + ". Install it from the Package Manager with "
                                 + "Install package from git URL: " + address);
            }

            if (SessionState.GetBool(WindowKey, false)) {
                return;
            }

            SessionState.SetBool(WindowKey, true);
            EditorApplication.delayCall += () => {
                var window = CreateInstance<StateMachineBootstrap>();
                window.titleContent = new GUIContent(Foundation);
                window.ShowUtility();
            };
        }

        private static string Address() {
            var package = PackageInfo.FindForAssembly(typeof(StateMachineBootstrap).Assembly);
            var path = package == null ? null : Path.Combine(package.resolvedPath, "Bootstrap", AddressFile);
            var line = path != null && File.Exists(path) ? FirstLine(path) : null;
            return string.IsNullOrEmpty(line) ? Foundation : line;
        }

        private static string FirstLine(string path) {
            foreach (var line in File.ReadAllLines(path)) {
                if (line.Trim().Length > 0) {
                    return line.Trim();
                }
            }

            return null;
        }

        private void CreateGUI() {
            var address = Address();
            var message = new Label("StateMachine needs " + Foundation + ", which this project does not hold yet.");
            message.style.whiteSpace = WhiteSpace.Normal;
            rootVisualElement.Add(message);
            var field = new TextField { value = address, isReadOnly = true };
            rootVisualElement.Add(field);
            rootVisualElement.Add(new Button(() => Client.Add(address)) { text = "Install " + Foundation });
        }
    }
}
#endif
