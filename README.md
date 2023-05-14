# engine_io_dart

A from-scratch implementation of the engine.io server-client communication
protocol in Dart.

## Features

- **Documented**: 100% of the public API is documented. When unsure about using
  a particular feature of the package, you can always rely on documentation
  comments to help explain it.
- **Tested**: The codebases feature over 100 tests in total, testing that each
  piece of functionality in the packages works as intended.
- **Strict**: The packages seek to provide the highest degree of safety and data
  correctness possible in accordance with the protocol. Invalid, malformed or
  otherwise unacceptable requests and responses are rejected immediately, a
  detailed exception is raised, and the connection is severed. In total, there
  are over 40+ different, descriptive error messages that can be thrown in
  various circumstances.
- **High canonicalisation and immutability**: Thanks to this, there is less
  memory usage, improved code safety and cleanliness, and, ultimately, higher
  performance.
- **High code quality**: All code is written in conformity with the
  [words](https://github.com/wordcollector/words) lint ruleset, which sees to
  eradicate a multitude of potential problems before the code ever runs.

## Implementation

- **Stream-based event system**: Events are emitted on streams exposed by the
  library, providing full execution flow transparency.
