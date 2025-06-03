# Application Layer

The `app` directory contains high-level application implementations that use the MFS engine components. This is where the integration of various subsystems happens to create complete applications.

## Contents

- **demo_app.zig** - A demonstration application that showcases the engine's cross-platform graphics capabilities, including backend switching, resource management, and rendering.

## Purpose

Code in this directory should:

1. Provide complete, working applications built on the MFS engine
2. Demonstrate proper use of engine subsystems
3. Serve as integration examples for engine features

## Usage

Applications in this directory generally follow this pattern:

```zig
// Initialize the application
var app = try DemoApp.init(allocator);
defer app.deinit();

// Run the main loop
try app.run();
```

When creating new applications:

1. Use the engine's platform abstractions rather than direct OS calls
2. Handle errors and resources properly
3. Follow the initialization/run/deinit lifecycle pattern
4. Add clear documentation for users

Applications should focus on high-level logic while delegating rendering, physics, and other specialized tasks to the appropriate engine subsystems.