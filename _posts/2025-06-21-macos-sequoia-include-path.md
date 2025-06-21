---
layout: post
title: "Surprising C++ failures in the macOS workers"
date: 2025-06-21 00:00:00 +0000
categories: macos,clang
tags: tunbury.org
image:
  path: /images/sequoia.jpg
  thumbnail: /images/thumbs/sequoia.jpg
---

@mseri raised [issue #175](https://github.com/ocaml/infrastructure/issues/175) as the macOS workers cannot find the most basic C++ headers. I easily eliminated [Obuilder](https://github.com/ocurrent/obuilder), as `opam install mccs.1.1+19` didn't work on the macOS workers natively.

On face value, the problem appears pretty common, and there are numerous threads on [Stack Overflow](https://stackoverflow.com) such as this [one](https://stackoverflow.com/questions/77250743/mac-xcode-g-cannot-compile-even-a-basic-c-program-issues-with-standard-libr), however, the resolutions I tried didn't work. I was reluctant to try some of the more intrusive changes like creating a symlink of every header from `/usr/include/` to `/Library/Developer/CommandLineTools/usr/include/c++/v1` as this doesn't seem to be what Apple intends.

For the record, a program such as this:

```cpp
#include <iostream>

using namespace std;

int main() {
    cout << "Hello World!" << endl;
    return 0;
}
```

Fails like this:

```sh
% c++ hello.cpp -o hello -v
Apple clang version 17.0.0 (clang-1700.0.13.3)
Target: x86_64-apple-darwin24.5.0
Thread model: posix
InstalledDir: /Library/Developer/CommandLineTools/usr/bin
 "/Library/Developer/CommandLineTools/usr/bin/clang" -cc1 -triple x86_64-apple-macosx15.0.0 -Wundef-prefix=TARGET_OS_ -Wdeprecated-objc-isa-usage -Werror=deprecated-objc-isa-usage -Werror=implicit-function-declaration -emit-obj -dumpdir hello- -disable-free -clear-ast-before-backend -disable-llvm-verifier -discard-value-names -main-file-name hello.cpp -mrelocation-model pic -pic-level 2 -mframe-pointer=all -fno-strict-return -ffp-contract=on -fno-rounding-math -funwind-tables=2 -target-sdk-version=15.4 -fvisibility-inlines-hidden-static-local-var -fdefine-target-os-macros -fno-assume-unique-vtables -fno-modulemap-allow-subdirectory-search -target-cpu penryn -tune-cpu generic -debugger-tuning=lldb -fdebug-compilation-dir=/Users/administrator/x -target-linker-version 1167.4.1 -v -fcoverage-compilation-dir=/Users/administrator/x -resource-dir /Library/Developer/CommandLineTools/usr/lib/clang/17 -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -internal-isystem /Library/Developer/CommandLineTools/usr/bin/../include/c++/v1 -internal-isystem /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/local/include -internal-isystem /Library/Developer/CommandLineTools/usr/lib/clang/17/include -internal-externc-isystem /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include -internal-externc-isystem /Library/Developer/CommandLineTools/usr/include -Wno-reorder-init-list -Wno-implicit-int-float-conversion -Wno-c99-designator -Wno-final-dtor-non-final-class -Wno-extra-semi-stmt -Wno-misleading-indentation -Wno-quoted-include-in-framework-header -Wno-implicit-fallthrough -Wno-enum-enum-conversion -Wno-enum-float-conversion -Wno-elaborated-enum-base -Wno-reserved-identifier -Wno-gnu-folding-constant -fdeprecated-macro -ferror-limit 19 -stack-protector 1 -fstack-check -mdarwin-stkchk-strong-link -fblocks -fencode-extended-block-signature -fregister-global-dtors-with-atexit -fgnuc-version=4.2.1 -fno-cxx-modules -fskip-odr-check-in-gmf -fcxx-exceptions -fexceptions -fmax-type-align=16 -fcommon -fcolor-diagnostics -clang-vendor-feature=+disableNonDependentMemberExprInCurrentInstantiation -fno-odr-hash-protocols -clang-vendor-feature=+enableAggressiveVLAFolding -clang-vendor-feature=+revert09abecef7bbf -clang-vendor-feature=+thisNoAlignAttr -clang-vendor-feature=+thisNoNullAttr -clang-vendor-feature=+disableAtImportPrivateFrameworkInImplementationError -D__GCC_HAVE_DWARF2_CFI_ASM=1 -o /var/folders/sh/9c8b7hzd2wb1g2_ky78vqw5r0000gn/T/hello-a268ab.o -x c++ hello.cpp
clang -cc1 version 17.0.0 (clang-1700.0.13.3) default target x86_64-apple-darwin24.5.0
ignoring nonexistent directory "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/local/include"
ignoring nonexistent directory "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/SubFrameworks"
ignoring nonexistent directory "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/Library/Frameworks"
#include "..." search starts here:
#include <...> search starts here:
 /Library/Developer/CommandLineTools/usr/bin/../include/c++/v1
 /Library/Developer/CommandLineTools/usr/lib/clang/17/include
 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include
 /Library/Developer/CommandLineTools/usr/include
 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks (framework directory)
End of search list.
hello.cpp:1:10: fatal error: 'iostream' file not found
    1 | #include <iostream>
      |          ^~~~~~~~~~
1 error generated.
```

That first folder looked strange: `bin/../include/c++/v1`. Really? What's in there? Not much:

```sh
% ls -l /Library/Developer/CommandLineTools/usr/bin/../include/c++/v1
total 40
-rw-r--r--  1 root  wheel  44544  7 Apr  2022 __functional_03
-rw-r--r--  1 root  wheel   6532  7 Apr  2022 __functional_base_03
-rw-r--r--  1 root  wheel   2552  7 Apr  2022 __sso_allocator
```

I definitely have `iostream` on the machine:

```sh
% ls -l /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk/usr/include/c++/v1/iostream
-rw-r--r--  1 root  wheel  1507  8 Mar 03:36 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1/iostream
-rw-r--r--  1 root  wheel  1391 13 Nov  2021 /Library/Developer/CommandLineTools/SDKs/MacOSX12.1.sdk/usr/include/c++/v1/iostream
-rw-r--r--  1 root  wheel  1583 13 Apr  2024 /Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk/usr/include/c++/v1/iostream
-rw-r--r--  1 root  wheel  1583 13 Apr  2024 /Library/Developer/CommandLineTools/SDKs/MacOSX14.sdk/usr/include/c++/v1/iostream
-rw-r--r--  1 root  wheel  1583 10 Nov  2024 /Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk/usr/include/c++/v1/iostream
-rw-r--r--  1 root  wheel  1507  8 Mar 03:36 /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/include/c++/v1/iostream
-rw-r--r--  1 root  wheel  1507  8 Mar 03:36 /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk/usr/include/c++/v1/iostream
```

I tried on my MacBook, which compiled the test program without issue. However, that was running Monterey, where the workers are running Sequoia. The _include_ paths on my laptop look much better. Where are they configured?

```sh
% c++ -v -o test test.cpp
Apple clang version 15.0.0 (clang-1500.3.9.4)
Target: x86_64-apple-darwin23.5.0
Thread model: posix
InstalledDir: /Library/Developer/CommandLineTools/usr/bin
 "/Library/Developer/CommandLineTools/usr/bin/clang" -cc1 -triple x86_64-apple-macosx14.0.0 -Wundef-prefix=TARGET_OS_ -Wdeprecated-objc-isa-usage -Werror=deprecated-objc-isa-usage -Werror=implicit-function-declaration -emit-obj -mrelax-all --mrelax-relocations -disable-free -clear-ast-before-backend -disable-llvm-verifier -discard-value-names -main-file-name test.cpp -mrelocation-model pic -pic-level 2 -mframe-pointer=all -fno-strict-return -ffp-contract=on -fno-rounding-math -funwind-tables=2 -target-sdk-version=14.4 -fvisibility-inlines-hidden-static-local-var -target-cpu penryn -tune-cpu generic -debugger-tuning=lldb -target-linker-version 1053.12 -v -fcoverage-compilation-dir=/Users/mtelvers/x -resource-dir /Library/Developer/CommandLineTools/usr/lib/clang/15.0.0 -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -I/usr/local/include -internal-isystem /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 -internal-isystem /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/local/include -internal-isystem /Library/Developer/CommandLineTools/usr/lib/clang/15.0.0/include -internal-externc-isystem /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include -internal-externc-isystem /Library/Developer/CommandLineTools/usr/include -Wno-reorder-init-list -Wno-implicit-int-float-conversion -Wno-c99-designator -Wno-final-dtor-non-final-class -Wno-extra-semi-stmt -Wno-misleading-indentation -Wno-quoted-include-in-framework-header -Wno-implicit-fallthrough -Wno-enum-enum-conversion -Wno-enum-float-conversion -Wno-elaborated-enum-base -Wno-reserved-identifier -Wno-gnu-folding-constant -fdeprecated-macro -fdebug-compilation-dir=/Users/mtelvers/x -ferror-limit 19 -stack-protector 1 -fstack-check -mdarwin-stkchk-strong-link -fblocks -fencode-extended-block-signature -fregister-global-dtors-with-atexit -fgnuc-version=4.2.1 -fno-cxx-modules -fcxx-exceptions -fexceptions -fmax-type-align=16 -fcommon -fcolor-diagnostics -clang-vendor-feature=+disableNonDependentMemberExprInCurrentInstantiation -fno-odr-hash-protocols -clang-vendor-feature=+enableAggressiveVLAFolding -clang-vendor-feature=+revert09abecef7bbf -clang-vendor-feature=+thisNoAlignAttr -clang-vendor-feature=+thisNoNullAttr -mllvm -disable-aligned-alloc-awareness=1 -D__GCC_HAVE_DWARF2_CFI_ASM=1 -o /var/folders/15/4zw4hb9s40b8cmff3z5bdszc0000gp/T/test-71e229.o -x c++ test.cpp
clang -cc1 version 15.0.0 (clang-1500.3.9.4) default target x86_64-apple-darwin23.5.0
ignoring nonexistent directory "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/local/include"
ignoring nonexistent directory "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/Library/Frameworks"
#include "..." search starts here:
#include <...> search starts here:
 /usr/local/include
 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1
 /Library/Developer/CommandLineTools/usr/lib/clang/15.0.0/include
 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include
 /Library/Developer/CommandLineTools/usr/include
 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks (framework directory)
End of search list.
 "/Library/Developer/CommandLineTools/usr/bin/ld" -demangle -lto_library /Library/Developer/CommandLineTools/usr/lib/libLTO.dylib -no_deduplicate -dynamic -arch x86_64 -platform_version macos 14.0.0 14.4 -syslibroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -o test -L/usr/local/lib /var/folders/15/4zw4hb9s40b8cmff3z5bdszc0000gp/T/test-71e229.o -lc++ -lSystem /Library/Developer/CommandLineTools/usr/lib/clang/15.0.0/lib/darwin/libclang_rt.osx.a
```

I've been meaning to upgrade my MacBook, and this looked like the perfect excuse. I updated to Sequoia and then updated the Xcode command-line tools. The test compilation worked, the paths looked good, but I had clang 1700.0.13.5, where the workers had 1700.0.13.3.

```sh
% c++ -v -o test test.cpp
Apple clang version 17.0.0 (clang-1700.0.13.5)
Target: x86_64-apple-darwin24.5.0
Thread model: posix
InstalledDir: /Library/Developer/CommandLineTools/usr/bin
```

I updated the workers to 1700.0.13.5, which didn't make any difference. The workers still had that funny `/../` path, which wasn't present anywhere else. I searched `/Library/Developer/CommandLineTools/usr/bin/../include/c++/v1 site:stackoverflow.com` and the answer is the top [match](https://stackoverflow.com/a/79606435).

> Rename or if you're confident enough, delete /Library/Developer/CommandLineTools/usr/include/c++, then clang++ will automatically search headers under /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 and find your <iostream> header. That directory is very likely an artifact of OS upgrade and by deleting it clang++ will realise that it should search in the header paths of new SDKs.

I wasn't confident, so I moved it, `sudo mv c++ ~`. With that done, the test program builds correctly! Have a read of the [answer](https://stackoverflow.com/a/79606435) on Stack Overflow.

Now, rather more cavalierly, I removed the folder on all the i7 and m1 workers:

```sh
$ for a in {01..04} ; do ssh m1-worker-$a.macos.ci.dev sudo rm -r /Library/Developer/CommandLineTools/usr/include/c++ ; done
```

