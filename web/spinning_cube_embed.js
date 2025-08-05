// MFS Engine Spinning Cube Demo - Embeddable Version
(function() {
    'use strict';

    // Create the demo container
    function createDemoContainer() {
        const container = document.createElement('div');
        container.className = 'mfs-demo-container';
        container.style.cssText = `
            width: 100%;
            max-width: 800px;
            margin: 20px auto;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        `;

        container.innerHTML = `
            <div class="mfs-demo-header" style="
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 15px 20px;
                text-align: center;
            ">
                <h3 style="margin: 0; font-size: 1.2rem;">🎮 MFS Engine Spinning Cube Demo</h3>
                <p style="margin: 5px 0 0 0; opacity: 0.9; font-size: 0.9rem;">Real-time 3D rendering powered by WebAssembly</p>
            </div>

            <div class="mfs-canvas-container" style="
                position: relative;
                background: #000;
                width: 100%;
                height: 400px;
            ">
                <canvas id="mfs-demo-canvas" width="800" height="400" style="
                    display: block;
                    width: 100%;
                    height: 100%;
                    cursor: pointer;
                "></canvas>
                <div id="mfs-loading-overlay" class="mfs-loading-overlay" style="
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background: rgba(0, 0, 0, 0.8);
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    color: white;
                    transition: opacity 0.3s ease;
                ">
                    <div class="mfs-spinner" style="
                        width: 40px;
                        height: 40px;
                        border: 3px solid #333;
                        border-top: 3px solid #667eea;
                        border-radius: 50%;
                        animation: mfs-spin 1s linear infinite;
                        margin-bottom: 15px;
                    "></div>
                    <div>Loading MFS Engine...</div>
                </div>
            </div>

            <div class="mfs-demo-controls" style="
                background: #f8f9fa;
                padding: 15px 20px;
                display: flex;
                justify-content: space-between;
                align-items: center;
                flex-wrap: wrap;
                gap: 10px;
            ">
                <div class="mfs-demo-stats" style="display: flex; gap: 20px; font-size: 0.9rem;">
                    <div class="mfs-stat-item" style="display: flex; flex-direction: column; align-items: center;">
                        <div class="mfs-stat-label" style="color: #666; font-size: 0.8rem;">FPS</div>
                        <div class="mfs-stat-value" id="mfs-fps-display" style="font-weight: 600; color: #333;">0</div>
                    </div>
                    <div class="mfs-stat-item" style="display: flex; flex-direction: column; align-items: center;">
                        <div class="mfs-stat-label" style="color: #666; font-size: 0.8rem;">Memory</div>
                        <div class="mfs-stat-value" id="mfs-memory-display" style="font-weight: 600; color: #333;">0 MB</div>
                    </div>
                    <div class="mfs-stat-item" style="display: flex; flex-direction: column; align-items: center;">
                        <div class="mfs-stat-label" style="color: #666; font-size: 0.8rem;">Status</div>
                        <div class="mfs-stat-value" id="mfs-status-display" style="font-weight: 600; color: #333;">Loading</div>
                    </div>
                </div>

                <div class="mfs-demo-buttons" style="display: flex; gap: 10px;">
                    <button id="mfs-start-btn" class="mfs-demo-btn" disabled style="
                        background: #667eea;
                        color: white;
                        border: none;
                        padding: 8px 16px;
                        border-radius: 5px;
                        cursor: pointer;
                        font-size: 0.9rem;
                        transition: background 0.2s ease;
                    ">Start</button>
                    <button id="mfs-pause-btn" class="mfs-demo-btn" disabled style="
                        background: #667eea;
                        color: white;
                        border: none;
                        padding: 8px 16px;
                        border-radius: 5px;
                        cursor: pointer;
                        font-size: 0.9rem;
                        transition: background 0.2s ease;
                    ">Pause</button>
                    <button id="mfs-reset-btn" class="mfs-demo-btn" disabled style="
                        background: #667eea;
                        color: white;
                        border: none;
                        padding: 8px 16px;
                        border-radius: 5px;
                        cursor: pointer;
                        font-size: 0.9rem;
                        transition: background 0.2s ease;
                    ">Reset</button>
                </div>
            </div>

            <div id="mfs-error-message" class="mfs-error-message" style="
                background: #ff6b6b;
                color: white;
                padding: 10px 20px;
                margin: 10px 0;
                border-radius: 5px;
                display: none;
            "></div>
        `;

        // Add CSS animation
        const style = document.createElement('style');
        style.textContent = `
            @keyframes mfs-spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
            .mfs-demo-btn:hover {
                background: #5a6fd8 !important;
            }
            .mfs-demo-btn:disabled {
                background: #ccc !important;
                cursor: not-allowed !important;
            }
            .mfs-loading-overlay.mfs-hidden {
                opacity: 0;
                pointer-events: none;
            }
            @media (max-width: 768px) {
                .mfs-demo-controls {
                    flex-direction: column !important;
                    align-items: stretch !important;
                }
                .mfs-demo-stats {
                    justify-content: space-around !important;
                }
                .mfs-demo-buttons {
                    justify-content: center !important;
                }
            }
        `;
        document.head.appendChild(style);

        return container;
    }

    // Demo state
    let engineRunning = false;
    let engineInitialized = false;
    let Module = {};

    // WebGL fallback demo
    function initializeWebGLDemo(canvas) {
        const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
        if (!gl) {
            showError('WebGL not supported');
            return;
        }

        // Simple spinning cube with WebGL
        const vertexShaderSource = `
            attribute vec3 position;
            attribute vec3 color;
            uniform mat4 modelViewMatrix;
            uniform mat4 projectionMatrix;
            varying vec3 vColor;
            void main() {
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
                vColor = color;
            }
        `;

        const fragmentShaderSource = `
            precision mediump float;
            varying vec3 vColor;
            void main() {
                gl_FragColor = vec4(vColor, 1.0);
            }
        `;

        // Create shaders
        const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertexShaderSource);
        const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fragmentShaderSource);
        const program = createProgram(gl, vertexShader, fragmentShader);

        // Cube vertices
        const vertices = new Float32Array([
            // Front face
            -1, -1,  1,  1, 0, 0,
             1, -1,  1,  0, 1, 0,
             1,  1,  1,  0, 0, 1,
            -1,  1,  1,  1, 1, 0,
            // Back face
            -1, -1, -1,  1, 0, 1,
             1, -1, -1,  0, 1, 1,
             1,  1, -1,  1, 1, 1,
            -1,  1, -1,  0, 0, 0,
        ]);

        const indices = new Uint16Array([
            0, 1, 2,  0, 2, 3,  // Front
            1, 5, 6,  1, 6, 2,  // Right
            5, 4, 7,  5, 7, 6,  // Back
            4, 0, 3,  4, 3, 7,  // Left
            3, 2, 6,  3, 6, 7,  // Top
            4, 5, 1,  4, 1, 0   // Bottom
        ]);

        // Create buffers
        const vertexBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

        const indexBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);

        // Set up attributes
        const positionLocation = gl.getAttribLocation(program, 'position');
        const colorLocation = gl.getAttribLocation(program, 'color');

        gl.enableVertexAttribArray(positionLocation);
        gl.vertexAttribPointer(positionLocation, 3, gl.FLOAT, false, 24, 0);

        gl.enableVertexAttribArray(colorLocation);
        gl.vertexAttribPointer(colorLocation, 3, gl.FLOAT, false, 24, 12);

        // Get uniform locations
        const modelViewMatrixLocation = gl.getUniformLocation(program, 'modelViewMatrix');
        const projectionMatrixLocation = gl.getUniformLocation(program, 'projectionMatrix');

        // Set up viewport
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.enable(gl.DEPTH_TEST);

        // Animation variables
        let rotation = 0;
        let lastTime = 0;
        let frameCount = 0;

        // Render function
        function render(currentTime) {
            if (!engineRunning) return;

            const deltaTime = currentTime - lastTime;
            rotation += deltaTime * 0.001;

            // Clear
            gl.clearColor(0.1, 0.1, 0.2, 1.0);
            gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

            // Use program
            gl.useProgram(program);

            // Set up matrices
            const modelViewMatrix = createModelViewMatrix(rotation);
            const projectionMatrix = createProjectionMatrix();

            gl.uniformMatrix4fv(modelViewMatrixLocation, false, modelViewMatrix);
            gl.uniformMatrix4fv(projectionMatrixLocation, false, projectionMatrix);

            // Draw
            gl.drawElements(gl.TRIANGLES, indices.length, gl.UNSIGNED_SHORT, 0);

            // Update stats
            frameCount++;
            if (currentTime - lastTime >= 1000) {
                const fps = (frameCount * 1000) / deltaTime;
                updateFPS(fps);
                frameCount = 0;
                lastTime = currentTime;
            }

            requestAnimationFrame(render);
        }

        // Start rendering
        engineInitialized = true;
        hideLoading();
        updateStatus('Ready (WebGL)');
        document.getElementById('mfs-start-btn').disabled = false;
        document.getElementById('mfs-reset-btn').disabled = false;

        // Store render function for start/pause
        window.mfsWebglRender = render;
    }

    // WebGL helper functions
    function createShader(gl, type, source) {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
            console.error('Shader compilation error:', gl.getShaderInfoLog(shader));
            gl.deleteShader(shader);
            return null;
        }
        return shader;
    }

    function createProgram(gl, vertexShader, fragmentShader) {
        const program = gl.createProgram();
        gl.attachShader(program, vertexShader);
        gl.attachShader(program, fragmentShader);
        gl.linkProgram(program);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
            console.error('Program linking error:', gl.getProgramInfoLog(program));
            gl.deleteProgram(program);
            return null;
        }
        return program;
    }

    function createModelViewMatrix(rotation) {
        const matrix = new Float32Array(16);
        const cos = Math.cos(rotation);
        const sin = Math.sin(rotation);
        
        matrix[0] = cos; matrix[1] = 0; matrix[2] = sin; matrix[3] = 0;
        matrix[4] = 0; matrix[5] = 1; matrix[6] = 0; matrix[7] = 0;
        matrix[8] = -sin; matrix[9] = 0; matrix[10] = cos; matrix[11] = 0;
        matrix[12] = 0; matrix[13] = 0; matrix[14] = -5; matrix[15] = 1;
        
        return matrix;
    }

    function createProjectionMatrix() {
        const canvas = document.getElementById('mfs-demo-canvas');
        const matrix = new Float32Array(16);
        const aspect = canvas.width / canvas.height;
        const fov = Math.PI / 4;
        const near = 0.1;
        const far = 100;
        
        const f = 1.0 / Math.tan(fov / 2);
        matrix[0] = f / aspect; matrix[1] = 0; matrix[2] = 0; matrix[3] = 0;
        matrix[4] = 0; matrix[5] = f; matrix[6] = 0; matrix[7] = 0;
        matrix[8] = 0; matrix[9] = 0; matrix[10] = (far + near) / (near - far); matrix[11] = -1;
        matrix[12] = 0; matrix[13] = 0; matrix[14] = (2 * far * near) / (near - far); matrix[15] = 0;
        
        return matrix;
    }

    // UI functions
    function updateFPS(fps) {
        document.getElementById('mfs-fps-display').textContent = Math.round(fps);
    }

    function updateMemoryUsage(bytes) {
        const mb = (bytes / (1024 * 1024)).toFixed(1);
        document.getElementById('mfs-memory-display').textContent = mb + ' MB';
    }

    function updateStatus(status) {
        document.getElementById('mfs-status-display').textContent = status;
    }

    function showError(message) {
        const errorElement = document.getElementById('mfs-error-message');
        errorElement.textContent = message;
        errorElement.style.display = 'block';
        updateStatus('Error');
    }

    function hideLoading() {
        document.getElementById('mfs-loading-overlay').classList.add('mfs-hidden');
    }

    // Module configuration
    Module = {
        canvas: document.getElementById('mfs-demo-canvas'),
        print: function(text) {
            console.log('MFS Engine:', text);
        },
        printErr: function(text) {
            console.error('MFS Engine Error:', text);
            showError(text);
        },
        onRuntimeInitialized: function() {
            console.log('MFS Engine WASM Runtime initialized');
            
            try {
                // Initialize the engine
                if (Module._initialize_spinning_cube_demo) {
                    const result = Module._initialize_spinning_cube_demo();
                    if (result === 0) {
                        engineInitialized = true;
                        hideLoading();
                        updateStatus('Ready');
                        document.getElementById('mfs-start-btn').disabled = false;
                        document.getElementById('mfs-reset-btn').disabled = false;
                    } else {
                        showError('Failed to initialize demo: ' + result);
                    }
                } else {
                    // Fallback to basic WebGL demo if WASM not available
                    initializeWebGLDemo(document.getElementById('mfs-demo-canvas'));
                }
            } catch (e) {
                console.log('WASM not available, using WebGL fallback');
                initializeWebGLDemo(document.getElementById('mfs-demo-canvas'));
            }
        },
        locateFile: function(path, prefix) {
            if (path.endsWith('.wasm')) {
                return 'mfs-spinning-cube.wasm';
            }
            return prefix + path;
        }
    };

    // Button event handlers
    function setupEventHandlers() {
        const startBtn = document.getElementById('mfs-start-btn');
        const pauseBtn = document.getElementById('mfs-pause-btn');
        const resetBtn = document.getElementById('mfs-reset-btn');

        startBtn.addEventListener('click', function() {
            if (engineInitialized && !engineRunning) {
                engineRunning = true;
                updateStatus('Running');
                startBtn.disabled = true;
                pauseBtn.disabled = false;

                if (Module._start_spinning_cube_demo) {
                    Module._start_spinning_cube_demo();
                } else if (window.mfsWebglRender) {
                    requestAnimationFrame(window.mfsWebglRender);
                }
            }
        });

        pauseBtn.addEventListener('click', function() {
            if (engineRunning) {
                engineRunning = false;
                updateStatus('Paused');
                startBtn.disabled = false;
                pauseBtn.disabled = true;

                if (Module._pause_spinning_cube_demo) {
                    Module._pause_spinning_cube_demo();
                }
            }
        });

        resetBtn.addEventListener('click', function() {
            if (engineInitialized) {
                if (Module._reset_spinning_cube_demo) {
                    Module._reset_spinning_cube_demo();
                }
                updateStatus('Reset');
                engineRunning = false;
                startBtn.disabled = false;
                pauseBtn.disabled = true;
            }
        });
    }

    // Performance monitoring
    function updatePerformanceStats() {
        const currentTime = performance.now();
        
        if (currentTime - window.mfsLastTime >= 1000) {
            if (performance.memory) {
                updateMemoryUsage(performance.memory.usedJSHeapSize);
            }
            window.mfsLastTime = currentTime;
        }

        if (engineRunning) {
            requestAnimationFrame(updatePerformanceStats);
        }
    }

    // Public API
    window.MFSEngineDemo = {
        create: function(targetElement) {
            const container = createDemoContainer();
            targetElement.appendChild(container);
            
            setupEventHandlers();
            updateStatus('Loading...');
            window.mfsLastTime = performance.now();
            updatePerformanceStats();

            // Try to load WASM module, fallback to WebGL if not available
            const script = document.createElement('script');
            script.src = 'mfs-spinning-cube.js';
            script.onerror = function() {
                console.log('WASM module not available, using WebGL fallback');
                // Trigger initialization without WASM
                setTimeout(() => {
                    if (!engineInitialized) {
                        initializeWebGLDemo(document.getElementById('mfs-demo-canvas'));
                    }
                }, 100);
            };
            document.head.appendChild(script);
        }
    };
})();