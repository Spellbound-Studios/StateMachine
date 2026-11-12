// Copyright (c) Spellbound Studios. All rights reserved.

using NUnit.Framework;

namespace Spellbound.PackageName.Tests {
    public class PackageNameTests {
        [Test]
        public void FrontDoorTypeExists() {
            Assert.IsNotNull(typeof(PackageNameKit));
        }
    }
}
