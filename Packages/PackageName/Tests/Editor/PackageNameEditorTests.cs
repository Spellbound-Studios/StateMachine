// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;

namespace Spellbound.PackageName.Editor.Tests {
    public class PackageNameEditorTests {
        [Test]
        public void FrontDoorTypeExists() {
            Assert.IsNotNull(typeof(PackageNameKit));
        }
    }
}
