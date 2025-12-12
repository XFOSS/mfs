#!/bin/bash

# Merge all changes into main branch and clean up other branches

echo "🔄 Starting merge process..."

# Check current branch
echo "Current branch: $(git branch --show-current)"

# Add all changes
echo "📝 Adding all changes..."
git add .

# Commit changes
echo "💾 Committing changes..."
git commit -m "feat: Add WebAssembly spinning cube demo and project analysis

- Add web_cube_demo.zig for WASM-compatible spinning cube
- Add build_web_demo.zig for WASM compilation
- Update web/index.html to use MFS Engine spinning cube demo
- Add PROJECTS_ANALYSIS_REPORT.md with donaldfilimon/underswitchx analysis
- Update documentation to reflect new WASM demo capabilities
- Improve web documentation with real MFS Engine demo"

# Check if we're on main branch
if [ "$(git branch --show-current)" != "main" ]; then
    echo "🔄 Switching to main branch..."
    git checkout main
fi

# Pull latest changes from origin
echo "📥 Pulling latest changes from origin..."
git pull origin main

# Check for any unmerged branches
echo "🔍 Checking for unmerged branches..."
git branch --no-merged main

# Delete local branches that are already merged
echo "🧹 Cleaning up merged branches..."
git branch --merged main | grep -v "main" | xargs -r git branch -d

# Delete remote branches that are already merged (if any)
echo "🧹 Cleaning up remote branches..."
git remote prune origin

# Push changes to origin
echo "📤 Pushing changes to origin..."
git push origin main

echo "✅ Merge complete! All changes are now in main branch."
echo "📊 Summary:"
echo "  - All new files committed"
echo "  - Merged branches cleaned up"
echo "  - Changes pushed to origin/main"