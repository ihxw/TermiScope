import re

with open('scripts/install_agent.sh.tmpl', 'r') as f:
    content = f.read()

old_install_dir = 'INSTALL_DIR="/opt/termiscope/agent"'
new_install_dir = """INSTALL_DIR="/opt/termiscope/agent"
if [ "$OS" != "darwin" ]; then
    for dir in "/opt" "/usr/local" "/var/lib" "/tmp"; do
        if mkdir -p "$dir/termiscope/agent" 2>/dev/null && touch "$dir/termiscope/agent/.test" 2>/dev/null; then
            rm -f "$dir/termiscope/agent/.test"
            INSTALL_DIR="$dir/termiscope/agent"
            break
        fi
    done
fi"""

# Replace only the first occurrence or the global one
content = content.replace(old_install_dir, new_install_dir, 1)

with open('scripts/install_agent.sh.tmpl', 'w') as f:
    f.write(content)

