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
#
# On completion the spinner line is replaced with `<symbol> <text>` and
# the cursor moves to a new line, so chained spinners leave a clean log.
# Pass `--no-persist` to keep the old "vanish on completion" behavior.
@example "Wrap a command in a spinner" {
    with-spinner "Compiling..." { ^cargo build }
}
@example "Capture the closure's return value" {
    let widgets = with-spinner "Loading widgets..." { http get https://example.com }
}
@example "Show different text once the work is done" {
    with-spinner "Compiling..." --done-text "Compiled!" { ^cargo build }
}
@example "Remove the text once the block finishes" {
    with-spinner --no-persist "Polling..." { sleep 2sec }
}
export def with-spinner [
    text: string # Label shown to the right of the spinner.
    work: closure # The work to perform while the spinner spins.
    --interval: duration = 80ms
    --color: string = "cyan" # Color of the running spinner glyph.
    --done-text: string # Text for the persisted line on success (default: text input).
    --symbol: string = "✔" # Symbol shown in front of the persisted success line.
    --symbol-color: string = "green" # Color of the success symbol.
    --fail-text: string # Text for the persisted line on failure (default: text input).
    --fail-symbol: string = "✖" # Symbol shown in front of the persisted failure line.
    --fail-color: string = "red" # Color of the failure symbol.
    --no-persist # Vanish on completion instead of leaving a line.
]: nothing -> any {
    let id = spinner start $text --interval $interval --color $color
    let result = try { do $work } catch {|err|
        spinner stop $id
        if not $no_persist {
            let label = $fail_text | default $text
            print $"(ansi $fail_color)($fail_symbol)(ansi reset) ($label)"
        }
        error make --unspanned {msg: $err.msg}
    }
    spinner stop $id
    if not $no_persist {
        let label = $done_text | default $text
        print $"(ansi $symbol_color)($symbol)(ansi reset) ($label)"
    }
    $result
}
