# Loading spinner — a small animated indicator for long-running work.

# The classic braille frames; spinner on the left, text on the right.
const FRAMES = ["⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"]

# Start a spinner in the background and return a handle.
#
# Pass the returned id to `stop` when the work is done.
@example "Customize the color and frame interval" {
    spinner start "Crunching..." --color magenta --interval 60ms
}
export def "spinner start" [
    text: string # Label shown to the right of the spinner.
    --interval: duration = 80ms # Time between frame updates.
    --color: string = "cyan" # ANSI color name for the spinner glyph.
    --frames: list<string> = $FRAMES # Override the animation frames.
]: nothing -> int {
    job spawn --description $"spinner: ($text)" {
        let n = $frames | length
        print -n (ansi cursor_off)
        mut i = 0
        loop {
            let glyph = $frames | get ($i mod $n)
            print -n $"\r(ansi $color)($glyph)(ansi reset) ($text)"
            sleep $interval
            $i += 1
        }
    }
}

# Stop a running spinner, clear its line, and restore the cursor.
#
# Accepts the handle as input (pipe) or as a positional argument.
@example "Stop via the pipeline" {
    let s = spinner start "Working..."
    $s | spinner stop
}
@example "Stop via positional argument" {
    let s = spinner start "Working..."
    spinner stop $s
}
export def "spinner stop" [
    id?: int # The handle returned by `start`. Falls back to pipeline input.
]: any -> nothing {
    let piped = $in
    let target = if $id != null { $id } else if ($piped | describe) == "int" { $piped } else { null }
    if $target == null {
        error make {msg: "spinner stop: missing spinner handle"}
    }
    job kill $target
    print -n $"\r(ansi erase_entire_line)(ansi cursor_on)"
}

# Run a closure while a spinner is shown, then stop the spinner and
# return the closure's result. The spinner is always stopped, even on error.
@example "Wrap a command in a spinner" {
    with-spinner "Compiling..." { ^cargo build }
}
@example "Capture the closure's return value" {
    let widgets = with-spinner "Loading widgets..." { http get https://example.com }
}
export def with-spinner [
    text: string # Label shown to the right of the spinner.
    work: closure # The work to perform while the spinner spins.
    --interval: duration = 80ms
    --color: string = "cyan"
]: nothing -> any {
    let id = spinner start $text --interval $interval --color $color
    let result = try { do $work } catch {|err|
        spinner stop $id
        error make --unspanned {msg: $err.msg}
    }
    spinner stop $id
    $result
}
