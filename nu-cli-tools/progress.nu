# Progress bar — a horizontal indicator that fills left-to-right as work completes.

# Built-in glyph sets. Pick one via `--style` or pass `--glyphs` to fully override.
# `smooth` uses unicode partial-block characters for sub-cell resolution; the
# others step a whole cell at a time.
const STYLES = {
    smooth: {full: "█", empty: "░", partials: ["▏", "▎", "▍", "▌", "▋", "▊", "▉"]},
    blocks: {full: "█", empty: "░", partials: []},
    ascii:  {full: "#", empty: "-", partials: []},
    line:   {full: "━", empty: "─", partials: []},
}

const DEFAULT_GLYPHS = {full: "█", empty: "░", partials: ["▏", "▎", "▍", "▌", "▋", "▊", "▉"]}

# Repeat a string N times. Private helper.
def repeat-str [s: string, n: int]: nothing -> string {
    if $n <= 0 { "" } else { 0..<$n | each { $s } | str join }
}

# Resolve a --style name (or an explicit override) to a glyph record.
def resolve-glyphs [style: string, override: any]: nothing -> record {
    if $override != null { $override } else { $STYLES | get -o $style | default $DEFAULT_GLYPHS }
}

# Render the bar body (no brackets, label, or carriage return).
def render-bar [current: float, total: float, width: int, glyphs: record]: nothing -> string {
    let raw = if $total <= 0 { 0.0 } else { $current / $total }
    let ratio = if $raw < 0 { 0.0 } else if $raw > 1 { 1.0 } else { $raw }
    let sub = ($glyphs.partials | length) + 1
    let filled = ($width * $sub * $ratio) | math round | into int
    let full_cells = $filled // $sub
    let partial_idx = $filled mod $sub
    let partial_char = if $partial_idx == 0 { "" } else { $glyphs.partials | get ($partial_idx - 1) }
    let empty_cells = $width - $full_cells - (if $partial_idx == 0 { 0 } else { 1 })
    (repeat-str $glyphs.full $full_cells) + $partial_char + (repeat-str $glyphs.empty $empty_cells)
}

# Format a duration compactly: "5s", "1m23s", "2h15m".
def format-eta [d: duration]: nothing -> string {
    let s = ($d / 1sec) | math floor | into int
    if $s < 60 { $"($s)s" } else if $s < 3600 { $"(($s // 60))m(($s mod 60))s" } else { $"(($s // 3600))h(($s mod 3600) // 60)m" }
}

# Internal: write one full bar line (no newline). Shared by `draw` and `each`.
def draw-line [current: number, total: number, text: string, opts: record]: nothing -> nothing {
    let glyphs = resolve-glyphs $opts.style $opts.glyphs
    let bar = render-bar ($current | into float) ($total | into float) $opts.width $glyphs
    let pct = if $total <= 0 { 0 } else { (($current * 100) / $total) | math round | into int }
    let label = if ($text | is-empty) { "" } else { $" ($text)" }
    let count = if $opts.show_count { $" \(($current)/($total)\)" } else { "" }
    let eta = if $opts.show_eta and $opts.start != null and $current > 0 and $total > 0 {
        let elapsed = (date now) - $opts.start
        let ratio = ($current | into float) / ($total | into float)
        let est_total = $elapsed / $ratio
        let remaining = $est_total - $elapsed
        $" eta (format-eta $remaining)"
    } else { "" }
    print -n (ansi cursor_off)
    print -n $"\r(ansi erase_entire_line)(ansi $opts.color)[($bar)](ansi reset) ($pct)%($count)($label)($eta)"
}

# Draw (or redraw) a progress bar on the current line.
#
# Stateless: pass `current` and `total` each call. Use this when you drive
# the loop yourself. Call `progress finish` (or `succeed`/`fail`) when done
# to restore the cursor and move to a new line.
@example "Manual loop with smooth bar" {
    for i in 1..50 {
        sleep 50ms
        progress draw $i 50 "Working..."
    }
    progress finish
}
@example "Pick a different style and show count + ETA" {
    let start = date now
    for i in 1..50 {
        sleep 50ms
        progress draw $i 50 "Crunching" --style ascii --show-count --show-eta --start $start
    }
    progress finish
}
export def "progress draw" [
    current: number, # Work completed so far.
    total: number,   # Total amount of work.
    text?: string,   # Optional label shown after the bar.
    --width: int = 30,                # Bar width in characters.
    --style: string = "smooth",       # smooth | blocks | ascii | line
    --color: string = "cyan",         # ANSI color for the bar.
    --glyphs: record,                 # Full override: {full, empty, partials}.
    --show-eta,                       # Append elapsed/eta (requires --start).
    --show-count,                     # Append "N/Total".
    --start: datetime,                # Start time for ETA. Pass `(date now)` before the loop.
]: nothing -> nothing {
    let opts = {width: $width, style: $style, color: $color, glyphs: $glyphs, show_eta: $show_eta, show_count: $show_count, start: $start}
    draw-line $current $total ($text | default "") $opts
}

# Finalize a progress line: restore the cursor and move to a new line.
export def "progress finish" []: nothing -> nothing {
    print $"(ansi cursor_on)"
}

# Clear the bar line and persist a "success" line in its place.
@example "Persist a success line after a manual loop" {
    for i in 1..50 { sleep 30ms; progress draw $i 50 "Building" }
    progress succeed --text "Built in 1.5s"
}
export def "progress succeed" [
    --text: string = "",
    --symbol: string = "✔",
    --color: string = "green",
]: nothing -> nothing {
    print -n $"\r(ansi erase_entire_line)(ansi cursor_on)"
    print $"(ansi $color)($symbol)(ansi reset) ($text)"
}

# Clear the bar line and persist a "failure" line in its place.
export def "progress fail" [
    --text: string = "",
    --symbol: string = "✖",
    --color: string = "red",
]: nothing -> nothing {
    print -n $"\r(ansi erase_entire_line)(ansi cursor_on)"
    print $"(ansi $color)($symbol)(ansi reset) ($text)"
}

# Iterate over a list, redrawing a progress bar after each element.
#
# Total is taken from the pipeline input's length. Returns the closure
# results, like `each`. On error the bar is cleaned up before the error
# propagates.
@example "Process files with a progress bar" {
    ls **/*.rs | progress each "Linting" { |f| ^cargo clippy --quiet $f.name }
}
@example "Count + ETA with the ascii style, and persist a success line" {
    1..100 | progress each "Crunching" --style ascii --show-count --show-eta --persist { |i| sleep 30ms }
}
export def "progress each" [
    text: string,                  # Label shown after the bar.
    work: closure,                 # Work to run for each element.
    --width: int = 30,
    --style: string = "smooth",
    --color: string = "cyan",
    --glyphs: record,
    --show-eta,
    --show-count,
    --persist,                     # Leave a "✔ text" line on success (default: just newline).
    --symbol: string = "✔",
    --symbol-color: string = "green",
    --fail-symbol: string = "✖",
    --fail-color: string = "red",
]: any -> list<any> {
    # Materialize the input so ranges work like lists.
    let items = $in | each {|x| $x}
    let total = $items | length
    let start = date now
    let opts = {width: $width, style: $style, color: $color, glyphs: $glyphs, show_eta: $show_eta, show_count: $show_count, start: $start}
    draw-line 0 $total $text $opts
    let result = try {
        $items | enumerate | each {|row|
            let r = do $work $row.item
            draw-line ($row.index + 1) $total $text $opts
            $r
        }
    } catch {|err|
        progress fail --text $text --symbol $fail_symbol --color $fail_color
        error make --unspanned {msg: $err.msg}
    }
    if $persist {
        progress succeed --text $text --symbol $symbol --color $symbol_color
    } else {
        progress finish
    }
    $result
}
