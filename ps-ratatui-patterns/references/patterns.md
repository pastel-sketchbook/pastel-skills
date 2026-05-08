# Ratatui TUI Patterns — Reference

Battle-tested patterns extracted from pastel-market, kube-log-viewer, and yp. Use these as the default approach in any Pastel Sketchbook ratatui app — copy, adapt, do not reinvent.

## 1. Terminal lifecycle (main.rs)

Always enter the alternate screen, enable raw mode, and enable mouse capture — even apps that don't yet use the mouse benefit from scroll. Always restore on exit, even on error.

```rust
use std::io;
use std::time::Duration;
use anyhow::Result;
use crossterm::event::{DisableMouseCapture, EnableMouseCapture, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::Terminal;
use ratatui::prelude::CrosstermBackend;

const TICK_RATE_MS: u64 = 250;

fn main() -> Result<()> {
    terminal::enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App::new();
    let events = EventHandler::new(Duration::from_millis(TICK_RATE_MS));
    let res = run_loop(&mut terminal, &mut app, &events);

    // Restore terminal unconditionally.
    terminal::disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen, DisableMouseCapture)?;
    terminal.show_cursor()?;
    res
}
```

The event loop drains async work *before* drawing, then dispatches:

```rust
loop {
    app.drain_results();
    terminal.draw(|frame| ui::draw(frame, app))?;
    match events.next()? {
        Event::Key(k) if k.kind == KeyEventKind::Press => app.handle_key(k),
        Event::Mouse(m) => app.handle_mouse(m),
        Event::Tick    => app.on_tick(),
        Event::Resize(_, _) | Event::Key(_) => {}
    }
    if app.should_quit { break; }
}
```

Use a 250 ms tick rate as the default. Anything faster wastes CPU; slower feels laggy.

## 2. App layout

Every screen should follow the same vertical skeleton:

```text
+-- header  (Length 3 -- title, tabs, indicators) --+
|                                                    |
|  body    (Min 5    -- flexible content)            |
|                                                    |
+-- status  (Length 1 -- one-line transient msg)     |
+-- footer  (Length 1 -- keybinding hints)           |
```

Implementation:

```rust
let chunks = Layout::default()
    .direction(Direction::Vertical)
    .constraints([
        Constraint::Length(3), // header
        Constraint::Min(5),    // body
        Constraint::Length(1), // status
        Constraint::Length(1), // footer
    ])
    .split(frame.area());
```

Always paint the theme background first so light themes don't leak the terminal default:

```rust
frame.render_widget(Clear, frame.area());
frame.render_widget(
    Block::default().style(Style::default().bg(theme.bg).fg(theme.fg)),
    frame.area(),
);
```

Render overlays (chart, popup, help) after the main layout so they appear on top.

## 3. Size guard

Before rendering, bail out with a friendly message when the terminal is too small.

```rust
pub const MIN_TERM_WIDTH:  u16 = 80;
pub const MIN_TERM_HEIGHT: u16 = 20;

pub fn render_size_guard(frame: &mut Frame, theme: &Theme) -> bool {
    let area = frame.area();
    if area.width >= MIN_TERM_WIDTH && area.height >= MIN_TERM_HEIGHT {
        return false;
    }
    frame.render_widget(Clear, area);
    let msg = format!(
        "Terminal too small ({}\u{00d7}{}). Need at least {MIN_TERM_WIDTH}\u{00d7}{MIN_TERM_HEIGHT}.",
        area.width, area.height,
    );
    let p = Paragraph::new(msg)
        .style(Style::default().fg(theme.error))
        .block(Block::default().borders(Borders::ALL)
            .border_style(Style::default().fg(theme.border)));
    frame.render_widget(p, area);
    true
}
```

Call it as the first thing inside `draw()` and short-circuit if it returns `true`.

## 4. Theme system

A `Theme` is a `Copy` struct of semantic `ratatui::style::Color` slots. Themes live in a `&'static [Theme]` array; the app stores a `theme_index: usize` and exposes `fn theme(&self) -> &'static Theme`.

Required semantic slots (superset that satisfies dashboards, log viewers, and pickers):

```rust
#[derive(Debug, Clone, Copy)]
pub struct Theme {
    pub name: &'static str,
    pub bg: Color, pub fg: Color,
    pub accent: Color, pub muted: Color, pub border: Color,
    pub gain: Color, pub loss: Color, pub error: Color, pub status: Color,
    pub highlight_bg: Color, pub highlight_fg: Color, pub stripe_bg: Color,
    pub key_bg: Color, pub key_fg: Color,
    pub title: Color, pub tag: Color,
    pub panel_bg: Color, pub chart_bg: Color,
}
```

See `references/themes.md` for the full theme palette (16 themes: 8 dark + 8 light).

Rules:

- Default theme is index 0 and uses `Color::Reset` for `bg` so it inherits the terminal background.
- Ship at least one matched light variant for every dark theme.
- Bind `t` (lowercase) to `theme_index = (theme_index + 1) % THEMES.len()`; persist `theme.name` to disk.
- Test that `gain` is in the green family and `loss` in the red family — prevents palette regressions.
- Pass `&'static Theme` (or `&Theme`) into render functions; never clone per-frame.

Reusable styled helpers:

```rust
pub fn highlight_style(theme: &Theme) -> Style {
    Style::default().bg(theme.highlight_bg).fg(theme.highlight_fg).add_modifier(Modifier::BOLD)
}
pub fn stripe_style(i: usize, theme: &Theme) -> Style {
    if i.is_multiple_of(2) { Style::default().bg(theme.stripe_bg) } else { Style::default() }
}
pub fn key_badge<'a>(key: &str, theme: &Theme) -> Span<'a> {
    Span::styled(format!(" {key} "), Style::default().fg(theme.key_fg).bg(theme.key_bg).add_modifier(Modifier::BOLD))
}
```

## 5. Centered popup / overlay

Every popup uses the same `centered_rect` + `Clear` + bordered `Block` recipe. Render after the main layout, ignore non-popup keys when one is open.

```rust
pub fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let v = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ]).split(r);
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ]).split(v[1])[1]
}

fn render_popup(frame: &mut Frame, theme: &Theme, items: Vec<ListItem>, state: &mut ListState) {
    let area = centered_rect(40, 50, frame.area());
    frame.render_widget(Clear, area);
    let list = List::new(items)
        .block(Block::default()
            .title(" Title ")
            .borders(Borders::ALL)
            .border_style(Style::default().fg(theme.border))
            .style(Style::default().bg(theme.bg)))
        .highlight_style(highlight_style(theme))
        .highlight_symbol("▸ ");
    frame.render_stateful_widget(list, area, state);
}
```

Conventions:

- Always `Clear` the popup area first, otherwise the underlying frame bleeds through.
- Always set `.style(bg(theme.bg))` on the popup `Block` so light themes look right.
- For multi-section popups, build a vertical `Layout` inside the popup area.
- `Esc` closes the popup; popup keys take priority over normal mode keys.

## 6. UTF-8 / CJK aware text helpers

Never use `s.len()` or byte slicing for display widths. Use `unicode-width` for column counts and char iteration for slicing.

Add to `Cargo.toml`:

```toml
unicode-width = "0.2"
```

Helpers (drop into `ui/text.rs`):

```rust
use unicode_width::UnicodeWidthChar;

/// Sum of terminal columns for the first `n` chars (CJK = 2, combining = 0).
pub fn display_width(s: &str, n: usize) -> usize {
    s.chars().take(n).map(|c| c.width().unwrap_or(0)).sum()
}

/// Truncate to `max_width` chars (not bytes), appending an ellipsis when cut.
pub fn truncate_str(s: &str, max_width: usize) -> String {
    if s.chars().count() <= max_width { return s.to_string(); }
    let head: String = s.chars().take(max_width.saturating_sub(1)).collect();
    format!("{head}…")
}

/// Case-insensitive multi-match highlighter.
pub fn highlight_text(text: &str, needle: &str, normal: Style, hit: Style) -> Vec<Span<'static>> {
    if needle.is_empty() { return vec![Span::styled(text.to_string(), normal)]; }
    let tl = text.to_lowercase();
    let nl = needle.to_lowercase();
    if text.chars().count() != tl.chars().count() {
        return vec![Span::styled(text.to_string(), normal)];
    }
    let tc: Vec<char> = tl.chars().collect();
    let nc: Vec<char> = nl.chars().collect();
    if nc.len() > tc.len() { return vec![Span::styled(text.to_string(), normal)]; }
    let mut hits = Vec::new();
    for i in 0..=tc.len() - nc.len() {
        if tc[i..i+nc.len()] == nc[..] { hits.push((i, i+nc.len())); }
    }
    if hits.is_empty() { return vec![Span::styled(text.to_string(), normal)]; }
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut pos = 0;
    for (s, e) in hits {
        if pos < s { out.push(Span::styled(chars[pos..s].iter().collect::<String>(), normal)); }
        out.push(Span::styled(chars[s..e].iter().collect::<String>(), hit));
        pos = e;
    }
    if pos < chars.len() { out.push(Span::styled(chars[pos..].iter().collect::<String>(), normal)); }
    out
}
```

Rules:

- All popup, header, footer, and table-cell strings must pass through `truncate_str` before rendering.
- Use Unicode arrows / glyphs directly in source — they're handled correctly by ratatui.
- For sparkline / spinner glyphs, prefer `'\u{XXXX}'` escapes in `const` arrays.

## 7. Mouse-driven draggable split

Pattern: store the split ratio (`f64` in `[0.0, 1.0]`) and a `dragging: bool` flag on the app. On `Down` start dragging, on `Drag` recompute the ratio from the mouse column, on `Up` stop.

```rust
pub struct App {
    /// Left panel's share of the horizontal split (0.0-1.0). Persisted.
    pub split: f64,
    /// True while the user holds the left mouse button on the divider.
    pub dragging: bool,
}
```

Mouse handler:

```rust
use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};

pub fn handle_mouse(&mut self, m: MouseEvent) {
    if !self.split_panel_open { return; }
    match m.kind {
        MouseEventKind::Down(MouseButton::Left) => self.dragging = true,
        MouseEventKind::Drag(MouseButton::Left) if self.dragging => {
            let col = f64::from(m.column);
            let width = f64::from(
                crossterm::terminal::size().map_or(80, |(w, _)| w).max(1),
            );
            self.split = (col / width).clamp(0.2, 0.8);
        }
        MouseEventKind::Up(MouseButton::Left) => self.dragging = false,
        MouseEventKind::ScrollDown => self.scroll_down(),
        MouseEventKind::ScrollUp   => self.scroll_up(),
        _ => {}
    }
}
```

Render side — convert the ratio to integer constraints:

```rust
let left_pct  = (self.split * 100.0).round().clamp(20.0, 80.0) as u16;
let right_pct = 100 - left_pct;
let cols = Layout::default()
    .direction(Direction::Horizontal)
    .constraints([Constraint::Percentage(left_pct), Constraint::Percentage(right_pct)])
    .split(area);
```

Rules:

- Always clamp the ratio (0.2..=0.8 is a sane default) so a panel can never disappear.
- Reset `dragging = false` whenever the panel closes or focus leaves the splittable view.
- Persist `split` to the same config file as `theme.name`.
- For vertical splits, swap `column`/`width` for `row`/`height`.

## 8. File / module layout (recommended)

```
src/
├── main.rs              # terminal lifecycle + run_loop only
├── app.rs               # App state, key/mouse handlers, ticks
├── event.rs             # crossterm -> Event::{Key,Mouse,Tick,Resize}
├── worker.rs            # background fetches -> drain_results()
└── ui/
    ├── mod.rs           # draw() dispatcher + draw_*_layout helpers
    ├── helpers.rs       # size_guard, key_badge, stripe_style, ...
    ├── text.rs          # display_width, truncate_str, highlight_text
    ├── popup.rs         # centered_rect + render_popup variants
    ├── header.rs        # ...one file per panel
    └── footer.rs
```

Keep `app.rs` free of `ratatui::widgets::*` imports beyond stateful widgets (`TableState`, `ListState`); all rendering belongs under `ui/`.

## 9. Code quality checklist

### Error handling
- No `unwrap()` in non-test code. Use `?` with `.context()` or explicit match.
- `.expect()` only with a safety comment explaining the invariant.
- Terminal restore on error. `disable_raw_mode` + `LeaveAlternateScreen` must execute even when `run_loop` returns `Err`.
- `anyhow::Result` in `main` with `.context()` on each fallible step.

### Rendering and layout
- No logic in `draw()`. Rendering functions should be pure transforms from state to frame.
- Clamp all user-controlled sizes. Split ratios, popup dimensions, and scroll offsets must be clamped.
- Saturating arithmetic for TUI math. Use `.saturating_sub()` for all `u16` subtraction.
- Safe casts. `as u16` from larger types must be preceded by `.min()` or bounds check.
- No indexing without bounds check. Use `.get()` for list/table items.

### State management
- `app.rs` owns all mutable state. UI modules receive `&App` read-only.
- No `ratatui::widgets::*` imports in `app.rs` beyond stateful widgets.

### Event handling
- Filter `KeyEventKind::Press` only unless deliberately supporting key repeat.
- Mouse events check bounds before acting.
- Tick rate is configurable or constant (default 250ms).

### Unicode and text
- Use `unicode-width` for display width, not `.len()` or `.chars().count()`.
- Truncation respects grapheme clusters.
- Test with CJK / emoji.

### Terminal safety
- Always restore terminal state, even on panic. Consider a `Drop` guard.
- No `print!` / `println!` while in raw mode.
- Handle `Resize` events — redraw immediately.

### Testing
- Render to `TestBackend` for snapshot/assertion tests.
- Unit test state transitions without rendering.
- Mock event sources for interaction flow tests.

## Reference apps

- [pastel-market](https://github.com/pastel-sketchbook/pastel-market) — full theme system, draggable chart-detail split, multi-overlay.
- [kube-log-viewer](https://github.com/pastel-sketchbook/kube-log-viewer) — clean popup module, two-column help overlay.
- [yp](https://github.com/pastel-sketchbook/yp) — display_width / truncate_str / highlight_text, PiP minimal layout.
