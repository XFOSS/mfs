#!/bin/bash

# Build MFS Engine Spinning Cube Demo for WebAssembly

echo "Building MFS Engine Spinning Cube Demo..."

# Create web directory if it doesn't exist
mkdir -p web

# Build the WASM module using Zig
echo "Compiling to WebAssembly..."
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# Copy the embed script to web directory
echo "Setting up web files..."
cp web/spinning_cube_embed.js web/

# Create a simple test page
echo "Creating test page..."
cat > web/test_demo.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MFS Engine Demo Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background: #f0f0f0;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>MFS Engine Spinning Cube Demo Test</h1>
        <div id="demo-container"></div>
    </div>
    
    <script src="spinning_cube_embed.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const container = document.getElementById('demo-container');
            if (window.MFSEngineDemo) {
                window.MFSEngineDemo.create(container);
            } else {
                container.innerHTML = '<p style="color: red;">Demo script failed to load</p>';
            }
        });
    </script>
</body>
</html>
EOF

echo "Build complete!"
echo "Test the demo by opening web/test_demo.html in your browser"
echo "Or integrate it into documentation pages using the embed script"