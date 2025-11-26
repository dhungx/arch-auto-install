#!/usr/bin/env bash
set -euo pipefail

# Hyprland Configuration Fix Script
# Fixes common errors in hyprcolors.conf and related config files

RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[1;33m'
BLUE=$'\e[1;34m'
MAGENTA=$'\e[0;35m'
NC=$'\e[0m'

info(){ printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn(){ printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error(){ printf '%b\n' "${RED}[✗]${NC} $*"; exit 1; }

# Function to convert RGB to hex format
# Input: rgb(166, 227, 161) or similar
# Output: 0xa6e3a1
rgb_to_hex() {
    local rgb_str="$1"
    
    # Extract RGB values using regex
    if [[ $rgb_str =~ rgb\(([[:space:]]*[0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*\) ]]; then
        local r=${BASH_REMATCH[1]##*( )}  # Remove leading spaces
        local g=${BASH_REMATCH[2]##*( )}  # Remove leading spaces
        local b=${BASH_REMATCH[3]##*( )}  # Remove leading spaces
        
        # Convert to hex and combine
        printf '0x%02x%02x%02x' "$r" "$g" "$b"
        return 0
    fi
    
    return 1
}

HYPR_CONFIG="/home/${SUDO_USER:-(whoami)}/.config/hypr"
HYPR_COLORS="$HYPR_CONFIG/hyprcolors.conf"
HYPR_MAIN="$HYPR_CONFIG/hyprland.conf"

[[ -d "$HYPR_CONFIG" ]] || error "Hyprland config directory not found at $HYPR_CONFIG"

info "Hyprland Configuration Fix Script"
info "Config directory: $HYPR_CONFIG"

# Function to fix color variable definitions
fix_color_variables() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found: $file - skipping color variable fixes"
        return
    fi
    
    info "Fixing color variables in $file..."
    
    # Create backup
    cp "$file" "$file.bak.$(date +%s)" || warn "Could not create backup of $file"
    
    # Fix: Ensure color variables use hex values without extra quotes
    # Pattern: $color1, $color2, etc. should be defined as RGB or RGBA hex
    sed -i 's/\$color\([0-9]\+\)\s*=\s*"\([^"]*\)"/\$color\1 = \2/g' "$file"
    sed -i "s/\$color\([0-9]\+\)\s*=\s*'\([^']*\)'/\$color\1 = \2/g" "$file"
    
    info "✓ Color variable syntax fixed"
}

# Function to fix gradient parsing errors
fix_gradient_errors() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found: $file - skipping gradient fixes"
        return
    fi
    
    info "Fixing gradient parsing errors in $file..."
    
    # Fix: Replace invalid gradient syntax with valid color references
    # Invalid: $color1 (without proper hex format)
    # Valid: 0xRRGGBB format or variables must be pre-defined
    
    # Ensure all color variables are properly expanded before gradients
    # This involves ensuring variables are defined before being used in gradients
    
    # Add default color definitions if missing
    if ! grep -Eq '^\s*\$color' "$file"; then
        warn "No color variables found in $file - adding defaults..."
        cat > "$file.colors.tmp" <<'COLORS'
# Default color scheme - Catppuccin Mocha
$color0 = 0x1e1e2e
$color1 = 0xa6e3a1
$color2 = 0xf5e0dc
$color3 = 0xf38ba8
$color4 = 0x89dceb
$color5 = 0xcba6f7
$color6 = 0x94e2d5
$color7 = 0xbac2de
$color8 = 0x45475a
$color9 = 0xa6e3a1
$color10 = 0xf5e0dc
$color11 = 0xf38ba8
$color12 = 0x89dceb
$color13 = 0xcba6f7
$color14 = 0x94e2d5
$color15 = 0xa6adc8

COLORS
        # Merge with existing file (keep existing colors, add missing)
        {
            cat "$file.colors.tmp"
            grep -v '^\s*\$color' "$file" || true
        } > "$file.new"
        mv "$file.new" "$file"
        rm -f "$file.colors.tmp"
    fi
    
    # Validate gradient syntax: gradient = $colorX $colorY
    # Both colors must be defined
    local tmpfile=$(mktemp)
    local gradients_fixed=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check for gradient definitions
        if [[ "$line" =~ gradient[[:space:]]*=[[:space:]]*.*\$ ]]; then
            # Extract color variables from gradient
            local color_vars
            color_vars=$(echo "$line" | grep -oE '\$color[0-9]+' || true)
            
            if [[ -n "$color_vars" ]]; then
                # Check if all referenced colors are defined in the file
                local all_valid=1
                while read -r color_var; do
                    if ! grep -Eq "^\s*${color_var}\s*=" "$file"; then
                        warn "Gradient references undefined color: $color_var"
                        all_valid=0
                    fi
                done <<< "$color_vars"
                
                if (( all_valid == 1 )); then
                    echo "$line" >> "$tmpfile"
                else
                    echo "# [FIXED - invalid gradient] $line" >> "$tmpfile"
                    ((gradients_fixed++))
                fi
            else
                echo "$line" >> "$tmpfile"
            fi
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$file"
    
    if (( gradients_fixed > 0 )); then
        mv "$tmpfile" "$file"
        info "✓ Fixed $gradients_fixed invalid gradients"
    else
        rm -f "$tmpfile"
        info "✓ Gradient syntax validated"
    fi
}

# Function to fix globbing errors in source commands
fix_source_globbing() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found: $file - skipping source fixes"
        return
    fi
    
    info "Fixing source globbing errors in $file..."
    
    # Fix: Comment out or fix broken source= statements with glob patterns
    # The error "globbing error: found no match" means the file pattern doesn't exist
    
    # Create temporary file for fixes
    local tmpfile=$(mktemp)
    local fixed=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if line has source= with glob patterns
        if [[ "$line" =~ source[[:space:]]*=[[:space:]]*.*\* ]]; then
            # Extract the path and trim whitespace
            local source_path=$(echo "$line" | sed 's/.*source\s*=\s*//;s/[[:space:]]*#.*//' | xargs)
            
            # Check if it's a glob pattern and if files exist
            if [[ "$source_path" == *'*'* ]]; then
                # Try to expand glob
                local expanded
                expanded=$(eval echo "$source_path" 2>/dev/null || echo "")
                
                if [[ -z "$expanded" || "$expanded" == "$source_path" ]]; then
                    # No matches - comment out the line
                    echo "# [FIXED - no glob match] $line" >> "$tmpfile"
                    ((fixed++))
                else
                    # Glob expanded successfully
                    echo "$line" >> "$tmpfile"
                fi
            else
                echo "$line" >> "$tmpfile"
            fi
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$file"
    
    if (( fixed > 0 )); then
        mv "$tmpfile" "$file"
        info "✓ Fixed $fixed globbing errors"
    else
        rm -f "$tmpfile"
        info "✓ No globbing errors found"
    fi
}

# Function to validate color format and fix parsing
validate_and_fix_colors() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found: $file - skipping validation"
        return
    fi
    
    info "Validating color formats in $file..."
    
    local tmpfile=$(mktemp)
    local fixed=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check for color variable assignments
        if [[ "$line" =~ \$color[0-9]+ ]]; then
            # Ensure the value is in correct hex format (0xRRGGBB or #RRGGBB)
            if [[ "$line" =~ =[[:space:]]*([^#]+) ]]; then
                local value="${BASH_REMATCH[1]}"
                value=$(echo "$value" | sed 's/[[:space:]]*#.*//')  # Remove comments
                value=$(echo "$value" | xargs)  # Trim whitespace
                
                # Check if value is valid color
                if [[ ! "$value" =~ ^0x[0-9a-fA-F]{6}$ ]] && [[ ! "$value" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    # Try to convert RGB/HSV to hex or mark as default
                    local var_name=$(echo "$line" | sed 's/=.*//' | xargs)
                    if [[ "$value" == "rgb"* ]]; then
                        # Try to convert RGB to hex
                        local hex_value
                        if hex_value=$(rgb_to_hex "$value" 2>/dev/null); then
                            info "Converted $var_name from RGB to hex: $hex_value"
                            echo "$var_name = $hex_value" >> "$tmpfile"
                            ((fixed++))
                        else
                            warn "Cannot auto-convert $var_name from RGB format - keeping as is"
                            echo "$line" >> "$tmpfile"
                        fi
                    else
                        warn "Invalid color format in: $line - using fallback"
                        echo "$line" >> "$tmpfile"
                    fi
                else
                    echo "$line" >> "$tmpfile"
                fi
            else
                echo "$line" >> "$tmpfile"
            fi
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$file"
    
    mv "$tmpfile" "$file"
    info "✓ Color validation complete"
}

# Function to generate valid hyprcolors.conf if missing
generate_default_hyprcolors() {
    local file="$1"
    
    info "Generating default hyprcolors.conf..."
    
    cat > "$file" <<'EOF'
# Hyprland Colors Configuration (Catppuccin Mocha)
# Color definitions for use in hyprland.conf

# Primary colors (0-7)
$color0 = 0x1e1e2e   # Base color
$color1 = 0xa6e3a1   # Green
$color2 = 0xf5e0dc   # Peach
$color3 = 0xf38ba8   # Red/Pink
$color4 = 0x89dceb   # Blue
$color5 = 0xcba6f7   # Mauve
$color6 = 0x94e2d5   # Teal
$color7 = 0xbac2de   # Lavender

# Bright colors (8-15)
$color8 = 0x45475a   # Surface 0
$color9 = 0xa6e3a1   # Bright Green
$color10 = 0xf5e0dc  # Bright Peach
$color11 = 0xf38ba8  # Bright Pink
$color12 = 0x89dceb  # Bright Blue
$color13 = 0xcba6f7  # Bright Mauve
$color14 = 0x94e2d5  # Bright Teal
$color15 = 0xa6adc8  # Bright Lavender

# Named color variables for easy theming
$background = 0x1e1e2e
$foreground = 0xcdd6f4
$cursor_color = 0xf5e0dc
$accent = 0x89dceb
EOF
    
    info "✓ Default hyprcolors.conf created"
}

# Function to check and fix hyprland.conf references
fix_hyprland_conf_references() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found: $file - skipping reference fixes"
        return
    fi
    
    info "Checking hyprland.conf for broken references..."
    
    # Check if hyprcolors.conf is sourced
    if ! grep -q "source.*hyprcolors" "$file"; then
        warn "hyprcolors.conf not sourced in hyprland.conf - adding reference..."
        echo "" >> "$file"
        echo "# Source color definitions" >> "$file"
        echo "source = ~/.config/hypr/hyprcolors.conf" >> "$file"
        info "✓ Added hyprcolors.conf source"
    fi
}

# Main execution
main() {
    echo -e "${MAGENTA}╔════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║   Hyprland Configuration Fix Script    ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check if running as root for proper permissions
    if [[ $EUID -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            info "Running as root (sudo) for user: $SUDO_USER"
            HYPR_CONFIG="/home/$SUDO_USER/.config/hypr"
            HYPR_COLORS="$HYPR_CONFIG/hyprcolors.conf"
            HYPR_MAIN="$HYPR_CONFIG/hyprland.conf"
        fi
    fi
    
    # Verify config directory exists
    if [[ ! -d "$HYPR_CONFIG" ]]; then
        error "Hyprland config directory not found at $HYPR_CONFIG"
    fi
    
    info "Working directory: $HYPR_CONFIG"
    
    # If hyprcolors.conf doesn't exist, generate it
    if [[ ! -f "$HYPR_COLORS" ]]; then
        warn "hyprcolors.conf not found - generating default..."
        generate_default_hyprcolors "$HYPR_COLORS"
    fi
    
    # Run fixes
    fix_source_globbing "$HYPR_COLORS"
    fix_color_variables "$HYPR_COLORS"
    fix_gradient_errors "$HYPR_COLORS"
    validate_and_fix_colors "$HYPR_COLORS"
    fix_hyprland_conf_references "$HYPR_MAIN"
    
    echo ""
    echo -e "${GREEN}✓ Hyprland configuration fixes complete${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Review the fixed configuration: nano $HYPR_COLORS"
    echo "2. Check main config: nano $HYPR_MAIN"
    echo "3. Reload Hyprland: Super+Alt+R or restart session"
    echo ""
    echo -e "${YELLOW}Backup files:${NC}"
    echo "Configuration backups saved with .bak.TIMESTAMP extension"
    echo ""
}

# Run main function
main "$@"
