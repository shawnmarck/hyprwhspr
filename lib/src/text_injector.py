"""
Text injector for HyprWhspr
Handles injecting transcribed text into other applications using paste strategy
"""

import os
import shutil
import subprocess
import time
import pyperclip
from typing import Optional


class TextInjector:
    """Handles injecting text into focused applications"""

    def __init__(self, config_manager=None):
        # Configuration
        self.config_manager = config_manager

        # Initialize settings from config if available
        if self.config_manager:
            # Always use paste strategy for fast, reliable injection
            pass
        else:
            # No fallback settings needed
            pass

        # Detect available injectors
        self.ydotool_available = self._check_ydotool()

        if not self.ydotool_available:
            print("⚠️  No typing backend found (ydotool). HyprWhspr requires ydotool for paste injection.")

    def _check_ydotool(self) -> bool:
        """Check if ydotool is available on the system"""
        try:
            result = subprocess.run(['which', 'ydotool'], capture_output=True, text=True, timeout=5)
            return result.returncode == 0
        except Exception:
            return False

    # ------------------------ Public API ------------------------

    def inject_text(self, text: str) -> bool:
        """
        Inject text into the currently focused application

        Args:
            text: Text to inject

        Returns:
            True if successful, False otherwise
        """
        if not text or text.strip() == "":
            print("No text to inject (empty or whitespace)")
            return True

        # Preprocess; also trim trailing newlines (avoid unwanted Enter)
        processed_text = self._preprocess_text(text).rstrip("\r\n")

        try:
            # Use strategy-based injection
            if self.ydotool_available:
                return self._inject_via_clipboard_and_hotkey(processed_text)
            else:
                return self._inject_via_clipboard(processed_text)

        except Exception as e:
            print(f"Primary injection method failed: {e}")

            # No fallback needed - paste strategy is always reliable
            return False

    # ------------------------ Helpers ------------------------

    def _preprocess_text(self, text: str) -> str:
        """
        Preprocess text to handle common speech-to-text corrections and remove unwanted line breaks
        """
        import re

        # Normalize line breaks to spaces to avoid unintended "Enter"
        processed = text.replace('\r\n', ' ').replace('\r', ' ').replace('\n', ' ')

        # Apply user-defined overrides first
        processed = self._apply_word_overrides(processed)

        # Built-in speech-to-text replacements
        replacements = {
            r'\bperiod\b': '.',
            r'\bcomma\b': ',',
            r'\bquestion mark\b': '?',
            r'\bexclamation mark\b': '!',
            r'\bcolon\b': ':',
            r'\bsemicolon\b': ';',
            r'\btux enter\b': '\n',     # Special phrase for new line
            r'\btab\b': '\t',
            r'\bdash\b': '-',
            r'\bunderscore\b': '_',
            r'\bopen paren\b': '(',
            r'\bclose paren\b': ')',
            r'\bopen bracket\b': '[',
            r'\bclose bracket\b': ']',
            r'\bopen brace\b': '{',
            r'\bclose brace\b': '}',
            r'\bat symbol\b': '@',
            r'\bhash\b': '#',
            r'\bdollar sign\b': '$',
            r'\bpercent\b': '%',
            r'\bcaret\b': '^',
            r'\bampersand\b': '&',
            r'\basterisk\b': '*',
            r'\bplus\b': '+',
            r'\bequals\b': '=',
            r'\bless than\b': '<',
            r'\bgreater than\b': '>',
            r'\bslash\b': '/',
            r'\bbackslash\b': r'\\',
            r'\bpipe\b': '|',
            r'\btilde\b': '~',
            r'\bgrave\b': '`',
            r'\bquote\b': '"',
            r'\bapostrophe\b': "'",
        }

        for pattern, replacement in replacements.items():
            processed = re.sub(pattern, replacement, processed, flags=re.IGNORECASE)

        # Collapse runs of whitespace, preserve intentional newlines
        processed = re.sub(r'[ \t]+', ' ', processed)
        processed = re.sub(r' *\n *', '\n', processed)
        processed = processed.strip()

        return processed

    def _apply_word_overrides(self, text: str) -> str:
        """Apply user-defined word overrides to the text"""
        import re

        if not self.config_manager:
            return text

        word_overrides = self.config_manager.get_word_overrides()
        if not word_overrides:
            return text

        processed = text
        for original, replacement in word_overrides.items():
            if original and replacement:
                pattern = r'\b' + re.escape(original) + r'\b'
                processed = re.sub(pattern, replacement, processed, flags=re.IGNORECASE)

        return processed

    # ------------------------ Backends ------------------------

    def _inject_via_ydotool(self, text: str) -> bool:
        """
        Inject using ydotool.
        - For 'paste' strategy: use clipboard then Ctrl+V keystroke (fast).
        - For 'type' strategy: stream text via stdin with --key-delay.
        """
        if self.inject_strategy == "paste":
            return self._inject_via_clipboard_and_hotkey(text)

        try:
            delay = self._compute_key_delay_ms()
            cmd = ['ydotool', 'type', '--key-delay', str(delay), '--file', '-']

            # Respect YDOTOOL_SOCKET; default to $XDG_RUNTIME_DIR/.ydotool_socket
            env = os.environ.copy()
            if "YDOTOOL_SOCKET" not in env:
                xdg = env.get("XDG_RUNTIME_DIR")
                if xdg:
                    env["YDOTOOL_SOCKET"] = os.path.join(xdg, ".ydotool_socket")

            print(f"Injecting text with ydotool: type (delay={delay}ms) via {env.get('YDOTOOL_SOCKET','<default>')}")
            result = subprocess.run(
                cmd,
                input=text.encode("utf-8"),
                capture_output=True,
                text=False,
                timeout=60,
                env=env,
            )

            if result.returncode == 0:
                return True
            else:
                stderr = (result.stderr or b"").decode("utf-8", "ignore")
                print(f"ERROR: ydotool failed: {stderr}")
                return False

        except subprocess.TimeoutExpired:
            print("ERROR: ydotool command timed out")
            return False
        except Exception as e:
            print(f"ERROR: ydotool injection failed: {e}")
            return False

    # ------------------------ Paste injection (primary method) ------------------------

    def _inject_via_clipboard_and_hotkey(self, text: str) -> bool:
        """Fast path: copy to clipboard, then press Ctrl+V via ydotool."""
        try:
            # 1) Set clipboard (prefer wl-copy on Wayland)
            if shutil.which("wl-copy"):
                subprocess.run(["wl-copy"], input=text.encode("utf-8"), check=True)
            else:
                pyperclip.copy(text)

            time.sleep(0.12)  # settle so the target app sees the new clipboard

            # 2) Press Ctrl+V
            if self.ydotool_available:
                # Linux evdev codes: 29 = LeftCtrl, 47 = 'V'
                result = subprocess.run(['ydotool', 'key', '29:1', '47:1', '47:0', '29:0'], capture_output=True, timeout=5)
                if result.returncode != 0:
                    stderr = (result.stderr or b"").decode("utf-8", "ignore")
                    print(f"  ydotool paste command failed: {stderr}")
                    return False
                return True

            print("No key-injection tool available; text is on the clipboard.")
            return True

        except Exception as e:
            print(f"Clipboard+hotkey injection failed: {e}")
            return False

    def _inject_via_clipboard(self, text: str) -> bool:
        """Fallback: copy text to clipboard if ydotool is not available."""
        try:
            if shutil.which("wl-copy"):
                subprocess.run(["wl-copy"], input=text.encode("utf-8"), check=True)
            else:
                pyperclip.copy(text)
            
            print("Text copied to clipboard (ydotool not available for paste)")
            return True
        except Exception as e:
            print(f"ERROR: Clipboard fallback failed: {e}")
            return False

