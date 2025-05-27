#!/usr/bin/env python3
"""
MFS Engine Web Build and Deployment Script

This script automates the process of building the MFS Engine for WebAssembly
and setting up a local development server for testing.
"""

import os
import sys
import subprocess
import shutil
import argparse
import json
import http.server
import socketserver
import threading
import webbrowser
import time
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Optional

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent
WEB_OUTPUT_DIR = PROJECT_ROOT / "zig-out" / "web"
WEB_TEMPLATE_DIR = PROJECT_ROOT / "web"
DEFAULT_PORT = 8080

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

class WebBuildError(Exception):
    """Custom exception for web build errors"""
    pass

def run_command(cmd: List[str], cwd: Optional[Path] = None, capture_output: bool = True) -> subprocess.CompletedProcess:
    """Run a command and return the result"""
    try:
        logger.debug(f"Running command: {' '.join(cmd)}")
        if cwd:
            logger.debug(f"Working directory: {cwd}")

        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture_output,
            text=True,
            check=True
        )

        if not capture_output:
            logger.debug("Command completed successfully")
        else:
            logger.debug(f"Command output: {result.stdout}")

        return result
    except subprocess.CalledProcessError as e:
        error_msg = f"Command failed: {' '.join(cmd)}"
        if e.stderr:
            error_msg += f"\nError output: {e.stderr}"
        if e.stdout:
            error_msg += f"\nStandard output: {e.stdout}"
        raise WebBuildError(error_msg)

def check_dependencies():
    """Check if required tools are available"""
    logger.info("Checking dependencies...")

    # Check for zig
    try:
        result = run_command(["zig", "version"])
        logger.info(f"✓ Zig found: {result.stdout.strip()}")
    except (FileNotFoundError, WebBuildError):
        raise WebBuildError("Zig compiler not found. Please install Zig and add it to your PATH.")

    # Check if we're in the right directory
    build_zig = PROJECT_ROOT / "build.zig"
    if not build_zig.exists():
        raise WebBuildError(f"build.zig not found in {PROJECT_ROOT}. Please run from the project root.")

    logger.info("✓ All dependencies satisfied")

def clean_build():
    """Clean previous build artifacts"""
    logger.info("Cleaning previous build artifacts...")

    # Remove zig-out directory
    zig_out = PROJECT_ROOT / "zig-out"
    if zig_out.exists():
        shutil.rmtree(zig_out)
        logger.info("✓ Removed zig-out directory")

    # Remove zig-cache directory
    zig_cache = PROJECT_ROOT / "zig-cache"
    if zig_cache.exists():
        shutil.rmtree(zig_cache)
        logger.info("✓ Removed zig-cache directory")

    # Remove deploy directory
    deploy_dir = PROJECT_ROOT / "deploy"
    if deploy_dir.exists():
        shutil.rmtree(deploy_dir)
        logger.info("✓ Removed deploy directory")

    logger.info("✓ Clean completed")

def build_for_web(optimize: str = "Debug", extra_args: Optional[List[str]] = None):
    """Build the engine for WebAssembly"""
    logger.info(f"Building for WebAssembly (optimization: {optimize})...")

    cmd = ["zig", "build", "web", f"-Doptimize={optimize}"]

    if extra_args:
        cmd.extend(extra_args)

    try:
        run_command(cmd, cwd=PROJECT_ROOT, capture_output=False)
        logger.info("✓ WebAssembly build completed")
    except WebBuildError as e:
        raise WebBuildError(f"Failed to build WebAssembly: {e}")

    # Verify output files exist
    if not WEB_OUTPUT_DIR.exists():
        raise WebBuildError(f"Output directory not found: {WEB_OUTPUT_DIR}")

    required_files = ["mfs-web.wasm", "mfs-web.js"]
    for file in required_files:
        file_path = WEB_OUTPUT_DIR / file
        if not file_path.exists():
            raise WebBuildError(f"Required output file not found: {file_path}")

    logger.info("✓ Build verification completed")

def setup_web_files():
    """Setup additional web files"""
    logger.info("Setting up web files...")

    # Ensure output directory exists
    WEB_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Copy template files if they exist
    if WEB_TEMPLATE_DIR.exists():
        for file in WEB_TEMPLATE_DIR.iterdir():
            if file.is_file():
                shutil.copy2(file, WEB_OUTPUT_DIR)
                logger.info(f"✓ Copied {file.name}")
    
    # Create basic HTML if it doesn't exist
    html_file = WEB_OUTPUT_DIR / "index.html"
    if not html_file.exists():
        create_basic_html()
    
    logger.info("✓ Web files setup completed")

def create_basic_html():
    """Create a basic HTML file for the WebAssembly build"""
    logger.info("Creating basic HTML file...")
    
    html_content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MFS Engine - WebAssembly</title>
    <style>
        body { 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #1a1a1a, #2d2d2d); 
            color: white; 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            min-height: 100vh;
        }
        canvas { 
            border: 2px solid #444; 
            border-radius: 8px;
            display: block; 
            margin: 20px auto; 
            box-shadow: 0 4px 8px rgba(0,0,0,0.3);
        }
        .info { 
            text-align: center; 
            margin: 20px; 
        }
        .status { 
            padding: 10px; 
            margin: 10px 0; 
            border-radius: 4px; 
            text-align: center; 
        }
        .loading { 
            background: #333; 
            border: 1px solid #555; 
        }
        .ready { 
            background: #1a5a1a; 
            border: 1px solid #2a7a2a; 
        }
        .error { 
            background: #5a1a1a; 
            border: 1px solid #7a2a2a; 
        }
        .footer { 
            position: fixed; 
            bottom: 10px; 
            right: 10px; 
            font-size: 0.8em; 
            opacity: 0.7; 
        }
    </style>
</head>
<body>
    <div class="info">
        <h1>MFS Engine</h1>
        <p>WebAssembly Build</p>
        <div id="status" class="status loading">Loading...</div>
    </div>
    
    <canvas id="canvas" width="800" height="600"></canvas>
    
    <div class="footer">
        MFS Engine v1.0
    </div>
    
    <script>
        // WebAssembly loading and initialization
        const statusDiv = document.getElementById('status');
        const canvas = document.getElementById('canvas');
        
        function updateStatus(message, type = 'loading') {
            statusDiv.textContent = message;
            statusDiv.className = `status ${type}`;
        }
        
        // Error handling
        window.addEventListener('error', function(e) {
            updateStatus(`Error: ${e.message}`, 'error');
            console.error('Runtime error:', e);
        });
        
        // WebAssembly module setup
        window.Module = {
            canvas: canvas,
            onRuntimeInitialized: function() {
                updateStatus('Engine ready!', 'ready');
                console.log('MFS Engine initialized successfully');
            },
            onAbort: function(what) {
                updateStatus('Engine failed to start', 'error');
                console.error('Engine abort:', what);
            },
            printErr: function(text) { 
                console.error('Engine Error:', text); 
            }
        };
    </script>
    <script src="mfs-web.js"></script>
</body>
</html>"""
    
    with open(WEB_OUTPUT_DIR / "index.html", 'w') as f:
        f.write(html_content)
    logger.info("✓ Created basic HTML file")

def verify_build():
    """Verify that the build output exists"""
    logger.info("Verifying build output...")
    
    required_files = ["mfs-web.wasm", "mfs-web.js"]
    for file in required_files:
        file_path = WEB_OUTPUT_DIR / file
        if not file_path.exists():
            raise WebBuildError(f"Required file not found: {file_path}")
        
        file_size = file_path.stat().st_size
        logger.info(f"✓ {file} ({file_size:,} bytes)")
    
    # Check if HTML file exists
    html_file = WEB_OUTPUT_DIR / "index.html"
    if html_file.exists():
        logger.info(f"✓ index.html ({html_file.stat().st_size:,} bytes)")
    else:
        logger.warning("⚠ index.html not found")
    
    logger.info("✓ Build verification completed")

class CORSHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP request handler with CORS headers for WebAssembly"""

    def end_headers(self):
        # Required headers for WebAssembly and WebGPU
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def guess_type(self, path):
        mimetype, encoding = super().guess_type(path)
        path_str = str(path)
        if path_str.endswith('.wasm'):
            return 'application/wasm'
        elif path_str.endswith('.js'):
            return 'application/javascript'
        return mimetype

    def log_message(self, format, *args):
        """Override to reduce server log noise"""
        # Only log errors and important requests
        if not any(x in args[0] for x in ['favicon.ico', '.map'] if args):
            super().log_message(format, *args)

def find_available_port(start_port: int = DEFAULT_PORT, max_attempts: int = 10) -> int:
    """Find an available port starting from start_port"""
    import socket
    for port in range(start_port, start_port + max_attempts):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('localhost', port))
                return port
        except OSError:
            continue
    raise WebBuildError(f"Could not find available port in range {start_port}-{start_port + max_attempts}")

def start_dev_server(port: int = DEFAULT_PORT, open_browser: bool = True):
    """Start a development server"""
    logger.info(f"Starting development server on port {port}...")
    
    if not WEB_OUTPUT_DIR.exists():
        raise WebBuildError(f"Web output directory not found: {WEB_OUTPUT_DIR}")
    
    # Find available port
    try:
        port = find_available_port(port)
    except WebBuildError:
        logger.warning(f"Port {port} not available, trying to find alternative...")
        port = find_available_port(port + 1)
    
    original_cwd = os.getcwd()
    
    try:
        os.chdir(WEB_OUTPUT_DIR)
        
        # Start server
        with socketserver.TCPServer(("", port), CORSHTTPRequestHandler) as httpd:
            server_url = f"http://localhost:{port}"
            logger.info(f"✓ Server running at {server_url}")
            logger.info("Press Ctrl+C to stop the server")
            
            # Open browser after a short delay
            def open_browser_delayed():
                time.sleep(1)
                if open_browser:
                    logger.info(f"Opening browser to {server_url}")
                    webbrowser.open(server_url)
                else:
                    logger.info(f"Server ready - open {server_url} in your browser")
            
            if open_browser:
                browser_thread = threading.Thread(target=open_browser_delayed)
                browser_thread.daemon = True
                browser_thread.start()
            
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                logger.info("Server stopped by user")
    except OSError as e:
        if e.errno == 48 or "Address already in use" in str(e):
            raise WebBuildError(f"Port {port} is already in use. Try a different port with --port")
        else:
            raise WebBuildError(f"Failed to start server: {e}")
    finally:
        os.chdir(original_cwd)

def create_deployment_package():
    """Create a deployment package"""
    logger.info("Creating deployment package...")

    package_dir = PROJECT_ROOT / "deploy"
    if package_dir.exists():
        shutil.rmtree(package_dir)

    shutil.copytree(WEB_OUTPUT_DIR, package_dir)

    # Create deployment info
    try:
        build_time = datetime.now().isoformat()
    except Exception:
        build_time = "unknown"

    deploy_info = {
        "engine": "MFS Engine",
        "version": "1.0.0",
        "build_time": build_time,
        "files": [f.name for f in package_dir.iterdir() if f.is_file()],
        "total_size_mb": sum(f.stat().st_size for f in package_dir.iterdir() if f.is_file()) / (1024 * 1024),
        "deployment_notes": {
            "requirements": [
                "HTTPS required for WebGPU and SharedArrayBuffer",
                "Modern browser with WebAssembly support (Chrome 57+, Firefox 52+, Safari 11+)",
                "Proper MIME type for .wasm files (application/wasm)",
                "Server must support range requests for large files"
            ],
            "required_headers": {
                "Cross-Origin-Embedder-Policy": "require-corp",
                "Cross-Origin-Opener-Policy": "same-origin",
                "Content-Type": "application/wasm (for .wasm files)"
            },
            "recommended_headers": {
                "Cache-Control": "public, max-age=31536000 (for static assets)",
                "Content-Encoding": "gzip (if server supports compression)"
            }
        },
        "server_configs": {
            "nginx": {
                "location": "~\\.wasm$ { add_header Content-Type application/wasm; }",
                "headers": "add_header Cross-Origin-Embedder-Policy require-corp; add_header Cross-Origin-Opener-Policy same-origin;"
            },
            "apache": {
                "mime_type": "AddType application/wasm .wasm",
                "headers": "Header always set Cross-Origin-Embedder-Policy require-corp"
            }
        }
    }

    with open(package_dir / "deploy-info.json", 'w', encoding='utf-8') as f:
        json.dump(deploy_info, f, indent=2)

    # Create a simple README for deployment
    readme_content = """# MFS Engine WebAssembly Deployment

## Quick Start
1. Upload all files to your web server
2. Ensure HTTPS is enabled (required for WebGPU)
3. Configure proper MIME types and headers (see deploy-info.json)
4. Access index.html in a modern browser

## Requirements
- HTTPS connection
- Modern browser with WebAssembly support
- Proper server configuration for .wasm files

See deploy-info.json for detailed deployment instructions.
"""

    with open(package_dir / "README.md", 'w', encoding='utf-8') as f:
        f.write(readme_content)

    total_size_mb = deploy_info["total_size_mb"]
    logger.info(f"✓ Deployment package created in {package_dir}")
    logger.info(f"✓ Package size: {total_size_mb:.2f} MB")
    logger.info(f"✓ Files included: {len(deploy_info['files'])}")

def main():
    parser = argparse.ArgumentParser(
        description="Build MFS Engine for WebAssembly",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                          # Build with debug optimization and start server
  %(prog)s --optimize ReleaseFast   # Build optimized release
  %(prog)s --clean --deploy         # Clean, build, and create deployment package
  %(prog)s --no-server --port 3000  # Build without starting server
        """
    )
    parser.add_argument("--optimize", choices=["Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"],
                       default="Debug", help="Optimization level (default: Debug)")
    parser.add_argument("--clean", action="store_true", help="Clean before building")
    parser.add_argument("--no-server", action="store_true", help="Don't start development server")
    parser.add_argument("--no-browser", action="store_true", help="Don't open browser automatically")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Development server port (default: {DEFAULT_PORT})")
    parser.add_argument("--deploy", action="store_true", help="Create deployment package")
    parser.add_argument("--build-args", nargs="*", help="Additional build arguments")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging")

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        print("MFS Engine Web Build Script")
        print("=" * 40)

        # Validate port range
        if not (1024 <= args.port <= 65535):
            raise WebBuildError("Port must be between 1024 and 65535")

        # Check dependencies
        check_dependencies()

        # Clean if requested
        if args.clean:
            clean_build()

        # Build for web
        build_for_web(args.optimize, args.build_args)

        # Setup web files
        setup_web_files()

        # Verify build
        verify_build()

        # Create deployment package if requested
        if args.deploy:
            create_deployment_package()

        # Start development server unless disabled
        if not args.no_server:
            start_dev_server(args.port, not args.no_browser)

        logger.info("✓ Build process completed successfully!")

    except WebBuildError as e:
        logger.error(f"Build failed: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Build interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()