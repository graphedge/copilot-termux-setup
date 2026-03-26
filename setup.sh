#!/data/data/com.termux/files/usr/bin/bash

# Ensure running under Termux
if [ -z "${TERMUX_VERSION:-}" ]; then
  echo "Error: This setup script must be run inside Termux (TERMUX_VERSION not set). Exiting." >&2
  exit 1
fi

set -e  # Exit on error
set -u  # Exit on undefined variable

# Detect architecture for Android platform string
ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64)
    ANDROID_ARCH="android-arm64"
    ;;
  x86_64|amd64)
    ANDROID_ARCH="android-x64"
    ;;
  i686|i386)
    ANDROID_ARCH="android-ia32"
    ;;
  armv7l|armv8l)
    ANDROID_ARCH="android-arm"
    ;;
  *)
    echo "Warning: Unknown architecture $ARCH, defaulting to android-arm64" >&2
    ANDROID_ARCH="android-arm64"
    ;;
esac

# Install root: allow override with first argument, otherwise derive from npm global root
if [ "${1:-}" != "" ]; then
  INSTALL_ROOT="$1"
else
  INSTALL_ROOT="${PREFIX}/lib/node_modules/@github/copilot"
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Module status tracking
MODULES_FIXED=0
MODULES_FAILED=0

################################################################################
# HELPER FUNCTIONS
################################################################################

# Print colored status messages
print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    MODULES_FIXED=$((MODULES_FIXED+1))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    MODULES_FAILED=$((MODULES_FAILED+1))
}

print_step() {
    echo ""
    echo -e "${GREEN}▶${NC} ${BLUE}$1${NC}"
    echo ""
}

# Ensure a pkg package is installed only if missing; can check by command or pkg list-installed
ensure_pkg() {
  local pkgname="$1"
  local check_cmd="${2:-}"

  if [ -n "$check_cmd" ]; then
    if command -v "$check_cmd" >/dev/null 2>&1; then
      print_info "$pkgname (command $check_cmd) already available at $(command -v $check_cmd)"
      return 0
    fi
  else
    if pkg list-installed "$pkgname" >/dev/null 2>&1; then
      print_info "$pkgname already installed according to pkg"
      return 0
    fi
  fi

  print_info "Installing $pkgname"
  if pkg install -y "$pkgname"; then
    print_success "$pkgname installed"
  else
    print_error "Failed to install $pkgname"
    return 1
  fi
}

################################################################################
# MAIN INSTALLATION SCRIPT
################################################################################

print_header "GitHub Copilot CLI on Termux"

echo "This script will install Github Copilot CLI and 4 native modules:"
echo ""
echo "  1. node-pty     - Pseudo-terminal for command execution"
echo "  2. sharp        - Image processing library"
echo "  3. keytar       - Secure credential storage"
echo "  4. clipboard    - System clipboard access (Termux API wrapper)"
echo ""
echo "Termux ${TERMUX_VERSION:-unknown} ($ANDROID_ARCH)"
echo ""

if [ -t 0 ]; then
    read -p "Press Enter to continue or Ctrl+C to abort..."
fi

################################################################################
# STEP 0: Update package repositories and install Node.js
################################################################################

print_header "Updating Termux packages and installing Node.js"

print_info "Running pkg update"
pkg update -y || print_warning "pkg update failed, continuing anyway"

print_info "Installing core build dependencies"
ensure_pkg nodejs node
ensure_pkg clang clang
ensure_pkg make make
ensure_pkg python python

# Create .gyp configuration for node-gyp (fixes android ndk path issues)
# Non-destructive: only create if missing
GYP_FILE="$HOME/.gyp/include.gypi"
if [ ! -f "$GYP_FILE" ]; then
    print_info "Creating ~/.gyp/include.gypi for node-gyp compatibility"
    mkdir -p ~/.gyp
    echo "{'variables':{'android_ndk_path':''}}" > "$GYP_FILE"
    print_info "Created gyp configuration"
else
    print_info "~/.gyp/include.gypi already exists, skipping"
fi

################################################################################
# STEP 1: Ensure GitHub Copilot CLI installed globally
################################################################################

print_step "Step 1/11: Installing GitHub Copilot CLI globally"

print_info "Running npm install -g @github/copilot to ensure CLI is present"
if npm install -g @github/copilot; then
    print_info "GitHub Copilot CLI installed globally"
else
    print_error "Failed to install GitHub Copilot CLI globally"
    exit 1
fi

if [ ! -d "$INSTALL_ROOT" ]; then
    print_error "Install root not found at $INSTALL_ROOT after global install"
    exit 1
fi

cd "$INSTALL_ROOT"

print_step "Step 2/11: Installing system dependencies"

ensure_pkg glib
ensure_pkg xorgproto
ensure_pkg rust rustc
ensure_pkg libvips
ensure_pkg pkg-config pkg-config
ensure_pkg ripgrep rg

print_success "System dependencies installed successfully"

# Ensure packaged ripgrep is available system-wide if no system 'rg' exists.
# Idempotent: only creates a symlink when needed and won't overwrite existing files.
RIPGREP_SRC="$(find "$INSTALL_ROOT/ripgrep" -type f -name 'rg' -perm /111 2>/dev/null | head -n1 || true)"
if [ -z "$RIPGREP_SRC" ]; then
    print_warning "No packaged ripgrep binary found; skipping rg symlink"
else
    # Use PREFIX for proper Termux bin directory, fallback to hardcoded path
    TARGET_RG="${PREFIX:-/data/data/com.termux/files/usr}/bin/rg"
    if command -v rg >/dev/null 2>&1; then
        print_info "System 'rg' already available at $(command -v rg); leaving system ripgrep intact"
    else
        mkdir -p "$(dirname "$TARGET_RG")"
        if [ -L "$TARGET_RG" ]; then
            if [ "$(readlink -f "$TARGET_RG")" = "$RIPGREP_SRC" ]; then
                print_info "rg symlink already points to packaged ripgrep"
            else
                print_warning "rg symlink exists and points elsewhere; skipping to avoid overwrite"
            fi
        elif [ -e "$TARGET_RG" ]; then
            print_warning "An executable named 'rg' exists at $TARGET_RG; skipping symlink"
        else
            ln -sf "$RIPGREP_SRC" "$TARGET_RG" && print_success "Linked packaged ripgrep to $TARGET_RG"
        fi
    fi
fi

# Link system ripgrep to the Copilot expected path
COPILOT_RG_DIR="$INSTALL_ROOT/ripgrep/bin/$ANDROID_ARCH"
COPILOT_RG_PATH="$COPILOT_RG_DIR/rg"
SYSTEM_RG="$(command -v rg 2>/dev/null || true)"

if [ -n "$SYSTEM_RG" ]; then
    mkdir -p "$COPILOT_RG_DIR"
    if [ ! -e "$COPILOT_RG_PATH" ]; then
        ln -sf "$SYSTEM_RG" "$COPILOT_RG_PATH" && print_success "Linked system rg to Copilot expected path"
    elif [ -L "$COPILOT_RG_PATH" ] && [ "$(readlink -f "$COPILOT_RG_PATH")" = "$SYSTEM_RG" ]; then
        print_info "Copilot rg symlink already correct"
    else
        print_warning "Copilot rg path exists; skipping"
    fi
else
    print_warning "No system rg found; Copilot may fail to use ripgrep"
fi

print_step "Step 3/11: Installing node-pty"

if npm install node-pty; then
    print_success "node-pty installed successfully"
    
    # Verify the build
    if [ -f "node_modules/node-pty/build/Release/pty.node" ]; then
        print_success "pty.node binary found"
    else
        print_error "pty.node binary not found after installation"
        exit 1
    fi
else
    print_error "Failed to install node-pty"
    exit 1
fi

print_step "Step 4/11: Installing node-addon-api and keytar"

npm install node-addon-api@latest --save-dev
if npm install keytar --ignore-scripts; then
    print_success "keytar package downloaded"
else
    print_error "Failed to install keytar package"
    exit 1
fi


print_step "Step 5/11: Patching node-addon-api enum handling"
find node_modules -name "napi.h" | while read -r NAPI_HEADER; do
    if grep -q "static_cast<napi_typedarray_type>(-1)" "$NAPI_HEADER"; then
        cp "$NAPI_HEADER" "$NAPI_HEADER.backup"
        if sed -i 's/static_cast<napi_typedarray_type>(-1)/napi_uint8_array/' "$NAPI_HEADER"; then
            print_success "Patched $NAPI_HEADER"
        else
            print_error "Failed to patch $NAPI_HEADER"
        fi
    fi
done

print_step "Step 6/11: Installing sharp"
if npm install sharp; then
    print_success "sharp installed and compiled successfully"
else
    print_error "Failed to install sharp"
    print_warning "Copilot CLI will work but without image processing features"
fi

print_step "Step 7/11: Setting up keytar (file-based bypass for Termux)"

# keytar requires libsecret-1 which is not available in Termux.
# Instead of compiling the native addon, we intercept require('keytar') via
# a Node.js Module._load hook and return a file-based credential store.

mkdir -p "$HOME/.copilot-hooks"

cat > "$HOME/.copilot-hooks/keytar-bypass.js" << 'KEYTARBYPASS'
// File-based keytar bypass for Termux (replaces libsecret with JSON file storage)
'use strict';
const Module = require('module');
const fs = require('fs');
const path = require('path');
const os = require('os');
const originalLoad = Module._load;

const CREDS_FILE = path.join(os.homedir(), '.config', 'copilot-termux', 'credentials.json');

function loadStore() {
  try {
    if (fs.existsSync(CREDS_FILE)) {
      return JSON.parse(fs.readFileSync(CREDS_FILE, 'utf8'));
    }
  } catch (e) {}
  return {};
}

function saveStore(store) {
  fs.mkdirSync(path.dirname(CREDS_FILE), { recursive: true });
  fs.writeFileSync(CREDS_FILE, JSON.stringify(store, null, 2), { mode: 0o600 });
}

const keytarImpl = {
  getPassword(service, account) {
    const store = loadStore();
    return Promise.resolve(store[`${service}\x00${account}`] || null);
  },
  setPassword(service, account, password) {
    const store = loadStore();
    store[`${service}\x00${account}`] = password;
    saveStore(store);
    return Promise.resolve();
  },
  deletePassword(service, account) {
    const store = loadStore();
    const key = `${service}\x00${account}`;
    const existed = key in store;
    if (existed) { delete store[key]; saveStore(store); }
    return Promise.resolve(existed);
  },
  findCredentials(service) {
    const store = loadStore();
    const prefix = `${service}\x00`;
    return Promise.resolve(
      Object.entries(store)
        .filter(([k]) => k.startsWith(prefix))
        .map(([k, password]) => ({ account: k.slice(prefix.length), password }))
    );
  },
  findPassword(service) {
    const store = loadStore();
    const prefix = `${service}\x00`;
    const entry = Object.entries(store).find(([k]) => k.startsWith(prefix));
    return Promise.resolve(entry ? entry[1] : null);
  }
};

Module._load = function(request, parent, isMain) {
  if (request === 'keytar' ||
      request.endsWith('keytar.node') ||
      (request.includes('/keytar/') && request.endsWith('.node'))) {
    return keytarImpl;
  }
  return originalLoad.call(this, request, parent, isMain);
};
KEYTARBYPASS

print_success "keytar bypass created at ~/.copilot-hooks/keytar-bypass.js"

# Termux login shells source ~/.bash_profile, not ~/.bashrc.
# Write to ~/.bash_profile; create it with a ~/.bashrc source if it doesn't exist.
BASH_PROFILE="$HOME/.bash_profile"
BYPASS_LINE='export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require $HOME/.copilot-hooks/keytar-bypass.js"'
if [ ! -f "$BASH_PROFILE" ]; then
    { echo "# ~/.bash_profile - sourced by login shells (Termux default)";
      echo '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'; } > "$BASH_PROFILE"
fi
if ! grep -qF 'keytar-bypass.js' "$BASH_PROFILE" 2>/dev/null; then
    { echo ""; echo "# GitHub Copilot CLI - keytar bypass for Termux"; echo "$BYPASS_LINE"; } >> "$BASH_PROFILE"
    print_success "Added keytar bypass to ~/.bash_profile"
else
    print_info "keytar bypass already in ~/.bash_profile"
fi
# Also keep ~/.bashrc in sync for non-login shells
BASHRC="$HOME/.bashrc"
if ! grep -qF 'keytar-bypass.js' "$BASHRC" 2>/dev/null; then
    { echo ""; echo "# GitHub Copilot CLI - keytar bypass for Termux"; echo "$BYPASS_LINE"; } >> "$BASHRC"
fi
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require $HOME/.copilot-hooks/keytar-bypass.js"

print_step "Step 8/11: Installing termux-api for clipboard support"
ensure_pkg termux-api termux-clipboard-get

print_step "Step 9/11: Setting up clipboard (Termux API wrapper)"
if [ ! -f "clipboard/index.cjs" ] || [ ! -f "clipboard/android-impl.cjs" ]; then
    mkdir -p clipboard
    if [ ! -f "clipboard/index.cjs" ]; then
        cat > clipboard/index.cjs <<'IDX'
const os = require('os');

if (os.platform() === 'android' || process.env.PREFIX?.includes('com.termux')) {
  module.exports = require('./android-impl.cjs');
} else {
  try {
    module.exports = require('../@teddyzhu/clipboard');
  } catch (e) {
    console.error('Native clipboard module not available, falling back to Android implementation');
    module.exports = require('./android-impl.cjs');
  }
}
IDX
    fi
    if [ ! -f "clipboard/android-impl.cjs" ]; then
        cat > clipboard/android-impl.cjs <<'AIDX'
const { execSync, exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);

class ClipboardManager {
  constructor() {
    try {
      execSync('which termux-clipboard-get', { stdio: 'ignore' });
      execSync('which termux-clipboard-set', { stdio: 'ignore' });
    } catch (e) {
      throw new Error('Termux API not installed. Run: pkg install termux-api');
    }
  }

  getText() {
    try {
      return execSync('termux-clipboard-get').toString();
    } catch (e) {
      throw new Error(`Failed to get text: ${e.message}`);
    }
  }

  setText(text) {
    try {
      execSync(`termux-clipboard-set`, { input: text });
    } catch (e) {
      throw new Error(`Failed to set text: ${e.message}`);
    }
  }

  async getTextAsync() {
    try {
      const { stdout } = await execAsync('termux-clipboard-get');
      return stdout;
    } catch (e) {
      throw new Error(`Failed to get text: ${e.message}`);
    }
  }

  async setTextAsync(text) {
    try {
      await execAsync('termux-clipboard-set', { input: text });
    } catch (e) {
      throw new Error(`Failed to set text: ${e.message}`);
    }
  }

  getHtml() {
    throw new Error('HTML clipboard not supported on Android/Termux');
  }

  setHtml() {
    throw new Error('HTML clipboard not supported on Android/Termux');
  }

  getRichText() {
    throw new Error('Rich text clipboard not supported on Android/Termux');
  }

  setRichText() {
    throw new Error('Rich text clipboard not supported on Android/Termux');
  }

  getImageBase64() {
    throw new Error('Image clipboard not supported on Android/Termux');
  }

  getImageData() {
    throw new Error('Image clipboard not supported on Android/Termux');
  }

  setImageBase64() {
    throw new Error('Image clipboard not supported on Android/Termux');
  }

  setImageRaw() {
    throw new Error('Image clipboard not supported on Android/Termux');
  }

  getImageRaw() {
    throw new Error('Image clipboard not supported on Android/Termux');
  }

  getFiles() {
    throw new Error('Files clipboard not supported on Android/Termux');
  }

  setFiles() {
    throw new Error('Files clipboard not supported on Android/Termux');
  }

  setBuffer() {
    throw new Error('Custom buffer clipboard not supported on Android/Termux');
  }

  getBuffer() {
    throw new Error('Custom buffer clipboard not supported on Android/Termux');
  }

  setContents(contents) {
    if (contents.text) {
      return this.setText(contents.text);
    }
    throw new Error('Only text content is supported on Android/Termux');
  }

  hasFormat(format) {
    return format === 'text';
  }

  getAvailableFormats() {
    return ['text'];
  }

  clear() {
    try {
      execSync('termux-clipboard-set', { input: '' });
    } catch (e) {
      throw new Error(`Failed to clear clipboard: ${e.message}`);
    }
  }
}

class ClipboardListener {
  constructor() {
    this.watchProcess = null;
    this.lastContent = '';
    this.callbacks = [];
  }

  watch(callback) {
    if (this.watchProcess) {
      this.stop();
    }

    this.callbacks.push(callback);
    
    this.lastContent = '';
    try {
      this.lastContent = execSync('termux-clipboard-get').toString();
    } catch (e) {
      // Ignore initial read errors
    }

    this.watchProcess = setInterval(() => {
      try {
        const currentContent = execSync('termux-clipboard-get').toString();
        if (currentContent !== this.lastContent) {
          this.lastContent = currentContent;
          const clipboardData = {
            availableFormats: ['text'],
            text: currentContent,
            rtf: null,
            html: null,
            image: null,
            files: null,
            files: null
          };
          this.callbacks.forEach(cb => {
            try {
              cb(clipboardData);
            } catch (e) {
              console.error('Clipboard callback error:', e);
            }
          });
        }
      } catch (e) {
        // Ignore polling errors
      }
    }, 500);
  }

  stop() {
    if (this.watchProcess) {
      clearInterval(this.watchProcess);
      this.watchProcess = null;
    }
    this.callbacks = [];
  }

  isWatching() {
    return this.watchProcess !== null;
  }

  getListenerType() {
    return 'android-termux-api';
  }
}

function getClipboardText() {
  try {
    return execSync('termux-clipboard-get').toString();
  } catch (e) {
    throw new Error(`Failed to get text: ${e.message}`);
  }
}

function setClipboardText(text) {
  try {
    execSync('termux-clipboard-set', { input: text });
  } catch (e) {
    throw new Error(`Failed to set text: ${e.message}`);
  }
}

function clearClipboard() {
  try {
    execSync('termux-clipboard-set', { input: '' });
  } catch (e) {
    throw new Error(`Failed to clear clipboard: ${e.message}`);
  }
}

function isWaylandClipboardAvailable() {
  return false;
}

module.exports = {
  ClipboardManager,
  ClipboardListener,
  getClipboardText,
  setClipboardText,
  clearClipboard,
  isWaylandClipboardAvailable
};
AIDX
    fi
fi

npm install @teddyzhu/clipboard --ignore-scripts 2>/dev/null || true
[ -f "clipboard/index.cjs" ] && print_success "Clipboard wrapper installed" || print_warning "Clipboard wrapper not found"

print_step "Step 10/11: Symlinking compiled binaries to prebuilds directory"

mkdir -p "prebuilds/$ANDROID_ARCH"
KEYTAR_PATH="$INSTALL_ROOT/node_modules/keytar/build/Release/keytar.node"
PTY_PATH="$INSTALL_ROOT/node_modules/node-pty/build/Release/pty.node"

# keytar.node is not compiled (no libsecret-1 in Termux) — bypass hook handles it
[ -f "$KEYTAR_PATH" ] && ln -sf "$KEYTAR_PATH" "prebuilds/$ANDROID_ARCH/keytar.node" && print_success "keytar.node symlinked" || print_info "keytar.node not compiled — JS bypass will be used instead"
[ -f "$PTY_PATH" ] && ln -sf "$PTY_PATH" "prebuilds/$ANDROID_ARCH/pty.node" && print_success "pty.node symlinked" || { print_error "pty.node not found"; exit 1; }

print_step "Step 11/11: Verifying installation"

cat > test-native-modules-install.mjs << 'TESTEOF'
import { createRequire } from 'module';
const require = createRequire(import.meta.url);

let passed = 0;
let failed = 0;

console.log("\nTesting native modules...\n");

// Test keytar
try {
  const keytar = require('keytar');
  console.log("✓ keytar loaded successfully");
  passed++;
} catch (e) {
  console.log("✗ keytar failed:", e.message);
  failed++;
}

// Test node-pty
try {
  const pty = require('node-pty');
  console.log("✓ node-pty loaded successfully");
  passed++;
} catch (e) {
  console.log("✗ node-pty failed:", e.message);
  failed++;
}

// Test sharp
try {
  const sharp = require('sharp');
  console.log("✓ sharp loaded successfully");
  passed++;
} catch (e) {
  console.log("✗ sharp failed:", e.message);
  failed++;
}

// Test clipboard (check if wrapper exists)
try {
  const fs = require('fs');
  if (fs.existsSync('./clipboard/index.cjs')) {
    console.log("✓ clipboard wrapper available");
    passed++;
  } else {
    console.log("⚠ clipboard wrapper not found");
    failed++;
  }
} catch (e) {
  console.log("✗ clipboard check failed:", e.message);
  failed++;
}

console.log(`\nResults: ${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
TESTEOF

node test-native-modules-install.mjs && print_success "All module tests passed!" || print_warning "Some modules failed to load"
rm -f test-native-modules-install.mjs

print_header "Installation Summary"

echo "Installed Packages:"
echo "  • nodejs, clang, make, python"
echo "  • glib, xorgproto, rust, libvips, pkg-config"
echo "  • ripgrep, termux-api"
echo ""
echo "Native Modules Built:"
echo "  • node-pty (terminal/command execution) — compiled native"
echo "  • sharp (image processing) — compiled native"
echo "  • keytar (credential storage) — JS file-based bypass (no libsecret needed)"
echo "  • clipboard wrapper (Termux API integration)"
echo ""
echo "Modified Files:"
echo "  • ~/.gyp/include.gypi (node-gyp config)"
echo "  • Patched node-addon-api enum handling"
echo "  • Created clipboard/index.cjs and clipboard/android-impl.cjs"
echo "  • ~/.copilot-hooks/keytar-bypass.js (credential store bypass)"
echo "  • Symlinked prebuilds/$ANDROID_ARCH/pty.node"
echo "  • Symlinked ripgrep to Copilot expected path"
echo ""

print_header "Installation Complete!"

echo "GitHub Copilot CLI is ready on Android/Termux ($ANDROID_ARCH)"
echo ""
echo "Next steps:"
echo "  1. Reload your shell config: source ~/.bash_profile"
echo "  2. Launch Copilot: copilot"
echo "  3. Sign in: /login"
echo "  4. Start coding with AI assistance!"
echo ""

print_success "Setup completed successfully!"

exit 0
