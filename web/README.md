# MFS Engine WebAssembly Demo

This directory contains the interactive spinning cube demo for the MFS Engine documentation.

## Files

- `spinning_cube_demo.html` - Standalone demo page
- `spinning_cube_embed.js` - Embeddable JavaScript module for documentation pages
- `test_demo.html` - Test page to verify the demo works
- `index.html` - Original full-featured demo

## Features

### 🎮 Interactive 3D Demo
- **Real-time rendering** with WebGL/WebAssembly
- **Performance monitoring** (FPS, memory usage)
- **Interactive controls** (Start, Pause, Reset)
- **Responsive design** that works on all devices

### 🚀 Technology Stack
- **WebGL fallback** - Works even without WASM
- **WebAssembly support** - For optimal performance
- **Modern JavaScript** - ES6+ features
- **CSS animations** - Smooth loading and transitions

### 📱 Cross-Platform
- **Desktop browsers** - Chrome, Firefox, Safari, Edge
- **Mobile devices** - Touch-friendly controls
- **Progressive enhancement** - Works with basic WebGL

## Usage

### Standalone Demo
Open `spinning_cube_demo.html` in any modern web browser to see the full demo.

### Embed in Documentation
```html
<!-- Load the demo script -->
<script src="spinning_cube_embed.js"></script>

<!-- Create a container -->
<div id="demo-container"></div>

<!-- Initialize the demo -->
<script>
document.addEventListener('DOMContentLoaded', function() {
    const container = document.getElementById('demo-container');
    if (window.MFSEngineDemo) {
        window.MFSEngineDemo.create(container);
    }
});
</script>
```

### Build WASM Version
```bash
# Build the WebAssembly module
./build_demo.sh

# Test the demo
open web/test_demo.html
```

## Demo Features

### 🎨 Visual Elements
- **Spinning cube** with colored faces
- **Smooth rotation** at 60 FPS
- **Depth testing** for proper 3D rendering
- **Perspective projection** for realistic depth

### 📊 Performance Stats
- **FPS counter** - Real-time frame rate
- **Memory usage** - JavaScript heap monitoring
- **Status indicator** - Loading, Ready, Running, Paused

### 🎛️ Controls
- **Start button** - Begin the animation
- **Pause button** - Stop the animation
- **Reset button** - Return to initial state

## Technical Details

### WebGL Implementation
The demo uses WebGL for 3D rendering with:
- **Vertex shader** - Position and color attributes
- **Fragment shader** - Color interpolation
- **Indexed drawing** - Efficient triangle rendering
- **Matrix transformations** - Model-view and projection matrices

### WebAssembly Support
When available, the demo can use compiled WebAssembly for:
- **Better performance** - Native code execution
- **Memory efficiency** - Direct memory access
- **Cross-language integration** - Zig to JavaScript

### Fallback Strategy
1. **Try WebAssembly** - Load and initialize WASM module
2. **Fallback to WebGL** - Use pure JavaScript WebGL
3. **Error handling** - Graceful degradation with user feedback

## Browser Compatibility

| Feature | Chrome | Firefox | Safari | Edge |
|---------|--------|---------|--------|------|
| WebGL | ✅ | ✅ | ✅ | ✅ |
| WebAssembly | ✅ | ✅ | ✅ | ✅ |
| Performance API | ✅ | ✅ | ✅ | ✅ |
| ES6 Modules | ✅ | ✅ | ✅ | ✅ |

## Development

### Building the Demo
```bash
# Install dependencies (if needed)
npm install

# Build WASM version
./build_demo.sh

# Test locally
python3 -m http.server 8000
# Then open http://localhost:8000/web/test_demo.html
```

### Customization
The demo can be customized by modifying:
- **Colors** - Change cube face colors in the vertex data
- **Animation speed** - Adjust rotation rate
- **Camera position** - Modify view matrix
- **Shaders** - Update vertex/fragment shaders

### Integration
To add the demo to other pages:
1. Include the embed script
2. Create a container element
3. Initialize with `MFSEngineDemo.create()`

## Performance

### Benchmarks
- **Target FPS**: 60 FPS
- **Memory usage**: < 10MB typical
- **Load time**: < 2 seconds
- **Animation smoothness**: 16ms frame time

### Optimization
- **Efficient rendering** - Minimal draw calls
- **Memory management** - Proper buffer cleanup
- **Animation timing** - RequestAnimationFrame usage
- **Error handling** - Graceful fallbacks

## Future Enhancements

### Planned Features
- **Multiple objects** - Multiple spinning cubes
- **User interaction** - Mouse/touch camera control
- **Advanced materials** - PBR rendering
- **Post-processing** - Bloom, shadows, effects

### Technical Improvements
- **WebGPU support** - Next-generation graphics API
- **Compute shaders** - GPU-accelerated effects
- **Asset loading** - Dynamic texture/model loading
- **Audio integration** - Spatial audio support

## License

This demo is part of the MFS Engine project and is licensed under the MIT License.