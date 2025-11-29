#!/bin/sh

#=====================================
# MEMORY USAGE REPORT
#=====================================
# Displays consolidated memory usage by application
# Usage: ./mem_usage_report.sh [option]

# Force C locale for consistent number formatting (period as decimal separator)
LC_NUMERIC=C
export LC_NUMERIC

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# Box drawing characters
BOX_H="─"
BOX_V="│"
BOX_TL="┌"
BOX_TR="┐"
BOX_BL="└"
BOX_BR="┘"
BOX_LT="├"
BOX_RT="┤"
BOX_TT="┬"
BOX_BT="┴"
BOX_X="┼"

# Help function
show_help() {
    printf "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║${NC}  ${WHITE}Memory Usage Report${NC}                                        ${CYAN}║${NC}\n"
    printf "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "${YELLOW}USAGE:${NC}  $0 [option]\n"
    printf "\n"
    printf "${YELLOW}OPTIONS:${NC}\n"
    printf "  ${GREEN}(none)${NC}     Display memory usage statistics (Interactive TUI)\n"
    printf "  ${GREEN}print${NC}      Print memory usage statistics to stdout\n"
    printf "  ${GREEN}kill${NC}       Trigger the OOM killer manually\n"
    printf "  ${GREEN}help${NC}       Display this help message\n"
    printf "\n"
}

# Core Logic Function
generate_report() {
    # Get total and used memory in MiB from `free`
    mem_info=$(free -m | awk '/^Mem:/ { print $2, $3, $4, $6, $7 }')
    total_mem=$(echo "$mem_info" | cut -d' ' -f1)
    used_mem=$(echo "$mem_info" | cut -d' ' -f2)
    free_mem=$(echo "$mem_info" | cut -d' ' -f3)
    buff_cache=$(echo "$mem_info" | cut -d' ' -f4)
    available_mem=$(echo "$mem_info" | cut -d' ' -f5)

    # Get swap info
    swap_info=$(free -m | awk '/^Swap:/ { print $2, $3 }')
    swap_total=$(echo "$swap_info" | cut -d' ' -f1)
    swap_used=$(echo "$swap_info" | cut -d' ' -f2)

    # Get process information and consolidate memory usage
    app_data=$(ps -e -o pmem=,args= | awk '
    {
        usage = $1
        cmd = $0
        sub(/^[0-9.-]+ +/, "", cmd)

        split(cmd, parts, " ")
        app_path = parts[1]
        sub(/.*\\/, "", app_path)
        app_name = app_path

        # Heuristics to group related processes under a common name
        if (cmd ~ /brave/) {
            app_name = "Brave Browser"
        } else if (cmd ~ /claude/) {
            app_name = "Claude Code"
        } else if (cmd ~ /code/ || cmd ~ /Code/) {
            app_name = "VS Code"
        } else if (cmd ~ /gemini/) {
            app_name = "Gemini CLI"
        } else if (cmd ~ /plasmashell/) {
            app_name = "KDE Plasma Shell"
        } else if (cmd ~ /kwin/) {
            app_name = "KWin (Window Manager)"
        } else if (cmd ~ /kded/) {
            app_name = "KDE Services (kded)"
        } else if (cmd ~ /krunner/) {
            app_name = "KRunner"
        } else if (cmd ~ /Xorg/ || cmd ~ /xorg/) {
            app_name = "Xorg (Display Server)"
        } else if (cmd ~ /konsole/) {
            app_name = "Konsole"
        } else if (cmd ~ /dolphin/) {
            app_name = "Dolphin"
        } else if (cmd ~ /live-server/) {
            app_name = "Live Server"
        } else if (cmd ~ /firefox/) {
            app_name = "Firefox"
        } else if (cmd ~ /chrome/ || cmd ~ /chromium/) {
            app_name = "Chrome/Chromium"
        } else if (cmd ~ /electron/) {
            app_name = "Electron App"
        } else if (cmd ~ /obsidian/) {
            app_name = "Obsidian"
        } else if (cmd ~ /slack/) {
            app_name = "Slack"
        } else if (cmd ~ /discord/) {
            app_name = "Discord"
        } else if (cmd ~ /spotify/) {
            app_name = "Spotify"
        } else if (cmd ~ /docker/) {
            app_name = "Docker"
        } else if (cmd ~ /mysql/ || cmd ~ /mariadb/) {
            app_name = "MySQL/MariaDB"
        } else if (cmd ~ /postgres/) {
            app_name = "PostgreSQL"
        } else if (cmd ~ /mongo/) {
            app_name = "MongoDB"
        } else if (cmd ~ /redis/) {
            app_name = "Redis"
        } else if (cmd ~ /nginx/) {
            app_name = "Nginx"
        } else if (cmd ~ /apache/) {
            app_name = "Apache"
        } else if (cmd ~ /node/) {
            app_name = "Node.js"
        } else if (cmd ~ /python/) {
            app_name = "Python"
        } else if (cmd ~ /java/) {
            app_name = "Java"
        } else if (cmd ~ /rust/) {
            app_name = "Rust"
        } else if (cmd ~ /go/) {
            app_name = "Go"
        }

        app[app_name] += usage
        count[app_name] += 1
    }
    END {
        for (a in app) {
            print app[a], count[a], a
        }
    }')

    # Calculate totals
    total_app_usage=$(echo "$app_data" | awk '{sum += $1} END {print sum}')
    total_used_percent=$(awk -v used="$used_mem" -v total="$total_mem" 'BEGIN {printf "%.2f", (used/total)*100}')
    system_usage=$(awk -v total_used="$total_used_percent" -v app_used="$total_app_usage" 'BEGIN {printf "%.2f", total_used - app_used}')

    # Combine data and sort - filter out unnamed entries and those with <0.5% usage
    combined_data=$( (echo "$app_data"; echo "$system_usage 1 System (Kernel, Buffers, Cache)") | sort -rn | awk '$1 >= 0.5 && $3 !~ /^[0-9.]+$/ {print}')

    # Count total processes
    total_procs=$(echo "$app_data" | awk '{sum += $2} END {print sum}')

    # Print header
    printf "\n"
    printf "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║${NC}  ${WHITE}📊 MEMORY USAGE REPORT${NC}%64s${CYAN}║${NC}\n" ""
    printf "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"

    # Memory overview bar
    used_percent_int=$(printf "%.0f" "$total_used_percent")
    bar_width=50
    filled=$((used_percent_int * bar_width / 100))
    empty=$((bar_width - filled))

    printf "${WHITE}  RAM Usage:${NC} "
    printf "${BLUE}["
    i=0
    while [ $i -lt $filled ]; do
        if [ $i -lt $((filled / 3)) ]; then
            printf "${GREEN}█"
        elif [ $i -lt $((filled * 2 / 3)) ]; then
            printf "${YELLOW}█"
        else
            printf "${RED}█"
        fi
        i=$((i + 1))
    done
    i=0
    while [ $i -lt $empty ]; do
        printf "${GRAY}░"
        i=$((i + 1))
    done
    printf "${BLUE}]${NC} "
    printf "${WHITE}%.1f%%${NC}\n" "$total_used_percent"

    # Swap bar (if swap exists)
    if [ "$swap_total" -gt 0 ]; then
        swap_percent=$(awk -v used="$swap_used" -v total="$swap_total" 'BEGIN {printf "%.1f", (used/total)*100}')
        swap_percent_int=$(printf "%.0f" "$swap_percent")
        filled=$((swap_percent_int * bar_width / 100))
        empty=$((bar_width - filled))

        printf "${WHITE}  Swap:${NC}      "
        printf "${BLUE}["
        i=0
        while [ $i -lt $filled ]; do
            printf "${MAGENTA}█"
            i=$((i + 1))
        done
        i=0
        while [ $i -lt $empty ]; do
            printf "${GRAY}░"
            i=$((i + 1))
        done
        printf "${BLUE}]${NC} "
        printf "${WHITE}%.1f%%${NC}\n" "$swap_percent"
    fi

    printf "\n"

    # Memory stats box
    printf "${BLUE}┌─────────────────────────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${BLUE}│${NC} ${CYAN}Total RAM:${NC} ${WHITE}%6d MiB${NC}  ${GRAY}│${NC}  ${CYAN}Used:${NC} ${YELLOW}%6d MiB${NC}  ${GRAY}│${NC}  ${CYAN}Available:${NC} ${GREEN}%6d MiB${NC}          ${BLUE}│${NC}\n" "$total_mem" "$used_mem" "$available_mem"
    printf "${BLUE}│${NC} ${CYAN}Buff/Cache:${NC} ${WHITE}%5d MiB${NC}  ${GRAY}│${NC}  ${CYAN}Free:${NC} ${WHITE}%6d MiB${NC}  ${GRAY}│${NC}  ${CYAN}Swap:${NC} ${WHITE}%6d${NC}/${WHITE}%d MiB${NC}          ${BLUE}│${NC}\n" "$buff_cache" "$free_mem" "$swap_used" "$swap_total"
    printf "${BLUE}└─────────────────────────────────────────────────────────────────────────────────┘${NC}\n"
    printf "\n"

    # Usage breakdown
    printf "${WHITE}  System:${NC} ${MAGENTA}%.1f%%${NC}  ${GRAY}+${NC}  ${WHITE}User Apps:${NC} ${CYAN}%.1f%%${NC}  ${GRAY}=${NC}  ${WHITE}Total:${NC} ${YELLOW}%.1f%%${NC}  ${GRAY}(%d processes)${NC}\n\n" "$system_usage" "$total_app_usage" "$total_used_percent" "$total_procs"

    # Table header
    printf "${BLUE}┌────────────────────────────────┬────────────┬────────────┬────────────┬──────────┐${NC}\n"
    printf "${BLUE}│${NC} ${WHITE}%-30s${NC} ${BLUE}│${NC} ${WHITE}%10s${NC} ${BLUE}│${NC} ${WHITE}%10s${NC} ${BLUE}│${NC} ${WHITE}%10s${NC} ${BLUE}│${NC} ${WHITE}%8s${NC} ${BLUE}│${NC}\n" "Application" "Usage (%)" "Memory" "Cumulative" "Procs"
    printf "${BLUE}├────────────────────────────────┼────────────┼────────────┼────────────┼──────────┤${NC}\n"

    # Table rows
    echo "$combined_data" | awk \
    -v total_mem="$total_mem" \
    -v BLUE="\033[0;34m" \
    -v GREEN="\033[0;32m" \
    -v YELLOW="\033[1;33m" \
    -v RED="\033[0;31m" \
    -v CYAN="\033[0;36m" \
    -v MAGENTA="\033[0;35m" \
    -v WHITE="\033[1;37m" \
    -v GRAY="\033[0;90m" \
    -v NC="\033[0m" '
    BEGIN {
        cumulative = 0
        rank = 1
    }
    {
        usage = $1
        proc_count = $2
        app_name = $3
        for (i = 4; i <= NF; i++) {
            app_name = app_name " " $i
        }

        cumulative += usage
        mem_mib = (usage / 100) * total_mem

        if (mem_mib >= 1024) {
            mem_str = sprintf("%.1f GiB", mem_mib / 1024)
        } else {
            mem_str = sprintf("%.0f MiB", mem_mib)
        }

        # Color based on usage
        if (usage >= 10) {
            color = RED
        } else if (usage >= 5) {
            color = YELLOW
        } else if (usage >= 1) {
            color = CYAN
        } else {
            color = GRAY
        }

        # Highlight system row
        if (app_name ~ /System/) {
            color = MAGENTA
        }

        printf "%s│%s %-30s %s│%s %10.2f %s│%s %10s %s│%s %10.2f %s│%s %8d %s│%s\n", \
            BLUE, color, app_name, BLUE, color, usage, BLUE, WHITE, mem_str, BLUE, WHITE, cumulative, BLUE, GRAY, proc_count, BLUE, NC

        rank++
    }'

    printf "${BLUE}└────────────────────────────────┴────────────┴────────────┴────────────┴──────────┘${NC}\n"
    printf "\n"

    # OOM Status section
    printf "${CYAN}┌─────────────────────────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${CYAN}│${NC}  ${WHITE}🛡️  OOM Protection Status${NC}%55s${CYAN}│${NC}\n" ""
    printf "${CYAN}├─────────────────────────────────────────────────────────────────────────────────┤${NC}\n"

    # Check panic_on_oom
    panic_oom=$(cat /proc/sys/vm/panic_on_oom 2>/dev/null)
    if [ "$panic_oom" = "0" ]; then
        printf "${CYAN}│${NC}  ${GREEN}●${NC} panic_on_oom: ${WHITE}%-3s${NC} (OOM killer enabled)%37s${CYAN}│${NC}\n" "$panic_oom" ""
    else
        printf "${CYAN}│${NC}  ${RED}●${NC} panic_on_oom: ${WHITE}%-3s${NC} (System will panic on OOM)%33s${CYAN}│${NC}\n" "$panic_oom" ""
    fi

    # Check systemd-oomd
    oomd_status=$(systemctl is-active systemd-oomd 2>/dev/null)
    if [ "$oomd_status" = "active" ]; then
        printf "${CYAN}│${NC}  ${GREEN}●${NC} systemd-oomd: ${GREEN}%-8s${NC}%55s${CYAN}│${NC}\n" "active" ""
    else
        printf "${CYAN}│${NC}  ${YELLOW}●${NC} systemd-oomd: ${GRAY}%-8s${NC}%55s${CYAN}│${NC}\n" "${oomd_status:-inactive}" ""
    fi

    printf "${CYAN}└─────────────────────────────────────────────────────────────────────────────────┘${NC}\n"
    printf "\n"

    # Funny message about mouseless terminal/Vim
    printf "${GRAY}  Pure power, no clicks needed (cat certainly agrees).${NC}\n"
    printf "\n"
    printf "${WHITE}               ·◎◎○··                                                           ${NC}\n"
    printf "${WHITE}                ○●◉◉◎◎·                                                         ${NC}\n"
    printf "${WHITE}                ·◉●●●●◉                                                         ${NC}\n"
    printf "${WHITE}                ○●●●●●○                                                         ${NC}\n"
    printf "${WHITE}              ·◎●●●●●◎·                 ·· ···○◎○○·                             ${NC}\n"
    printf "${WHITE}             ○●●●●●◉○                ○○○○◎◉◉●●◎◎◎·                              ${NC}\n"
    printf "${WHITE}           ·◎●●◉●●◉○             ·◎◉◎◎◎○◉●●◉◎◎○◎  ··                            ${NC}\n"
    printf "${WHITE}          ○◉●●●●◉◎·             ○◉◎◎◎○○◎◉◎◉◎○○○◎···                             ${NC}\n"
    printf "${WHITE}        ·◎●●●◉●◉○·            ·◎◉◎○○◎◎◎◎○○◎◎◎○○○◎·  ·                           ${NC}\n"
    printf "${WHITE}       ○◉◉◉●●●◉○             ◎◉◎○○○○◎◎◎○◎◎◎◎○◎◎◎○○○··                           ${NC}\n"
    printf "${WHITE}      ·●●●●●●◉○             ○◎◎◎◎◎○◎○◎◎◎◎◎◎○◎●●◎◎                               ${NC}\n"
    printf "${WHITE}     ·◉●●●●●◉○           ·○○◎○○◎◎◎◎◎◎◎○○◎◎○○○○○○◎                               ${NC}\n"
    printf "${WHITE}    ·◉●◉●●●◎··    ···◎◎○○◎◎◎◎◎○◎◎◎◎◎◉◉◎◉●●◉◎◎◎◎◎◎·                              ${NC}\n"
    printf "${WHITE}    ○●●●●●◉·    ○◉◎◎◎◎◎◎◎○◎◎○◎◎◎◎◎◎◎◎◎◉◎◎◎◎◎◎◎◎○ ·○○                            ${NC}\n"
    printf "${WHITE}   ·◉●●●●●○   ○◎◉◎◎◎◎◎○○◎◎◎◎○○◎◎◎◎◎◎◎◎○○·      ◎○  · ·                          ${NC}\n"
    printf "${WHITE}   ○◉●●●●◎·  ◎◉◎○○◎◎◎◎◎◎◎◎◎◎◎◎◎◎○◎◎◎◎◎◎○◎○     ◎·○   ··                         ${NC}\n"
    printf "${WHITE}   ◉●●●●●◎ ·◉◉◎◎◎◎◎◎◎○◎◎◎○◎◎◎◎◎◎◎◎◎◎○◎○◎◉·     ·                                ${NC}\n"
    printf "${WHITE}   ◉●●●◉●○ ◎●◎◎◎◎◎◎◉◎◎◎◎◎◎◎○◎◎◎◎◎◎◎◎◎○◎●◎·                                      ${NC}\n"
    printf "${WHITE}   ◉●●●●●◎◎◉◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎○◎◎◎◎◎○◎○◎◉◉●·                                       ${NC}\n"
    printf "${WHITE}   ◉●●●●●◉◎◎◎◎◎◎◎◎◎◎◎◎◎◎○○◎○◎◎◎◎◎◎◎◎◉●●◉◎○○○○○○○                                ${NC}\n"
    printf "${WHITE}   ◎◉●●●●◉◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◉◎◎◎◎◎◎◎○◎●●●◉●●●●●●●●◎·                              ${NC}\n"
    printf "${WHITE}   ·◉●●●●◉◎◎◎◎◎◎◎◎◎◎◎◎○○◉◉◉◎○○◎◎◎◎◎●●●●●◉◉●●●●●●◎◎○○·                           ${NC}\n"
    printf "${WHITE}    ◉◉●●●◉○◎◎◎◎◎◎◎◎◎◎○◎◎◎○◉◉◎○○◎◎◎◎◎◎··········◉◎◉◉◉○·                          ${NC}\n"
    printf "${WHITE}    ○●●●●◉◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◉●●◎○◎◎○○◎·            ○○○·                           ${NC}\n"
    printf "${WHITE}     ◎●●●●◉◎○◎○◎○◎◎○◎◉◎◎◎○◎○◉●◎○◎○◎◎○                                           ${NC}\n"
    printf "${WHITE}      ◉◉●●●◎○○○◎○◎◎◎◎○○○◎◎○○◎●●○○◎◎◎◎·             ···  ·○○·                    ${NC}\n"
    printf "${WHITE}      ·◎◉●●●◎○○◎○◎◎◎◎○◎◎◎◎○◎◉●●●○○◎◎◎○               ◎●◉◉○◉●○◎◉●◉●◎○○           ${NC}\n"
    printf "${WHITE}        ◎◉◎◎○◎◎○○◎◎◎◎◎◎◎○○◎◎●●●●●○○◎◎◎·            ···◎●●◉◉●●●●●●●●●●◉·         ${NC}\n"
    printf "${WHITE}        ·◉◉◎○○○◎○○◎◎◎◎◎○◎◉◉●●●●●●●◎○○○○·                ◎●●●●●●●●●●●●●●◎○○◎·    ${NC}\n"
    printf "${WHITE}         ○◎●◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◎◉◉◉◎◎◎◎◉○              ·◉◉●●●●●●●●●●●◉···○◎○·  ${NC}\n"
    printf "${WHITE}      ·····○○○○○○○○○○◎○○○○○○○○○○○○○◎◎○○○◎·· ··         ·◎· ·○◎◎◎◎◎◎◎◎◎···· ○◉○  ${NC}\n"
    printf "${WHITE}                                                           ··○○○○○○○○○○○○○○·    ${NC}\n"
    printf "\n"
}

# TUI Loop Function
tui_mode() {
    # Hide cursor
    printf "\033[?25l"
    
    # Restore cursor on exit
    trap 'printf "\033[?25h"; exit 0' INT TERM EXIT

    while true; do
        clear
        generate_report
        
        # Footer Controls
        printf "${CYAN}┌─────────────────────────────────────────────────────────────────────────────────┐${NC}\n"
        printf "${CYAN}│${NC}  ${WHITE}CONTROLS:${NC}   ${GREEN}[ r ]${NC} Refresh Report    ${RED}[ q ]${NC} Quit Program                           ${CYAN}│${NC}\n"
        printf "${CYAN}└─────────────────────────────────────────────────────────────────────────────────┘${NC}\n"
        
        # Read single key
        old_tty=$(stty -g)
        stty -icanon -echo min 1 time 0
        key=$(dd bs=1 count=1 2>/dev/null)
        stty "$old_tty"

        case "$key" in
            q|Q)
                break
                ;;
            r|R)
                continue
                ;;
        esac
    done
}

# Main execution
case "$1" in
    help|-h|--help)
        show_help
        ;;
    print)
        generate_report
        ;;
    kill)
        printf "${RED}⚠ Triggering OOM killer...${NC}\n"
        echo f | sudo tee /proc/sysrq-trigger
        ;;
    *)
        tui_mode
        ;;
esac
