#!/usr/bin/env python3
"""
Rclone Sync Manager
A comprehensive tool for managing rclone mount and bisync operations
"""

"""
# IMPORTANT: The Shebang is changed to #!/bin/sh for POSIX compatibility.
# If you run this file, please use 'sh rclone_mount.sh' or ensure it has execute permissions.

# ... Header ...
# Script Name:  rclone_mount.sh
# Description:  GUI startup commands
# Author:       Diego
# Date:

#ACTIONS:

# 1.Rclone config menu


#2. Check Status Mount (flags used)
# Mount
# Umount (force)
# Reset (Umount+Mount)

#rclone mount remote:path /local/mountpoint \
#--vfs-cache-mode full \
##--cache-dir', '~/.cache/rclone/
##--poll-interval 60s \
###--tpslimit 10 \
##--vfs-cache-max-age 1h \
##--vfs-cache-max-size 50G \
##--vfs-read-chunk-size 32M \
##--vfs-read-chunk-size-limit off \
#--dir-cache-time 10000h \
#--drive-skip-gdocs \
#--log-level INFO \
##--log-file PATH \
#--daemon \
#--rc


#3. Check If the list of localmoutpoint/folder (s) folders already exists and rclone check
#rclone check /local/path/folder1 remote:path/folder1 --combined -
#rclone bisync /local/path/folder1 remote:path/folder1 --dry-run --verbose

# 4. Bisync it
#rclone bisync /local/path/folder1 remote:path/folder1 --resync --verbose --drive-skip-gdocs --log-level INFO
#rclone bisync /local/path/folder1 remote:path/folder1 --verbose --drive-skip-gdocs --log-level INFO

#rclone bisync remote:path/folder1 /local/mountpoint/folder1 \
#--conflict-resolve path1
#--tpslimit 10 \
#--drive-skip-gdocs \
#--log-level INFO

#rclone bisync remote:path/folder2 /local/mountpoint/folder2 \
#--conflict-resolve path1
#--tpslimit 10 \
#--drive-skip-gdocs \
#--log-level INFO

"""

import os
import sys
import subprocess
import argparse
import json
from pathlib import Path
from typing import List, Dict, Optional, Tuple


class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'


class RcloneManager:
    """Main class for managing rclone operations"""

    def __init__(self):
        self.config_file = Path.home() / '.config' / 'rclone' / 'rclone.conf'
        self.mount_config = Path.home() / '.config' / 'rclone_manager' / 'mounts.json'
        self.mount_config.parent.mkdir(parents=True, exist_ok=True)

        # Default paths - using POSIX compliant methods
        self.user = os.environ.get('USER') or os.environ.get('LOGNAME') or os.getlogin()
        self.default_mount = Path.home() / 'Documents' / 'Gdrive'
        self.log_dir = Path.home() / 'Documents' / 'Gdrive' / 'system' / '.rclone'
        self.default_remote = 'Gdrive'  # Default remote name
        self.default_bisync_base = Path.home() / 'Documents/Gdrive_Syncs'

    def check_rclone_installed(self) -> bool:
        """Check if rclone is installed"""
        try:
            subprocess.run(['rclone', 'version'],
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL,
                         check=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    def run_rclone_config(self) -> None:
        """Open rclone configuration menu"""
        print(f"{Colors.HEADER}Opening rclone configuration...{Colors.ENDC}")
        try:
            subprocess.run(['rclone', 'config'], check=True)
        except subprocess.CalledProcessError as e:
            print(f"{Colors.FAIL}Error running rclone config: {e}{Colors.ENDC}")

    def get_mount_status(self, mountpoint: str) -> Tuple[bool, Optional[str]]:
        """Check if a path is mounted and get mount flags"""
        try:
            result = subprocess.run(['mount'],
                                  capture_output=True,
                                  text=True,
                                  check=True)
            for line in result.stdout.split('\n'):
                if mountpoint in line:
                    return True, line
            return False, None
        except subprocess.CalledProcessError:
            return False, None

    def get_all_mounts(self) -> List[Tuple[str, str]]:
        """Get all current mounts and their mountpoints"""
        mounts = []
        try:
            result = subprocess.run(['mount'],
                                  capture_output=True,
                                  text=True,
                                  check=True)
            for line in result.stdout.split('\n'):
                # Look for rclone mounts (they contain 'rclone' or are fuse mounts)
                if 'rclone' in line.lower() or line.startswith('rclone') or ':' in line:
                    parts = line.split()
                    if len(parts) >= 3 and parts[1] == 'on':
                        # Format: "remote on /path/to/mount type ..."
                        remote = parts[0]
                        mountpoint = parts[2]
                        mounts.append((remote, mountpoint))
            return mounts
        except subprocess.CalledProcessError:
            return []

    def mount_remote(self, remote: str, local_path: str, mode: str = 'daemon') -> bool:
        """
        Mount a remote with predefined options

        Args:
            remote: Remote name and path (e.g., 'gdrive:' or 'gdrive:folder')
            local_path: Local mountpoint path
            mode: 'daemon' (--daemon with &), 'silent' (& only), 'verbose' (foreground)
        """
        # Ensure log directory exists
        self.log_dir.mkdir(parents=True, exist_ok=True)
        log_file = self.log_dir / 'rclone.log'

        # Create mountpoint if it doesn't exist
        mount_path = Path(local_path)
        mount_path.mkdir(parents=True, exist_ok=True)

        # Check if remote is a remote name (e.g., 'gdrive') or includes path
        if ':' not in remote:
            remote = f"{remote}:"

        mount_cmd = [
            'rclone', 'mount', remote,
            str(local_path),
            '--vfs-cache-mode', 'full',
            '--tpslimit', '10',
            '--vfs-cache-max-age', '1h',
            '--vfs-cache-max-size', '50G',
            '--vfs-read-chunk-size', '32M',
            '--vfs-read-chunk-size-limit', 'off',
            '--dir-cache-time', '10000h',
            '--drive-skip-gdocs',
            '--log-level', 'INFO',
            '--rc',
            '--log-file', str(log_file)
        ]

        try:
            print(f"{Colors.OKBLUE}Mounting {remote} to {local_path}...{Colors.ENDC}")
            print(f"{Colors.OKCYAN}Log file: {log_file}{Colors.ENDC}")

            if mode == 'daemon':
                # Mode 1: --daemon with & - Background service, returns terminal immediately
                mount_cmd.append('--daemon')
                print(f"{Colors.OKCYAN}Mode: Daemon (--daemon | Background service | Silent){Colors.ENDC}")
                print(f"{Colors.OKGREEN}Terminal will be returned immediately{Colors.ENDC}")

                # Run with --daemon flag AND as background process
                cmd_str = ' '.join([f"'{arg}'" if ' ' in arg else arg for arg in mount_cmd]) + ' &'
                subprocess.Popen(cmd_str, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                # Give it a moment to start
                import time
                time.sleep(2)

                # Verify mount succeeded
                is_mounted, _ = self.get_mount_status(str(local_path))
                if is_mounted:
                    print(f"{Colors.OKGREEN}✓ Successfully mounted!{Colors.ENDC}")
                    self.save_mount_config(remote, str(local_path))
                    return True
                else:
                    print(f"{Colors.WARNING}Mount process started, verifying...{Colors.ENDC}")
                    self.save_mount_config(remote, str(local_path))
                    print(f"{Colors.WARNING}Check log file if issues occur: {log_file}{Colors.ENDC}")
                    return True

            elif mode == 'silent':
                # Mode 2: & only - Terminal child process, returns terminal immediately
                print(f"{Colors.OKCYAN}Mode: Silent (& | Terminal Child Process){Colors.ENDC}")
                print(f"{Colors.OKGREEN}Terminal will be returned immediately{Colors.ENDC}")

                # Run as background process WITHOUT --daemon
                cmd_str = ' '.join([f"'{arg}'" if ' ' in arg else arg for arg in mount_cmd]) + ' &'
                subprocess.Popen(cmd_str, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                import time
                time.sleep(2)

                is_mounted, _ = self.get_mount_status(str(local_path))
                if is_mounted:
                    print(f"{Colors.OKGREEN}✓ Successfully mounted!{Colors.ENDC}")
                    self.save_mount_config(remote, str(local_path))
                    return True
                else:
                    print(f"{Colors.WARNING}Mount process started in background{Colors.ENDC}")
                    self.save_mount_config(remote, str(local_path))
                    return True

            else:  # verbose
                # Mode 3: No --daemon, no & - Verbose foreground mode
                print(f"{Colors.WARNING}Mode: Verbose (Logs in terminal){Colors.ENDC}")
                print(f"{Colors.WARNING}This will show live output. Press Ctrl+C when done.{Colors.ENDC}")
                print(f"{Colors.WARNING}Terminal will NOT be returned until you stop it.{Colors.ENDC}")
                input(f"\n{Colors.OKGREEN}Press Enter to start mount in verbose mode...{Colors.ENDC}")

                print(f"\n{Colors.HEADER}{'='*60}{Colors.ENDC}")
                print(f"{Colors.HEADER}VERBOSE MODE - Live rclone output below{Colors.ENDC}")
                print(f"{Colors.HEADER}{'='*60}{Colors.ENDC}\n")

                # Run WITHOUT --daemon flag, showing output directly to terminal
                subprocess.run(mount_cmd, check=False)

                print(f"\n{Colors.HEADER}{'='*60}{Colors.ENDC}")
                print(f"{Colors.WARNING}Mount stopped - Returning to menu{Colors.ENDC}")
                print(f"{Colors.HEADER}{'='*60}{Colors.ENDC}")
                return True

        except subprocess.CalledProcessError as e:
            print(f"{Colors.FAIL}Error mounting: {e}{Colors.ENDC}")
            if e.stderr:
                print(f"{Colors.FAIL}{e.stderr}{Colors.ENDC}")
            print(f"{Colors.WARNING}Check log file: {log_file}{Colors.ENDC}")
            return False
        except KeyboardInterrupt:
            print(f"\n{Colors.WARNING}Mount interrupted by user - Returning to menu{Colors.ENDC}")
            return True

    def umount_remote(self, local_path: str, force: bool = False) -> bool:
        """Unmount a mounted remote"""
        try:
            if force:
                print(f"{Colors.WARNING}Force unmounting {local_path}...{Colors.ENDC}")
                subprocess.run(['fusermount', '-uz', local_path], check=True)
            else:
                print(f"{Colors.OKBLUE}Unmounting {local_path}...{Colors.ENDC}")
                subprocess.run(['fusermount', '-u', local_path], check=True)

            print(f"{Colors.OKGREEN}Successfully unmounted!{Colors.ENDC}")
            return True
        except subprocess.CalledProcessError as e:
            print(f"{Colors.FAIL}Error unmounting: {e}{Colors.ENDC}")
            if not force:
                print(f"{Colors.WARNING}Try force unmount? (may require sudo){Colors.ENDC}")
            return False

    def reset_mount(self, remote: str, local_path: str) -> bool:
        """Unmount and remount a remote"""
        print(f"{Colors.HEADER}Resetting mount...{Colors.ENDC}")
        self.umount_remote(local_path, force=True)
        return self.mount_remote(remote, local_path)

    def save_mount_config(self, remote: str, local_path: str) -> None:
        """Save mount configuration to file"""
        config = {}
        if self.mount_config.exists():
            with open(self.mount_config, 'r') as f:
                config = json.load(f)

        config[local_path] = remote

        with open(self.mount_config, 'w') as f:
            json.dump(config, f, indent=2)

    def load_mount_config(self) -> Dict[str, str]:
        """Load saved mount configurations"""
        if self.mount_config.exists():
            with open(self.mount_config, 'r') as f:
                return json.load(f)
        return {}

    def get_rclone_remotes(self) -> List[str]:
        """Get list of configured rclone remotes"""
        try:
            result = subprocess.run(['rclone', 'listremotes'],
                                  capture_output=True,
                                  text=True,
                                  check=True)
            remotes = [r.strip().rstrip(':') for r in result.stdout.strip().split('\n') if r.strip()]
            return remotes
        except subprocess.CalledProcessError:
            return []

    def list_remote_folders(self, remote: str, max_depth: int = 1) -> List[str]:
        """List folders in a remote"""
        try:
            if ':' not in remote:
                remote = f"{remote}:"

            result = subprocess.run(
                ['rclone', 'lsf', remote, '--dirs-only', f'--max-depth={max_depth}'],
                capture_output=True,
                text=True,
                check=True,
                timeout=10
            )
            folders = [f.strip().rstrip('/') for f in result.stdout.strip().split('\n') if f.strip()]
            return folders
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return []

    def check_folders(self, local_path: str, remote: str, folders: List[str]) -> None:
        """Check if folders exist and run rclone check"""
        for folder in folders:
            local_folder = Path(local_path) / folder
            remote_folder = f"{remote}/{folder}"

            print(f"\n{Colors.HEADER}Checking: {folder}{Colors.ENDC}")

            if not local_folder.exists():
                print(f"{Colors.WARNING}Local folder does not exist: {local_folder}{Colors.ENDC}")
                continue

            print(f"{Colors.OKBLUE}Running rclone check...{Colors.ENDC}")
            try:
                result = subprocess.run(
                    ['rclone', 'check', str(local_folder), remote_folder, '--combined', '-'],
                    capture_output=True,
                    text=True,
                    check=False
                )
                print(result.stdout)
                if result.stderr:
                    print(f"{Colors.WARNING}{result.stderr}{Colors.ENDC}")
            except subprocess.CalledProcessError as e:
                print(f"{Colors.FAIL}Error: {e}{Colors.ENDC}")

    def bisync_folder(self, remote: str, local_path: str, folder: str,
                     dry_run: bool = False, resync: bool = False) -> bool:
        """Run bisync on a folder"""
        local_folder = Path(local_path) / folder

        # Format remote path correctly
        # If remote already has ':', it's formatted (e.g., 'Gdrive:' or 'Gdrive:path')
        # Otherwise, add ':' (e.g., 'Gdrive' -> 'Gdrive:')
        if ':' in remote:
            # Already has colon, check if it has a path after colon
            remote_parts = remote.split(':', 1)
            remote_name = remote_parts[0]
            remote_path = remote_parts[1] if len(remote_parts) > 1 else ''

            # Build remote folder path
            if remote_path:
                remote_folder = f"{remote_name}:{remote_path}/{folder}"
            else:
                remote_folder = f"{remote_name}:{folder}"
        else:
            # No colon, so it's just the remote name
            remote_folder = f"{remote}:{folder}"

        # Check if local folder exists
        if not local_folder.exists():
            print(f"{Colors.WARNING}Local folder does not exist: {local_folder}{Colors.ENDC}")
            create = input(f"{Colors.OKGREEN}Create it? [y]: {Colors.ENDC}").strip().lower()
            if not create or create == 'y':
                local_folder.mkdir(parents=True, exist_ok=True)
                print(f"{Colors.OKGREEN}Created: {local_folder}{Colors.ENDC}")
            else:
                print(f"{Colors.FAIL}Skipping {folder} - local folder missing{Colors.ENDC}")
                return False

        # Check if this is first time sync (no bisync state exists)
        bisync_cache = Path.home() / '.cache' / 'rclone' / 'bisync'
        needs_resync = resync or not bisync_cache.exists()

        cmd = [
            'rclone', 'bisync',
            remote_folder,
            str(local_folder),
            '--tpslimit', '10',
            '--drive-skip-gdocs'
        ]

        if needs_resync:
            cmd.append('--resync')
            print(f"{Colors.WARNING}Note: Using --resync (first time or forced resync){Colors.ENDC}")
            print(f"{Colors.WARNING}Path1 (remote) will be authoritative{Colors.ENDC}")

        if dry_run:
            cmd.append('--dry-run')

        # Add verbose only if not using log-level
        cmd.append('--verbose')

        print(f"\n{Colors.HEADER}Bisync: {folder}{Colors.ENDC}")
        print(f"{Colors.OKCYAN}Remote: {remote_folder}{Colors.ENDC}")
        print(f"{Colors.OKCYAN}Local:  {local_folder}{Colors.ENDC}")

        if dry_run:
            print(f"{Colors.WARNING}DRY RUN MODE - No changes will be made{Colors.ENDC}")

        try:
            result = subprocess.run(cmd, check=False)
            if result.returncode == 0:
                print(f"{Colors.OKGREEN}✓ Bisync completed successfully{Colors.ENDC}")
            else:
                print(f"{Colors.FAIL}✗ Bisync failed with code {result.returncode}{Colors.ENDC}")
            return result.returncode == 0
        except subprocess.CalledProcessError as e:
            print(f"{Colors.FAIL}Error during bisync: {e}{Colors.ENDC}")
            return False
        except KeyboardInterrupt:
            print(f"\n{Colors.WARNING}Bisync interrupted by user{Colors.ENDC}")
            return False


class TUI:
    """Text User Interface for the rclone manager"""

    def __init__(self, manager: RcloneManager):
        self.manager = manager

    def clear_screen(self) -> None:
        """Clear terminal screen - POSIX compliant"""
        subprocess.run(['clear'], check=False)

    def print_header(self) -> None:
        """Print TUI header"""
        self.clear_screen()
        print(f"{Colors.BOLD}{Colors.HEADER}")
        print("=" * 60)
        print("          RCLONE SYNC MANAGER")
        print("=" * 60)
        print(f"{Colors.ENDC}")

    def print_menu(self) -> None:
        """Print main menu"""
        print(f"\n{Colors.OKCYAN}Main Menu:{Colors.ENDC}")
        print(f"  {Colors.BOLD}1.{Colors.ENDC} Rclone Configuration")
        print(f"  {Colors.BOLD}2.{Colors.ENDC} Check Mount Status")
        print(f"  {Colors.BOLD}3.{Colors.ENDC} Mount Remote")
        print(f"  {Colors.BOLD}4.{Colors.ENDC} Unmount Remote")
        print(f"  {Colors.BOLD}5.{Colors.ENDC} Reset Mount (Unmount + Mount)")
        print(f"  {Colors.BOLD}6.{Colors.ENDC} Check Folders")
        print(f"  {Colors.BOLD}7.{Colors.ENDC} Bisync Folders")
        print(f"  {Colors.BOLD}8.{Colors.ENDC} Edit Default Mount Path")
        print(f"  {Colors.BOLD}9.{Colors.ENDC} View Log File")
        print(f"  {Colors.BOLD}0.{Colors.ENDC} Exit")
        print()

    def get_input(self, prompt: str) -> str:
        """Get user input with prompt"""
        return input(f"{Colors.OKGREEN}{prompt}{Colors.ENDC}").strip()

    def pause(self) -> None:
        """Pause and wait for user input"""
        input(f"\n{Colors.WARNING}Press Enter to continue...{Colors.ENDC}")

    def run(self) -> None:
        """Run the TUI main loop"""
        if not self.manager.check_rclone_installed():
            print(f"{Colors.FAIL}Error: rclone is not installed!{Colors.ENDC}")
            print("Please install rclone: https://rclone.org/install/")
            sys.exit(1)

        while True:
            self.print_header()

            # Auto-check mount status on startup
            default_mount = str(self.manager.default_mount)
            is_mounted, info = self.manager.get_mount_status(default_mount)

            print(f"\n{Colors.HEADER}Current Mount Status:{Colors.ENDC}")
            print(f"Default mountpoint: {Colors.BOLD}{default_mount}{Colors.ENDC}")
            if is_mounted:
                print(f"Status: {Colors.OKGREEN}MOUNTED ✓{Colors.ENDC}")
                print(f"{Colors.OKCYAN}{info}{Colors.ENDC}")
            else:
                print(f"Status: {Colors.WARNING}NOT MOUNTED{Colors.ENDC}")

            self.print_menu()

            choice = self.get_input("Select option: ")

            if choice == '1':
                self.manager.run_rclone_config()
                self.pause()

            elif choice == '2':
                # Use default path if no input
                mountpoint = self.get_input(f"Enter mountpoint path [{default_mount}]: ").strip()
                if not mountpoint:
                    mountpoint = default_mount

                is_mounted, info = self.manager.get_mount_status(mountpoint)
                if is_mounted:
                    print(f"{Colors.OKGREEN}✓ Mounted!{Colors.ENDC}")
                    print(f"{Colors.OKBLUE}{info}{Colors.ENDC}")
                else:
                    print(f"{Colors.WARNING}✗ Not mounted{Colors.ENDC}")
                self.pause()

            elif choice == '3':
                # Get available remotes
                remotes = self.manager.get_rclone_remotes()
                if not remotes:
                    print(f"{Colors.FAIL}No remotes configured! Please run rclone config first.{Colors.ENDC}")
                    self.pause()
                    continue

                print(f"\n{Colors.OKCYAN}Available remotes:{Colors.ENDC}")
                for i, r in enumerate(remotes, 1):
                    marker = " (default)" if i == 1 else ""
                    print(f"  {i}. {r}{marker}")

                remote_choice = self.get_input(f"Select remote [1]: ").strip()
                if not remote_choice:
                    remote_choice = '1'

                try:
                    remote_name = remotes[int(remote_choice) - 1]
                except (ValueError, IndexError):
                    print(f"{Colors.FAIL}Invalid selection{Colors.ENDC}")
                    self.pause()
                    continue

                # Ask for remote path
                use_root = self.get_input("Mount root folder? [y]: ").strip().lower()
                if not use_root:
                    use_root = 'y'

                remote_path = ""

                if use_root != 'y':
                    print(f"\n{Colors.OKCYAN}Listing folders in {remote_name}...{Colors.ENDC}")
                    folders = self.manager.list_remote_folders(remote_name)
                    if folders:
                        print(f"{Colors.OKCYAN}Available folders:{Colors.ENDC}")
                        for i, f in enumerate(folders, 1):
                            print(f"  {i}. {f}")
                        print(f"  0. Enter custom path")

                        folder_choice = self.get_input(f"Select folder [0]: ").strip()
                        if not folder_choice:
                            folder_choice = '0'

                        try:
                            idx = int(folder_choice)
                            if idx > 0:
                                remote_path = folders[idx - 1]
                            elif idx == 0:
                                remote_path = self.get_input("Enter remote path: ").strip('/')
                        except (ValueError, IndexError):
                            print(f"{Colors.FAIL}Invalid selection{Colors.ENDC}")
                            self.pause()
                            continue
                    else:
                        remote_path = self.get_input("Enter remote path (leave empty for root): ").strip('/')

                remote = f"{remote_name}:{remote_path}"

                # Ask for local path
                default_local = str(self.manager.default_mount)
                local = self.get_input(f"Local mountpoint [{default_local}]: ").strip()
                if not local:
                    local = default_local

                # Ask for mount mode
                print(f"\n{Colors.OKCYAN}Mount modes:{Colors.ENDC}")
                print(f"  1. Daemon (--daemon | Background service | Silent) - Default")
                print(f"  2. Silent Mode (& | Terminal Child Process)")
                print(f"  3. Verbose (Logs in terminal)")

                mode_choice = self.get_input("Select mode [1]: ").strip()
                if not mode_choice:
                    mode_choice = '1'

                mode_map = {'1': 'daemon', '2': 'silent', '3': 'verbose'}
                mode = mode_map.get(mode_choice, 'daemon')

                self.manager.mount_remote(remote, local, mode)

                if mode != 'verbose':
                    self.pause()

            elif choice == '4':
                # Show all mounted drives
                mounts = self.manager.get_all_mounts()

                if not mounts:
                    print(f"{Colors.WARNING}No rclone mounts found{Colors.ENDC}")
                    # Still offer to unmount manually
                    local = self.get_input(f"Enter mountpoint to unmount [{default_mount}]: ").strip()
                    if not local:
                        local = default_mount
                    force = self.get_input("Force unmount? [n]: ").strip().lower()
                    if not force:
                        force = 'n'
                    self.manager.umount_remote(local, force == 'y')
                else:
                    print(f"\n{Colors.OKCYAN}Currently mounted:{Colors.ENDC}")
                    for i, (remote, mountpoint) in enumerate(mounts, 1):
                        print(f"  {i}. {mountpoint} <- {remote}")
                    print(f"  0. Enter custom path")

                    choice_unmount = self.get_input(f"Select mount to unmount [0]: ").strip()
                    if not choice_unmount:
                        choice_unmount = '0'

                    try:
                        idx = int(choice_unmount)
                        if idx > 0 and idx <= len(mounts):
                            local = mounts[idx - 1][1]
                        else:
                            local = self.get_input(f"Enter mountpoint [{default_mount}]: ").strip()
                            if not local:
                                local = default_mount
                    except ValueError:
                        print(f"{Colors.FAIL}Invalid selection{Colors.ENDC}")
                        self.pause()
                        continue

                    force = self.get_input("Force unmount? [n]: ").strip().lower()
                    if not force:
                        force = 'n'
                    self.manager.umount_remote(local, force == 'y')

                self.pause()

            elif choice == '5':
                remotes = self.manager.get_rclone_remotes()
                if not remotes:
                    print(f"{Colors.FAIL}No remotes configured!{Colors.ENDC}")
                    self.pause()
                    continue

                print(f"\n{Colors.OKCYAN}Available remotes:{Colors.ENDC}")
                for i, r in enumerate(remotes, 1):
                    marker = " (default)" if i == 1 else ""
                    print(f"  {i}. {r}{marker}")

                remote_choice = self.get_input(f"Select remote [1]: ").strip()
                if not remote_choice:
                    remote_choice = '1'

                try:
                    remote_name = remotes[int(remote_choice) - 1]
                except (ValueError, IndexError):
                    print(f"{Colors.FAIL}Invalid selection{Colors.ENDC}")
                    self.pause()
                    continue

                remote_path = self.get_input("Enter remote path [root]: ").strip('/')
                remote = f"{remote_name}:{remote_path}"

                default_local = str(self.manager.default_mount)
                local = self.get_input(f"Local mountpoint [{default_local}]: ").strip()
                if not local:
                    local = default_local

                self.manager.reset_mount(remote, local)
                self.pause()

            elif choice == '6':
                local = self.get_input("Enter local base path: ")
                remote = self.get_input("Enter remote:path: ")
                folders = self.get_input("Enter folders (comma-separated): ").split(',')
                folders = [f.strip() for f in folders if f.strip()]
                self.manager.check_folders(local, remote, folders)
                self.pause()

            elif choice == '7':
                default_remote = self.manager.default_remote
                default_local = str(self.manager.default_bisync_base)

                remote = self.get_input(f"Enter remote:path [{default_remote}]: ").strip()
                if not remote:
                    remote = default_remote

                local = self.get_input(f"Enter local base path [{default_local}]: ").strip()
                if not local:
                    local = default_local

                folders = self.get_input("Enter folders (comma-separated): ").split(',')
                folders = [f.strip() for f in folders if f.strip()]

                if not folders:
                    print(f"{Colors.FAIL}No folders specified{Colors.ENDC}")
                    self.pause()
                    continue

                print(f"\n{Colors.OKCYAN}Bisync options:{Colors.ENDC}")
                dry_run = self.get_input("Dry run first? [y]: ").strip().lower()
                if not dry_run:
                    dry_run = 'y'
                dry_run = dry_run == 'y'

                if not dry_run:
                    resync = self.get_input("Force resync (--resync)? [n]: ").strip().lower()
                    if not resync:
                        resync = 'n'
                    resync = resync == 'y'
                else:
                    resync = False

                for folder in folders:
                    self.manager.bisync_folder(remote, local, folder, dry_run, resync)

                if dry_run:
                    print(f"\n{Colors.WARNING}Dry run completed. Run again without dry-run to apply changes.{Colors.ENDC}")

                self.pause()

            elif choice == '8':
                current = str(self.manager.default_mount)
                print(f"\n{Colors.OKCYAN}Current default mount: {current}{Colors.ENDC}")
                new_path = self.get_input("Enter new default mount path: ").strip()
                if new_path:
                    self.manager.default_mount = Path(new_path)
                    self.manager.log_dir = Path(new_path) / 'system' / '.rclone'
                    print(f"{Colors.OKGREEN}Default mount path updated!{Colors.ENDC}")
                    print(f"{Colors.OKCYAN}Log directory: {self.manager.log_dir}{Colors.ENDC}")
                self.pause()

            elif choice == '9':
                log_file = self.manager.log_dir / 'rclone.log'
                if log_file.exists():
                    print(f"\n{Colors.HEADER}Last 50 lines of log:{Colors.ENDC}")
                    try:
                        with open(log_file, 'r') as f:
                            lines = f.readlines()
                            for line in lines[-50:]:
                                print(line.rstrip())
                    except Exception as e:
                        print(f"{Colors.FAIL}Error reading log: {e}{Colors.ENDC}")
                else:
                    print(f"{Colors.WARNING}Log file not found: {log_file}{Colors.ENDC}")
                self.pause()

            elif choice == '0':
                print(f"{Colors.OKGREEN}Goodbye!{Colors.ENDC}")
                sys.exit(0)

            else:
                print(f"{Colors.FAIL}Invalid option!{Colors.ENDC}")
                self.pause()


def print_help() -> None:
    """Print help message"""
    help_text = f"""
{Colors.BOLD}Rclone Sync Manager{Colors.ENDC}

{Colors.HEADER}USAGE:{Colors.ENDC}
    rclone_manager.py [OPTIONS]

{Colors.HEADER}OPTIONS:{Colors.ENDC}
    -h, --help              Show this help message
    --config                Open rclone configuration
    --mount REMOTE LOCAL    Mount remote to local path
    --umount LOCAL          Unmount local path
    --check LOCAL REMOTE    Check folders
    --bisync REMOTE LOCAL   Run bisync on folders

{Colors.HEADER}EXAMPLES:{Colors.ENDC}
    {Colors.OKGREEN}# Start TUI{Colors.ENDC}
    ./rclone_manager.py

    {Colors.OKGREEN}# Mount a remote{Colors.ENDC}
    ./rclone_manager.py --mount gdrive:folder /mnt/gdrive

    {Colors.OKGREEN}# Unmount{Colors.ENDC}
    ./rclone_manager.py --umount /mnt/gdrive

    {Colors.OKGREEN}# Open rclone config{Colors.ENDC}
    ./rclone_manager.py --config

{Colors.HEADER}CONFIGURATION:{Colors.ENDC}
    Mount configurations are saved in:
    ~/.config/rclone_manager/mounts.json
"""
    print(help_text)


def main() -> None:
    """Main entry point"""
    manager = RcloneManager()

    # No arguments - start TUI
    if len(sys.argv) == 1:
        tui = TUI(manager)
        tui.run()
        return

    # Parse arguments
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('-h', '--help', action='store_true')
    parser.add_argument('--config', action='store_true')
    parser.add_argument('--mount', nargs=2, metavar=('REMOTE', 'LOCAL'))
    parser.add_argument('--umount', metavar='LOCAL')
    parser.add_argument('--force', action='store_true')

    try:
        args = parser.parse_args()
    except SystemExit:
        print_help()
        sys.exit(1)

    if args.help:
        print_help()
        sys.exit(0)

    if not manager.check_rclone_installed():
        print(f"{Colors.FAIL}Error: rclone is not installed!{Colors.ENDC}")
        sys.exit(1)

    if args.config:
        manager.run_rclone_config()
    elif args.mount:
        remote, local = args.mount
        manager.mount_remote(remote, local)
    elif args.umount:
        manager.umount_remote(args.umount, args.force)
    else:
        print(f"{Colors.FAIL}Invalid arguments!{Colors.ENDC}")
        print_help()
        sys.exit(1)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.WARNING}Interrupted by user{Colors.ENDC}")
        sys.exit(0)
    except Exception as e:
        print(f"{Colors.FAIL}Unexpected error: {e}{Colors.ENDC}")
        sys.exit(1)
