# Loading spinner — a small animated indicator for long-running work.

# The classic braille frames; spinner on the left, text on the right.
const FRAMES = ["⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"]

# Start a spinner in the background and return a handle.
#
# Pass the returned handle to `stop`, `succeed`, or `fail` when the work is done.
@example "Customize the color and frame interval" {
    spinner start "Crunching..." --color magenta --interval 60ms
}
export def "spinner start" [
    text: string # Label shown to the right of the spinner.
    --interval: duration = 80ms # Time between frame updates.
    --color: string = "cyan" # ANSI color name for the spinner glyph.
    --frames: list<string> = $FRAMES # Override the animation frames.
]: nothing -> record<id: int, text: string> {
    let id = job spawn --description $"spinner: ($text)" {
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
    {id: $id text: $text}
}

# Resolve a spinner handle (record or bare int) to {id, text}.
# Private helper shared by stop/succeed/fail.
def "spinner handle-info" [handle: any]: nothing -> record<id: int, text: string> {
    if $handle == null {
        error make {msg: "spinner: missing handle (pass the value returned by `spinner start`)"}
    }
    if (($handle | describe) | str starts-with "record") {
        {id: $handle.id text: ($handle | get -o text | default "")}
    } else {
        {id: $handle text: ""}
    }
}

# Stop a running spinner, clear its line, and restore the cursor.
#
# Accepts the handle as input (pipe) or as a positional argument. Use this
# when you want the spinner to vanish without a trace — for a persisted
# completion line, use `spinner succeed` or `spinner fail` instead.
@example "Stop via the pipeline" {
    let s = spinner start "Working..."
    $s | spinner stop
}
@example "Stop via positional argument" {
    let s = spinner start "Working..."
    spinner stop $s
}
export def "spinner stop" [
    handle?: any # The handle returned by `start`. Falls back to pipeline input.
]: any -> nothing {
    let piped = $in
    let info = spinner handle-info (if $handle != null { $handle } else { $piped })
    job kill $info.id
    print -n $"\r(ansi erase_entire_line)(ansi cursor_on)"
}

# Stop a spinner and leave a persisted "success" line in its place.
#
# The label defaults to the running text from the handle; pass `--text` to
# override. Accepts the handle as input (pipe) or positional argument.
@example "Persist with the original text" {
    let s = spinner start "Compiling..."
    $s | spinner succeed
}
@example "Persist with a different message" {
    let s = spinner start "Compiling..."
    $s | spinner succeed --text "Compiled in 1.2s"
}
export def "spinner succeed" [
    handle?: any # Handle from `spinner start`. Falls back to pipeline input.
    --text: string # Override the persisted label (default: handle's text).
    --symbol: string = "✔" # Symbol shown in front of the persisted line.
    --color: string = "green" # Color of the symbol.
]: any -> nothing {
    let piped = $in
    let info = spinner handle-info (if $handle != null { $handle } else { $piped })
    job kill $info.id
    let label = $text | default $info.text
    print -n $"\r(ansi erase_entire_line)(ansi cursor_on)"
    print $"(ansi $color)($symbol)(ansi reset) ($label)"
}

# Stop a spinner and leave a persisted "failure" line in its place.
#
# Like `spinner succeed` but defaults to a red ✖.
@example "Persist a failure with the original text" {
    let s = spinner start "Building..."
    $s | spinner fail
}
@example "Persist a failure with a different message" {
    let s = spinner start "Building..."
    $s | spinner fail --text "Build failed"
}
export def "spinner fail" [
    handle?: any # Handle from `spinner start`. Falls back to pipeline input.
    --text: string # Override the persisted label (default: handle's text).
    --symbol: string = "✖" # Symbol shown in front of the persisted line.
    --color: string = "red" # Color of the symbol.
]: any -> nothing {
    let piped = $in
    let info = spinner handle-info (if $handle != null { $handle } else { $piped })
    job kill $info.id
    let label = $text | default $info.text
    print -n $"\r(ansi erase_entire_line)(ansi cursor_on)"
    print $"(ansi $color)($symbol)(ansi reset) ($label)"
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
    let handle = spinner start $text --interval $interval --color $color
    let result = try { do $work } catch {|err|
        if $no_persist {
            spinner stop $handle
        } else {
            spinner fail $handle --text ($fail_text | default $text) --symbol $fail_symbol --color $fail_color
        }
        error make --unspanned {msg: $err.msg}
    }
    if $no_persist {
        spinner stop $handle
    } else {
        spinner succeed $handle --text ($done_text | default $text) --symbol $symbol --color $symbol_color
    }
    $result
}
