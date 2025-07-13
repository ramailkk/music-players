# Terminal Music Player 
# Requirements: yt-dlp and mpv in PATH

$YTDLP = "yt-dlp"
$MPV = "mpv"
$MPV_SOCKET = "mpvsocket"

$queue = @()
$currentIndex = 0
$isPlaying = $false
$repeatMode = $false
$mpvProcess = $null

function Test-Dependencies {
    try {
        $null = Get-Command $YTDLP -ErrorAction Stop
        $null = Get-Command $MPV -ErrorAction Stop
        return $true
    } catch {
        Write-Host "Error: Please install yt-dlp and mpv and ensure they're in your PATH" -ForegroundColor Red
        return $false
    }
}

function Get-SongInfo($query) {
    if ([string]::IsNullOrWhiteSpace($query)) {
        Write-Host "Please provide a search query" -ForegroundColor Red
        return $null
    }

    Write-Host "Searching for: $query" -ForegroundColor Cyan
    try {
        $output = & $YTDLP "ytsearch1:$query" --get-title --get-url --quiet --no-warnings `
            --default-search ytsearch --no-playlist --no-check-certificate --geo-bypass 2>$null

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($output)) {
            Write-Host "Failed to find song: $query" -ForegroundColor Red
            return $null
        }

        $lines = $output -split "`r?`n" | Where-Object { $_ -ne "" }
        if ($lines.Count -lt 2) {
            Write-Host "Invalid response from yt-dlp" -ForegroundColor Red
            return $null
        }

        return @{
            Title = $lines[0].Trim()
            Url   = $lines[1].Trim()
        }
    } catch {
        Write-Host "Error searching for song: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Add-Song($query) {
    $info = Get-SongInfo $query
    if ($null -eq $info) { return }

    $script:queue += $info
    Write-Host "Added to queue: $($info.Title)" -ForegroundColor Green

    if (-not $isPlaying) {
        Start-Playback
    }
}

function Start-MPV {
    if ($mpvProcess -and -not $mpvProcess.HasExited) {
        return $true
    }

    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $MPV
        $processInfo.Arguments = "--no-video --quiet --idle --input-ipc-server=$MPV_SOCKET --no-terminal"
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true

        $script:mpvProcess = [System.Diagnostics.Process]::Start($processInfo)
        Start-Sleep -Seconds 2  # Give mpv time to start and create socket
        return $true
    } catch {
        Write-Host "Failed to start mpv: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Send-MPVCommand($command) {
    if (-not (Start-MPV)) { return $false }

    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $MPV_SOCKET, [System.IO.Pipes.PipeDirection]::Out)
        $pipe.Connect(2000)
        $writer = New-Object System.IO.StreamWriter($pipe)
        $writer.WriteLine($command)
        $writer.Flush()
        $writer.Close()
        $pipe.Close()
        return $true
    } catch {
        Write-Host "Could not connect to mpv. Restarting mpv..." -ForegroundColor Yellow
        Stop-MPV
        Start-Sleep -Seconds 1
        return $false
    }
}

# New function to get a property from MPV
function Get-MPVProperty($property) {
    if (-not $mpvProcess -or $mpvProcess.HasExited) {
        return $null
    }

    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $MPV_SOCKET, [System.IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect(500) # Use a short timeout for quick checks
        $writer = New-Object System.IO.StreamWriter($pipe)
        $reader = New-Object System.IO.StreamReader($pipe)

        $command = "{ `"command`": [`"get_property`", `"$property`"] }"
        $writer.WriteLine($command)
        $writer.Flush()

        $response = $reader.ReadLine()
        $writer.Close()
        $reader.Close()
        $pipe.Close()

        if ($response) {
            $data = (ConvertFrom-Json -InputObject $response).data
            return $data
        }
        return $null
    } catch {
        # Don't show errors for property checks as they can happen during song transitions
        return $null
    }
}

function Play-Song($position) {
    if ([string]::IsNullOrWhiteSpace($position)) {
        Write-Host "Please specify a song position (e.g., 'play 3')" -ForegroundColor Red
        return
    }

    try {
        $index = [int]$position - 1  # Convert to 0-based index
    } catch {
        Write-Host "Invalid position. Please enter a number." -ForegroundColor Red
        return
    }

    if ($index -lt 0 -or $index -ge $queue.Count) {
        Write-Host "Invalid position. Queue has $($queue.Count) songs." -ForegroundColor Red
        return
    }

    $script:currentIndex = $index
    Start-Playback
}

function Start-Playback {
    if ($queue.Count -eq 0) {
        Write-Host "Queue is empty" -ForegroundColor Red
        return
    }

    if ($currentIndex -ge $queue.Count) {
        if ($repeatMode) {
            $script:currentIndex = 0
        } else {
            Write-Host "End of queue" -ForegroundColor Yellow
            $script:isPlaying = $false
            return
        }
    }

    $entry = $queue[$currentIndex]
    Write-Host "Playing: $($entry.Title)" -ForegroundColor Magenta

    if (Send-MPVCommand "{ `"command`": [`"loadfile`", `"$($entry.Url)`"] }") {
        $script:isPlaying = $true
    } else {
        # Fallback: restart mpv and try again
        if (Start-MPV) {
            Start-Sleep -Seconds 2
            if (Send-MPVCommand "{ `"command`": [`"loadfile`", `"$($entry.Url)`"] }") {
                $script:isPlaying = $true
            } else {
                $script:isPlaying = $false
            }
        } else {
            $script:isPlaying = $false
        }
    }
}

function Pause-Playback {
    if (Send-MPVCommand '{ "command": ["set_property", "pause", true] }') {
        Write-Host "Paused" -ForegroundColor Yellow
    }
}

function Resume-Playback {
    if (Send-MPVCommand '{ "command": ["set_property", "pause", false] }') {
        Write-Host "Resumed" -ForegroundColor Green
    }
}

function Stop-Playback {
    if (Send-MPVCommand '{ "command": ["stop"] }') {
        Write-Host "Stopped" -ForegroundColor Red
        $script:isPlaying = $false
    }
}

function Stop-MPV {
    if ($mpvProcess -and -not $mpvProcess.HasExited) {
        try {
            Send-MPVCommand '{ "command": ["quit"] }' | Out-Null
            Start-Sleep -Seconds 1
            if (-not $mpvProcess.HasExited) {
                $mpvProcess.Kill()
            }
        } catch {
            # Process might already be dead
        }
    }
    $script:mpvProcess = $null
    $script:isPlaying = $false
}

function Skip-Next {
    if ($currentIndex + 1 -lt $queue.Count) {
        $script:currentIndex++
        Start-Playback
    } elseif ($repeatMode) {
        $script:currentIndex = 0
        Start-Playback
    } else {
        Write-Host "End of queue" -ForegroundColor Yellow
        $script:isPlaying = $false
    }
}

function Skip-Previous {
    if ($currentIndex -gt 0) {
        $script:currentIndex--
        Start-Playback
    } else {
        Write-Host "Already at first song" -ForegroundColor Yellow
    }
}

function Toggle-Repeat {
    $script:repeatMode = -not $repeatMode
    $status = if ($repeatMode) { "ON" } else { "OFF" }
    Write-Host "Repeat mode: $status" -ForegroundColor Blue
}

function Remove-Song($position) {
    if ([string]::IsNullOrWhiteSpace($position)) {
        Write-Host "Please specify a song position (e.g., 'remove 3')" -ForegroundColor Red
        return
    }

    try {
        $index = [int]$position - 1  # Convert to 0-based index
    } catch {
        Write-Host "Invalid position. Please enter a number." -ForegroundColor Red
        return
    }

    if ($index -lt 0 -or $index -ge $queue.Count) {
        Write-Host "Invalid position. Queue has $($queue.Count) songs." -ForegroundColor Red
        return
    }

    $removedSong = $queue[$index]

    # Create new array without the removed element
    $newQueue = @()
    for ($i = 0; $i -lt $queue.Count; $i++) {
        if ($i -ne $index) {
            $newQueue += $queue[$i]
        }
    }
    $script:queue = $newQueue

    Write-Host "Removed: $($removedSong.Title)" -ForegroundColor Red

    # Adjust current index if needed
    if ($index -lt $currentIndex) {
        $script:currentIndex--
    } elseif ($index -eq $currentIndex) {
        # If we removed the currently playing song
        if ($isPlaying) {
            if ($currentIndex -lt $queue.Count) {
                Start-Playback  # Play next song
            } else {
                Stop-Playback
                $script:currentIndex = [Math]::Max(0, $queue.Count - 1)
            }
        }
    }
}

function Clear-Queue {
    Stop-Playback
    $script:queue = @()
    $script:currentIndex = 0
    Write-Host "Queue cleared" -ForegroundColor Red
}

function Show-Queue {
    if ($queue.Count -eq 0) {
        Write-Host "Queue is empty" -ForegroundColor Yellow
        return
    }

    Write-Host "Queue ($($queue.Count) songs):" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $queue.Count; $i++) {
        $entry = $queue[$i]
        $number = $i + 1
        
        if ($i -eq $currentIndex -and $isPlaying) {
            Write-Host ">>> $number. $($entry.Title)" -ForegroundColor Green
        } elseif ($i -eq $currentIndex) {
            Write-Host "||  $number. $($entry.Title)" -ForegroundColor Yellow
        } else {
            Write-Host "    $number. $($entry.Title)"
        }
    }
    Write-Host ""
    Write-Host "Repeat mode: $(if ($repeatMode) { 'ON' } else { 'OFF' })" -ForegroundColor Blue
}

function Show-Help {
    Write-Host @"

Music Player Commands:
  add <song>       - Add song to queue (searches YouTube)
  play <number>    - Start/resume playback or play specific song
  pause            - Pause current song
  resume           - Resume playback
  stop             - Stop playback
  next             - Skip to next song
  prev             - Skip to previous song
  remove <number>  - Remove song from queue by position
  repeat           - Toggle repeat mode
  queue            - Show current queue
  clear            - Clear entire queue
  help             - Show this help
  quit / exit / q  - Exit player
"@ -ForegroundColor Yellow
}

# Add Ctrl+C handler for clean exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if ($script:mpvProcess -and -not $script:mpvProcess.HasExited) {
        try {
            $script:mpvProcess.Kill()
        } catch {
            # Process might already be dead
        }
    }
}

# Initialize
if (-not (Test-Dependencies)) {
    exit 1
}

Write-Host "Terminal Music Player ~ Enjoy the beats" -ForegroundColor Cyan
Write-Host "Type 'help' for available commands." -ForegroundColor Gray

# Main loop - MODIFIED FOR AUTOMATIC PLAYBACK
while ($true) {
    # Check if current song ended
    if ($isPlaying) {
        $remaining = Get-MPVProperty "time-remaining"
        if ($remaining -ne $null -and [double]$remaining -le 0.5) {
            Skip-Next
        }
    }

    # Non-blocking check for user input
    if ([Console]::KeyAvailable) {
        Write-Host -NoNewline "`n> " -ForegroundColor Cyan
        $input = Read-Host

        if ([string]::IsNullOrWhiteSpace($input)) {
            Show-Queue
            continue
        }

        $parts = $input.Trim() -split " ", 2
        $cmd = $parts[0].ToLower()
        $arg = if ($parts.Count -gt 1) { $parts[1] } else { "" }

        switch ($cmd) {
            "add"    { Add-Song $arg }
            "play"   {
                if ([string]::IsNullOrWhiteSpace($arg)) {
                    Resume-Playback
                } else {
                    Play-Song $arg
                }
            }
            "pause"  { Pause-Playback }
            "resume" { Resume-Playback }
            "stop"   { Stop-Playback }
            "next"   { Skip-Next }
            "prev"   { Skip-Previous }
            "remove" { Remove-Song $arg }
            "repeat" { Toggle-Repeat }
            "clear"  { Clear-Queue }
            "queue"  { Show-Queue }
            "help"   { Show-Help }
            "quit"   {
                Write-Host "Shutting down..." -ForegroundColor Yellow
                Stop-MPV
                Write-Host "Goodbye!" -ForegroundColor Green
                exit 0
            }
            "exit"   {
                Write-Host "Shutting down..." -ForegroundColor Yellow
                Stop-MPV
                Write-Host "Goodbye!" -ForegroundColor Green
                exit 0
            }
            "q"      {
                Write-Host "Shutting down..." -ForegroundColor Yellow
                Stop-MPV
                Write-Host "Goodbye!" -ForegroundColor Green
                exit 0
            }
            default  {
                Write-Host "Unknown command: $cmd (type 'help' for available commands)" -ForegroundColor Red
            }
        }
    } else {
        # Sleep for a short period to avoid high CPU usage
        Start-Sleep -Milliseconds 250
    }
}

# Final cleanup (in case loop is exited unexpectedly)
if ($mpvProcess -and -not $mpvProcess.HasExited) {
    Stop-MPV
}