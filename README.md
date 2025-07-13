# Terminal Music Player

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://docs.microsoft.com/en-us/powershell/) [![yt-dlp](https://img.shields.io/badge/yt--dlp-latest-brightgreen)](https://github.com/yt-dlp/yt-dlp) [![mpv](https://img.shields.io/badge/mpv-latest-purple)](https://mpv.io/)

A simple terminal-based music player built with PowerShell, `yt-dlp`, and `mpv`. Search and play music from YouTube directly in your terminal. This project was created to consume less memory while enjoying music from YouTube and to integrate seamlessly with a terminal-based workflow in an IDE.

---

## Features

*   **Lightweight:** Low memory footprint compared to a web browser.
*   **Search and Play:** Find and stream audio from YouTube without leaving your terminal.
*   **Seamless Integration:** Keep your music playback in the same environment as your development tools.
*   **Simple and Fast:** Quickly play music with just a few commands.
---

## Requirements

Before you begin, ensure you have the following installed and configured:

*   **[MPV](https://mpv.io/)**: A powerful, free, and open-source media player.
*   **[yt-dlp](https://github.com/yt-dlp/yt-dlp)**: A feature-rich command-line tool for downloading videos and audio from YouTube and other sites.
*   **PowerShell 5.1+**: Comes pre-installed with modern versions of Windows.

---

## ⚙️ Setup Instructions

### 1. Install MPV

1.  **Download MPV for Windows** from the official source: [Download here](https://sourceforge.net/projects/mpv-player-windows/).
2.  **Extract the archive** to a permanent location on your computer (e.g., `C:\Program Files\mpv`).
3.  **Add the folder containing `mpv.exe`** to your system’s `PATH` environment variable. This allows you to run `mpv` from any terminal.

### 2. Install yt-dlp

1.  **Download `yt-dlp.exe`** from the [latest release page](https://github.com/yt-dlp/yt-dlp/releases/latest).
2.  **Place the executable** in a dedicated folder (e.g., `C:\Tools`).
3.  **Add that folder to your system’s `PATH`** as well.

### 3. Verify Installation

To confirm that both `mpv` and `yt-dlp` are correctly installed and accessible from your `PATH`, open a new PowerShell terminal and run:

```bash
mpv --version
yt-dlp --version```

If both commands return a version number, you are ready to go!

---

##  How to Run

1.  **Open PowerShell**: Launch a new PowerShell terminal.
2.  **Navigate to the script's directory**:
    ```powershell
    cd path\to\cli-music-player
    ```
3.  **Run the script**:
    ```powershell
    .\music_player.ps1
    ```

### Troubleshooting

If you encounter an error message like `running scripts is disabled on this system`, you need to change the execution policy for your user account. Run this command once in PowerShell:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

This command allows locally created scripts to run. You can now try running the script again.

Enjoy your music! 🎵
