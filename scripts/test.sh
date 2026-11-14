#!/bin/zsh
# Without Xcode, Swift does not find the Swift Testing macros: point to them explicitly.
cd "${0:A:h}/.." && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing "$@"
