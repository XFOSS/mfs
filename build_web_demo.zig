//! Build script for MFS Engine WebAssembly Cube Demo
//! Compiles the spinning cube demo to WebAssembly for web documentation

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_model = .{ .explicit = &std.Target.wasm.cpu.baseline },
            .abi = .musl,
        },
    });

    const optimize = b.standardOptimizeOption(.{});
    const wasm_allocator = b.option(bool, "wasm-allocator", "Use WASM allocator") orelse true;

    // Create the WASM module
    const wasm_module = b.addSharedLibrary(.{
        .name = "mfs-cube-demo",
        .root_source_file = .{ .path = "src/web_cube_demo.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Set WASM-specific options
    wasm_module.rdynamic = true;
    wasm_module.import_memory = true;
    wasm_module.initial_memory = 65536;
    wasm_module.max_memory = 65536;
    wasm_module.stack_pointer_offsets = .{ .stack_pointer = 1024 };

    // Add WASM-specific defines
    wasm_module.addCSourceFile(.{
        .file = .{ .path = "src/web_cube_demo.zig" },
        .flags = &.{},
    });

    // Set compilation flags for WASM
    wasm_module.addCFlags(&.{
        "-DWASM=1",
        "-D__wasm__=1",
        "-fno-stack-protector",
        "-fno-builtin",
    });

    // Install the WASM file
    b.installArtifact(wasm_module);

    // Create JavaScript glue code
    const js_glue = b.addWriteFiles();
    const js_content = 
        \\// MFS Engine WebAssembly Cube Demo - JavaScript Glue Code
        \\// This file provides the JavaScript interface for the WASM module
        \\
        \\let Module = {};
        \\let canvas = null;
        \\let gl = null;
        \\let animationId = null;
        \\let lastTime = 0;
        \\
        \\// WebGL function pointers for WASM
        \\let glCreateShader = null;
        \\let glShaderSource = null;
        \\let glCompileShader = null;
        \\let glGetShaderiv = null;
        \\let glCreateProgram = null;
        \\let glAttachShader = null;
        \\let glLinkProgram = null;
        \\let glGetProgramiv = null;
        \\let glUseProgram = null;
        \\let glGetAttribLocation = null;
        \\let glGetUniformLocation = null;
        \\let glGenBuffers = null;
        \\let glBindBuffer = null;
        \\let glBufferData = null;
        \\let glVertexAttribPointer = null;
        \\let glEnableVertexAttribArray = null;
        \\let glClear = null;
        \\let glClearColor = null;
        \\let glViewport = null;
        \\let glDrawArrays = null;
        \\let glUniformMatrix4fv = null;
        \\
        \\// Initialize WebGL context and set up function pointers
        \\function initWebGL(webglCanvas) {
        \\    canvas = webglCanvas;
        \\    gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
        \\    
        \\    if (!gl) {
        \\        console.error('WebGL not supported');
        \\        return false;
        \\    }
        \\
        \\    // Set up WebGL function pointers
        \\    glCreateShader = gl.createShader.bind(gl);
        \\    glShaderSource = gl.shaderSource.bind(gl);
        \\    glCompileShader = gl.compileShader.bind(gl);
        \\    glGetShaderiv = gl.getShaderParameter.bind(gl);
        \\    glCreateProgram = gl.createProgram.bind(gl);
        \\    glAttachShader = gl.attachShader.bind(gl);
        \\    glLinkProgram = gl.linkProgram.bind(gl);
        \\    glGetProgramiv = gl.getProgramParameter.bind(gl);
        \\    glUseProgram = gl.useProgram.bind(gl);
        \\    glGetAttribLocation = gl.getAttribLocation.bind(gl);
        \\    glGetUniformLocation = gl.getUniformLocation.bind(gl);
        \\    glGenBuffers = gl.genBuffers.bind(gl);
        \\    glBindBuffer = gl.bindBuffer.bind(gl);
        \\    glBufferData = gl.bufferData.bind(gl);
        \\    glVertexAttribPointer = gl.vertexAttribPointer.bind(gl);
        \\    glEnableVertexAttribArray = gl.enableVertexAttribArray.bind(gl);
        \\    glClear = gl.clear.bind(gl);
        \\    glClearColor = gl.clearColor.bind(gl);
        \\    glViewport = gl.viewport.bind(gl);
        \\    glDrawArrays = gl.drawArrays.bind(gl);
        \\    glUniformMatrix4fv = gl.uniformMatrix4fv.bind(gl);
        \\
        \\    return true;
        \\}
        \\
        \\// Initialize the WASM module
        \\function initWASM() {
        \\    return new Promise((resolve, reject) => {
        \\        Module = {
        \\            canvas: canvas,
        \\            print: function(text) {
        \\                console.log('WASM:', text);
        \\            },
        \\            printErr: function(text) {
        \\                console.error('WASM Error:', text);
        \\            },
        \\            onRuntimeInitialized: function() {
        \\                console.log('WASM Runtime initialized');
        \\                
        \\                // Initialize WebGL in WASM
        \\                const result = Module._initialize_webgl(gl);
        \\                if (result === 0) {
        \\                    console.log('WebGL initialized successfully');
        \\                    resolve();
        \\                } else {
        \\                    reject(new Error('WebGL initialization failed: ' + result));
        \\                }
        \\            },
        \\            locateFile: function(path, prefix) {
        \\                if (path.endsWith('.wasm')) {
        \\                    return 'mfs-cube-demo.wasm';
        \\                }
        \\                return prefix + path;
        \\            }
        \\        };
        \\
        \\        // Load the WASM module
        \\        const script = document.createElement('script');
        \\        script.src = 'mfs-cube-demo.js';
        \\        script.onload = () => {
        \\            // Module will be initialized via onRuntimeInitialized
        \\        };
        \\        script.onerror = () => {
        \\            reject(new Error('Failed to load WASM module'));
        \\        };
        \\        document.head.appendChild(script);
        \\    });
        \\}
        \\
        \\// Start the animation loop
        \\function startAnimation() {
        \\    if (animationId) return;
        \\
        \\    function animate(currentTime) {
        \\        if (!lastTime) lastTime = currentTime;
        \\        const deltaTime = (currentTime - lastTime) / 1000.0;
        \\        lastTime = currentTime;
        \\
        \\        if (Module._render_cube) {
        \\            Module._render_cube(deltaTime);
        \\        }
        \\
        \\        animationId = requestAnimationFrame(animate);
        \\    }
        \\
        \\    Module._start_demo();
        \\    animate(0);
        \\}
        \\
        \\// Stop the animation
        \\function stopAnimation() {
        \\    if (animationId) {
        \\        cancelAnimationFrame(animationId);
        \\        animationId = null;
        \\    }
        \\    Module._stop_demo();
        \\}
        \\
        \\// Reset the demo
        \\function resetDemo() {
        \\    Module._reset_demo();
        \\}
        \\
        \\// Set canvas size
        \\function setCanvasSize(width, height) {
        \\    if (canvas) {
        \\        canvas.width = width;
        \\        canvas.height = height;
        \\        Module._set_canvas_size(width, height);
        \\    }
        \\}
        \\
        \\// Export functions for external use
        \\window.MFSCubeDemo = {
        \\    initWebGL: initWebGL,
        \\    initWASM: initWASM,
        \\    startAnimation: startAnimation,
        \\    stopAnimation: stopAnimation,
        \\    resetDemo: resetDemo,
        \\    setCanvasSize: setCanvasSize
        \\};
    ;

    js_glue.add("mfs-cube-demo.js", js_content);

    // Install the JavaScript file
    b.installFile(js_glue.getWrittenFiles().get("mfs-cube-demo.js"), "mfs-cube-demo.js");

    // Create a simple HTML demo page
    const html_content = 
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>MFS Engine - Spinning Cube Demo</title>
        \\    <style>
        \\        body {
        \\            margin: 0;
        \\            padding: 20px;
        \\            background-color: #1a1a1a;
        \\            color: #ffffff;
        \\            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        \\            display: flex;
        \\            flex-direction: column;
        \\            align-items: center;
        \\        }
        \\
        \\        .header {
        \\            text-align: center;
        \\            margin-bottom: 20px;
        \\        }
        \\
        \\        .header h1 {
        \\            margin: 0;
        \\            font-size: 2.5em;
        \\            background: linear-gradient(45deg, #ff6b6b, #4ecdc4, #45b7d1);
        \\            -webkit-background-clip: text;
        \\            -webkit-text-fill-color: transparent;
        \\            background-clip: text;
        \\        }
        \\
        \\        .canvas-container {
        \\            position: relative;
        \\            border: 2px solid #333;
        \\            border-radius: 8px;
        \\            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
        \\            overflow: hidden;
        \\        }
        \\
        \\        #canvas {
        \\            display: block;
        \\            background-color: #000000;
        \\        }
        \\
        \\        .controls {
        \\            margin-top: 20px;
        \\            display: flex;
        \\            gap: 10px;
        \\            flex-wrap: wrap;
        \\            justify-content: center;
        \\        }
        \\
        \\        .btn {
        \\            padding: 10px 20px;
        \\            background: linear-gradient(45deg, #4ecdc4, #45b7d1);
        \\            color: white;
        \\            border: none;
        \\            border-radius: 5px;
        \\            cursor: pointer;
        \\            font-size: 1em;
        \\            transition: transform 0.2s ease, box-shadow 0.2s ease;
        \\        }
        \\
        \\        .btn:hover {
        \\            transform: translateY(-2px);
        \\            box-shadow: 0 4px 12px rgba(78, 205, 196, 0.3);
        \\        }
        \\
        \\        .btn:disabled {
        \\            background: #666;
        \\            cursor: not-allowed;
        \\            transform: none;
        \\            box-shadow: none;
        \\        }
        \\
        \\        .loading {
        \\            position: absolute;
        \\            top: 50%;
        \\            left: 50%;
        \\            transform: translate(-50%, -50%);
        \\            color: #ffffff;
        \\            font-size: 1.2em;
        \\        }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="header">
        \\        <h1>MFS Engine</h1>
        \\        <p>WebAssembly Spinning Cube Demo</p>
        \\    </div>
        \\
        \\    <div class="canvas-container">
        \\        <canvas id="canvas" width="800" height="600"></canvas>
        \\        <div id="loading" class="loading">Loading...</div>
        \\    </div>
        \\
        \\    <div class="controls">
        \\        <button id="startBtn" class="btn" disabled>Start</button>
        \\        <button id="stopBtn" class="btn" disabled>Stop</button>
        \\        <button id="resetBtn" class="btn" disabled>Reset</button>
        \\    </div>
        \\
        \\    <script src="mfs-cube-demo.js"></script>
        \\    <script>
        \\        const canvas = document.getElementById('canvas');
        \\        const loading = document.getElementById('loading');
        \\        const startBtn = document.getElementById('startBtn');
        \\        const stopBtn = document.getElementById('stopBtn');
        \\        const resetBtn = document.getElementById('resetBtn');
        \\
        \\        // Initialize the demo
        \\        async function initDemo() {
        \\            try {
        \\                // Initialize WebGL
        \\                if (!MFSCubeDemo.initWebGL(canvas)) {
        \\                    throw new Error('WebGL not supported');
        \\                }
        \\
        \\                // Initialize WASM
        \\                await MFSCubeDemo.initWASM();
        \\
        \\                // Enable controls
        \\                startBtn.disabled = false;
        \\                resetBtn.disabled = false;
        \\                loading.style.display = 'none';
        \\
        \\                console.log('Demo initialized successfully');
        \\            } catch (error) {
        \\                console.error('Failed to initialize demo:', error);
        \\                loading.textContent = 'Error: ' + error.message;
        \\            }
        \\        }
        \\
        \\        // Button event handlers
        \\        startBtn.addEventListener('click', () => {
        \\            MFSCubeDemo.startAnimation();
        \\            startBtn.disabled = true;
        \\            stopBtn.disabled = false;
        \\        });
        \\
        \\        stopBtn.addEventListener('click', () => {
        \\            MFSCubeDemo.stopAnimation();
        \\            startBtn.disabled = false;
        \\            stopBtn.disabled = true;
        \\        });
        \\
        \\        resetBtn.addEventListener('click', () => {
        \\            MFSCubeDemo.resetDemo();
        \\        });
        \\
        \\        // Handle window resize
        \\        function resizeCanvas() {
        \\            const container = canvas.parentElement;
        \\            const containerWidth = container.clientWidth;
        \\            const containerHeight = Math.min(container.clientHeight, window.innerHeight * 0.6);
        \\
        \\            canvas.width = containerWidth;
        \\            canvas.height = containerHeight;
        \\            MFSCubeDemo.setCanvasSize(containerWidth, containerHeight);
        \\        }
        \\
        \\        window.addEventListener('resize', resizeCanvas);
        \\
        \\        // Initialize the demo when the page loads
        \\        window.addEventListener('load', initDemo);
        \\    </script>
        \\</body>
        \\</html>
    ;

    js_glue.add("demo.html", html_content);
    b.installFile(js_glue.getWrittenFiles().get("demo.html"), "demo.html");

    // Add build step
    b.default_step.dependOn(&wasm_module.step);
    b.default_step.dependOn(&js_glue.step);
}