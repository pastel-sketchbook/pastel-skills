---
name: ratatui-patterns
description: Common patterns for building ratatui + crossterm TUIs in Pastel Sketchbook Rust projects — terminal lifecycle, app layout, theme system, mouse-driven draggable split resizing, centered popup overlays, and UTF-8 / CJK aware string helpers. Use when scaffolding a new ratatui app, adding a popup or help overlay, building a multi-theme TUI, supporting mouse-resizable panels, or rendering text that may contain non-ASCII characters.
---

# Ratatui TUI Patterns

Battle-tested patterns extracted from `pastel-market`, `kube-log-viewer`, and `yp`. Use these as the default approach in any Pastel Sketchbook ratatui app — copy, adapt, do **not** reinvent.

## When to use

Reach for this skill whenever the task touches:

- bringing up or tearing down a ratatui terminal,
- splitting the screen into header / body / status / footer,
- adding a centered popup, help overlay, or modal,
- letting the user drag a vertical/horizontal split with the mouse,
- adding or extending a multi-theme color system,
- rendering text containing CJK, emoji, or accented characters.

## 1. Terminal lifecycle (main.rs)

Always enter the alternate screen, enable raw mode, and **enable mouse capture** — even apps that don't yet use the mouse benefit from scroll. Always restore on exit, even on error.

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

Every screen should follow the same vertical skeleton. This keeps muscle memory across apps.

```text
┌─ header  (Length 3 — title, tabs, indicators) ─┐
│                                                │
│  body    (Min 5    — flexible content)         │
│                                                │
├─ status  (Length 1 — one-line transient msg)   │
└─ footer  (Length 1 — keybinding hints)         │
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

Render overlays (chart, popup, help) **after** the main layout so they appear on top.

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

pub const THEMES: &[Theme] = &[
    // Default — dark, cyan accent, classic market green/red
    Theme {
        name: "Default",
        bg: Color::Reset,
        fg: Color::White,
        accent: Color::Rgb(0, 217, 255),
        muted: Color::DarkGray,
        border: Color::DarkGray,
        gain: Color::Rgb(0, 200, 80),
        loss: Color::Rgb(255, 80, 80),
        error: Color::Rgb(255, 80, 80),
        status: Color::Rgb(0, 217, 255),
        highlight_bg: Color::Rgb(40, 40, 60),
        highlight_fg: Color::Rgb(255, 220, 100),
        stripe_bg: Color::Rgb(28, 28, 34),
        key_bg: Color::DarkGray,
        key_fg: Color::Black,
        title: Color::Rgb(0, 217, 255),
        tag: Color::Rgb(180, 140, 255),
        panel_bg: Color::Rgb(24, 24, 30),
        chart_bg: Color::Rgb(18, 18, 24),
    },
    // Gruvbox Dark
    Theme {
        name: "Gruvbox",
        bg: Color::Rgb(29, 32, 33),
        fg: Color::Rgb(235, 219, 178),
        accent: Color::Rgb(215, 153, 33),
        muted: Color::Rgb(146, 131, 116),
        border: Color::Rgb(62, 57, 54),
        gain: Color::Rgb(184, 187, 38),
        loss: Color::Rgb(251, 73, 52),
        error: Color::Rgb(251, 73, 52),
        status: Color::Rgb(184, 187, 38),
        highlight_bg: Color::Rgb(50, 48, 47),
        highlight_fg: Color::Rgb(250, 189, 47),
        stripe_bg: Color::Rgb(40, 40, 40),
        key_bg: Color::Rgb(80, 73, 69),
        key_fg: Color::Rgb(235, 219, 178),
        title: Color::Rgb(250, 189, 47),
        tag: Color::Rgb(131, 165, 152),
        panel_bg: Color::Rgb(37, 36, 36),
        chart_bg: Color::Rgb(22, 24, 25),
    },
    // Solarized Dark
    Theme {
        name: "Solarized",
        bg: Color::Rgb(0, 43, 54),
        fg: Color::Rgb(253, 246, 227),
        accent: Color::Rgb(42, 161, 152),
        muted: Color::Rgb(131, 148, 150),
        border: Color::Rgb(16, 58, 68),
        gain: Color::Rgb(133, 153, 0),
        loss: Color::Rgb(220, 50, 47),
        error: Color::Rgb(220, 50, 47),
        status: Color::Rgb(181, 137, 0),
        highlight_bg: Color::Rgb(7, 54, 66),
        highlight_fg: Color::Rgb(253, 246, 227),
        stripe_bg: Color::Rgb(3, 48, 58),
        key_bg: Color::Rgb(88, 110, 117),
        key_fg: Color::Rgb(253, 246, 227),
        title: Color::Rgb(181, 137, 0),
        tag: Color::Rgb(108, 113, 196),
        panel_bg: Color::Rgb(7, 54, 66),
        chart_bg: Color::Rgb(0, 36, 46),
    },
    // Ayu Dark
    Theme {
        name: "Ayu",
        bg: Color::Rgb(10, 14, 20),
        fg: Color::Rgb(191, 191, 191),
        accent: Color::Rgb(255, 153, 64),
        muted: Color::Rgb(92, 103, 115),
        border: Color::Rgb(40, 44, 52),
        gain: Color::Rgb(125, 210, 80),
        loss: Color::Rgb(240, 113, 113),
        error: Color::Rgb(240, 113, 113),
        status: Color::Rgb(85, 180, 211),
        highlight_bg: Color::Rgb(20, 24, 32),
        highlight_fg: Color::Rgb(255, 180, 84),
        stripe_bg: Color::Rgb(15, 19, 26),
        key_bg: Color::Rgb(60, 66, 76),
        key_fg: Color::Rgb(191, 191, 191),
        title: Color::Rgb(255, 180, 84),
        tag: Color::Rgb(210, 154, 230),
        panel_bg: Color::Rgb(18, 22, 30),
        chart_bg: Color::Rgb(6, 9, 14),
    },
    // Flexoki Dark
    Theme {
        name: "Flexoki",
        bg: Color::Rgb(16, 15, 15),
        fg: Color::Rgb(206, 205, 195),
        accent: Color::Rgb(36, 131, 123),
        muted: Color::Rgb(135, 133, 128),
        border: Color::Rgb(40, 39, 38),
        gain: Color::Rgb(208, 162, 21),
        loss: Color::Rgb(209, 77, 65),
        error: Color::Rgb(209, 77, 65),
        status: Color::Rgb(208, 162, 21),
        highlight_bg: Color::Rgb(28, 27, 26),
        highlight_fg: Color::Rgb(208, 162, 21),
        stripe_bg: Color::Rgb(22, 21, 20),
        key_bg: Color::Rgb(52, 51, 49),
        key_fg: Color::Rgb(206, 205, 195),
        title: Color::Rgb(208, 162, 21),
        tag: Color::Rgb(142, 139, 206),
        panel_bg: Color::Rgb(24, 23, 22),
        chart_bg: Color::Rgb(10, 9, 9),
    },
    // Zoegi Dark
    Theme {
        name: "Zoegi",
        bg: Color::Rgb(20, 20, 20),
        fg: Color::Rgb(204, 204, 204),
        accent: Color::Rgb(64, 128, 104),
        muted: Color::Rgb(89, 89, 89),
        border: Color::Rgb(48, 48, 48),
        gain: Color::Rgb(92, 168, 112),
        loss: Color::Rgb(204, 92, 92),
        error: Color::Rgb(204, 92, 92),
        status: Color::Rgb(86, 139, 153),
        highlight_bg: Color::Rgb(34, 34, 34),
        highlight_fg: Color::Rgb(128, 200, 160),
        stripe_bg: Color::Rgb(27, 27, 27),
        key_bg: Color::Rgb(64, 64, 64),
        key_fg: Color::Rgb(204, 204, 204),
        title: Color::Rgb(128, 200, 160),
        tag: Color::Rgb(150, 180, 210),
        panel_bg: Color::Rgb(28, 28, 28),
        chart_bg: Color::Rgb(14, 14, 14),
    },
    // FFE Dark
    Theme {
        name: "FFE Dark",
        bg: Color::Rgb(30, 35, 43),
        fg: Color::Rgb(216, 222, 233),
        accent: Color::Rgb(79, 214, 190),
        muted: Color::Rgb(155, 162, 175),
        border: Color::Rgb(59, 66, 82),
        gain: Color::Rgb(161, 239, 211),
        loss: Color::Rgb(255, 117, 127),
        error: Color::Rgb(255, 117, 127),
        status: Color::Rgb(161, 239, 211),
        highlight_bg: Color::Rgb(46, 52, 64),
        highlight_fg: Color::Rgb(240, 169, 136),
        stripe_bg: Color::Rgb(26, 31, 39),
        key_bg: Color::Rgb(59, 66, 82),
        key_fg: Color::Rgb(216, 222, 233),
        title: Color::Rgb(240, 169, 136),
        tag: Color::Rgb(137, 220, 235),
        panel_bg: Color::Rgb(26, 31, 39),
        chart_bg: Color::Rgb(22, 26, 34),
    },
    // Postrboard Dark
    Theme {
        name: "Postrboard",
        bg: Color::Rgb(26, 27, 38),
        fg: Color::Rgb(226, 232, 240),
        accent: Color::Rgb(79, 182, 232),
        muted: Color::Rgb(124, 141, 163),
        border: Color::Rgb(42, 45, 61),
        gain: Color::Rgb(132, 204, 22),
        loss: Color::Rgb(248, 113, 113),
        error: Color::Rgb(248, 113, 113),
        status: Color::Rgb(132, 204, 22),
        highlight_bg: Color::Rgb(54, 58, 79),
        highlight_fg: Color::Rgb(251, 138, 77),
        stripe_bg: Color::Rgb(30, 31, 43),
        key_bg: Color::Rgb(54, 58, 79),
        key_fg: Color::Rgb(226, 232, 240),
        title: Color::Rgb(251, 138, 77),
        tag: Color::Rgb(96, 165, 250),
        panel_bg: Color::Rgb(22, 23, 31),
        chart_bg: Color::Rgb(18, 19, 28),
    },
    // --- Light themes ---
    // Default Light
    Theme {
        name: "Default Light",
        bg: Color::Reset,
        fg: Color::Rgb(40, 40, 50),
        accent: Color::Rgb(0, 140, 180),
        muted: Color::Rgb(120, 120, 130),
        border: Color::Rgb(180, 180, 190),
        gain: Color::Rgb(0, 140, 50),
        loss: Color::Rgb(200, 40, 40),
        error: Color::Rgb(200, 40, 40),
        status: Color::Rgb(0, 140, 180),
        highlight_bg: Color::Rgb(220, 225, 235),
        highlight_fg: Color::Rgb(30, 30, 40),
        stripe_bg: Color::Rgb(240, 240, 245),
        key_bg: Color::Rgb(180, 180, 190),
        key_fg: Color::Rgb(40, 40, 50),
        title: Color::Rgb(0, 140, 180),
        tag: Color::Rgb(100, 80, 180),
        panel_bg: Color::Rgb(235, 235, 240),
        chart_bg: Color::Rgb(245, 245, 248),
    },
    // Gruvbox Light
    Theme {
        name: "Gruvbox Light",
        bg: Color::Rgb(251, 241, 199),
        fg: Color::Rgb(60, 56, 54),
        accent: Color::Rgb(215, 153, 33),
        muted: Color::Rgb(146, 131, 116),
        border: Color::Rgb(213, 196, 161),
        gain: Color::Rgb(121, 116, 14),
        loss: Color::Rgb(204, 36, 29),
        error: Color::Rgb(204, 36, 29),
        status: Color::Rgb(121, 116, 14),
        highlight_bg: Color::Rgb(235, 219, 178),
        highlight_fg: Color::Rgb(60, 56, 54),
        stripe_bg: Color::Rgb(249, 236, 186),
        key_bg: Color::Rgb(213, 196, 161),
        key_fg: Color::Rgb(60, 56, 54),
        title: Color::Rgb(215, 153, 33),
        tag: Color::Rgb(69, 133, 136),
        panel_bg: Color::Rgb(242, 233, 185),
        chart_bg: Color::Rgb(245, 236, 192),
    },
    // Solarized Light
    Theme {
        name: "Solarized Light",
        bg: Color::Rgb(253, 246, 227),
        fg: Color::Rgb(88, 110, 117),
        accent: Color::Rgb(42, 161, 152),
        muted: Color::Rgb(147, 161, 161),
        border: Color::Rgb(220, 212, 188),
        gain: Color::Rgb(133, 153, 0),
        loss: Color::Rgb(220, 50, 47),
        error: Color::Rgb(220, 50, 47),
        status: Color::Rgb(133, 153, 0),
        highlight_bg: Color::Rgb(238, 232, 213),
        highlight_fg: Color::Rgb(7, 54, 66),
        stripe_bg: Color::Rgb(245, 239, 218),
        key_bg: Color::Rgb(220, 212, 188),
        key_fg: Color::Rgb(88, 110, 117),
        title: Color::Rgb(181, 137, 0),
        tag: Color::Rgb(108, 113, 196),
        panel_bg: Color::Rgb(238, 232, 213),
        chart_bg: Color::Rgb(247, 241, 222),
    },
    // Flexoki Light
    Theme {
        name: "Flexoki Light",
        bg: Color::Rgb(255, 252, 240),
        fg: Color::Rgb(16, 15, 15),
        accent: Color::Rgb(36, 131, 123),
        muted: Color::Rgb(111, 110, 105),
        border: Color::Rgb(230, 228, 217),
        gain: Color::Rgb(102, 128, 11),
        loss: Color::Rgb(209, 77, 65),
        error: Color::Rgb(209, 77, 65),
        status: Color::Rgb(102, 128, 11),
        highlight_bg: Color::Rgb(242, 240, 229),
        highlight_fg: Color::Rgb(16, 15, 15),
        stripe_bg: Color::Rgb(247, 245, 234),
        key_bg: Color::Rgb(230, 228, 217),
        key_fg: Color::Rgb(16, 15, 15),
        title: Color::Rgb(36, 131, 123),
        tag: Color::Rgb(100, 92, 187),
        panel_bg: Color::Rgb(244, 241, 230),
        chart_bg: Color::Rgb(250, 247, 235),
    },
    // Ayu Light
    Theme {
        name: "Ayu Light",
        bg: Color::Rgb(252, 252, 252),
        fg: Color::Rgb(92, 97, 102),
        accent: Color::Rgb(255, 153, 64),
        muted: Color::Rgb(153, 160, 166),
        border: Color::Rgb(207, 209, 210),
        gain: Color::Rgb(133, 179, 4),
        loss: Color::Rgb(240, 113, 113),
        error: Color::Rgb(240, 113, 113),
        status: Color::Rgb(133, 179, 4),
        highlight_bg: Color::Rgb(230, 230, 230),
        highlight_fg: Color::Rgb(92, 97, 102),
        stripe_bg: Color::Rgb(243, 244, 245),
        key_bg: Color::Rgb(207, 209, 210),
        key_fg: Color::Rgb(92, 97, 102),
        title: Color::Rgb(255, 153, 64),
        tag: Color::Rgb(163, 122, 204),
        panel_bg: Color::Rgb(242, 242, 242),
        chart_bg: Color::Rgb(246, 246, 246),
    },
    // Zoegi Light
    Theme {
        name: "Zoegi Light",
        bg: Color::Rgb(255, 255, 255),
        fg: Color::Rgb(51, 51, 51),
        accent: Color::Rgb(55, 121, 97),
        muted: Color::Rgb(89, 89, 89),
        border: Color::Rgb(230, 230, 230),
        gain: Color::Rgb(55, 121, 97),
        loss: Color::Rgb(204, 92, 92),
        error: Color::Rgb(204, 92, 92),
        status: Color::Rgb(55, 121, 97),
        highlight_bg: Color::Rgb(235, 235, 235),
        highlight_fg: Color::Rgb(51, 51, 51),
        stripe_bg: Color::Rgb(247, 247, 247),
        key_bg: Color::Rgb(230, 230, 230),
        key_fg: Color::Rgb(51, 51, 51),
        title: Color::Rgb(55, 121, 97),
        tag: Color::Rgb(80, 120, 160),
        panel_bg: Color::Rgb(245, 245, 245),
        chart_bg: Color::Rgb(250, 250, 250),
    },
    // FFE Light
    Theme {
        name: "FFE Light",
        bg: Color::Rgb(232, 236, 240),
        fg: Color::Rgb(30, 35, 43),
        accent: Color::Rgb(42, 157, 132),
        muted: Color::Rgb(74, 80, 96),
        border: Color::Rgb(201, 205, 214),
        gain: Color::Rgb(26, 138, 110),
        loss: Color::Rgb(201, 67, 78),
        error: Color::Rgb(201, 67, 78),
        status: Color::Rgb(26, 138, 110),
        highlight_bg: Color::Rgb(221, 225, 232),
        highlight_fg: Color::Rgb(192, 121, 32),
        stripe_bg: Color::Rgb(245, 247, 250),
        key_bg: Color::Rgb(201, 205, 214),
        key_fg: Color::Rgb(30, 35, 43),
        title: Color::Rgb(192, 121, 32),
        tag: Color::Rgb(58, 142, 164),
        panel_bg: Color::Rgb(245, 247, 250),
        chart_bg: Color::Rgb(227, 231, 236),
    },
    // Postrboard Light
    Theme {
        name: "Postrboard Light",
        bg: Color::Rgb(250, 250, 250),
        fg: Color::Rgb(17, 24, 39),
        accent: Color::Rgb(2, 132, 199),
        muted: Color::Rgb(100, 116, 139),
        border: Color::Rgb(203, 213, 225),
        gain: Color::Rgb(77, 124, 15),
        loss: Color::Rgb(220, 38, 38),
        error: Color::Rgb(220, 38, 38),
        status: Color::Rgb(77, 124, 15),
        highlight_bg: Color::Rgb(226, 232, 240),
        highlight_fg: Color::Rgb(194, 65, 12),
        stripe_bg: Color::Rgb(248, 250, 252),
        key_bg: Color::Rgb(203, 213, 225),
        key_fg: Color::Rgb(17, 24, 39),
        title: Color::Rgb(194, 65, 12),
        tag: Color::Rgb(12, 74, 110),
        panel_bg: Color::Rgb(241, 245, 249),
        chart_bg: Color::Rgb(244, 244, 244),
    },
];

pub fn theme_index_by_name(name: &str) -> usize {
    THEMES.iter().position(|t| t.name == name).unwrap_or(0)
}
```

Rules:

- **Default theme is index 0** and uses `Color::Reset` for `bg` so it inherits the terminal background.
- Ship at least one matched **light** variant for every dark theme.
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

Every popup uses the same `centered_rect` + `Clear` + bordered `Block` recipe. Render *after* the main layout, ignore non-popup keys when one is open.

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
    frame.render_widget(Clear, area);                          // wipe what's underneath
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
- For multi-section popups (list + footer preview), build a vertical `Layout` inside the popup area and use `Borders::TOP|LEFT|RIGHT` on the top block and `Borders::BOTTOM|LEFT|RIGHT` on the bottom — this looks like one bordered box.
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

/// Case-insensitive multi-match highlighter. Falls back to a single span if
/// `to_lowercase()` changes the char count (e.g. Turkish İ → i + combining dot)
/// because position mapping would be unsafe.
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

- All popup, header, footer, and table-cell strings must pass through `truncate_str` (or `display_width`-aware logic) before being rendered.
- Use Unicode arrows / glyphs (`▸ ▲ ▼ ▶ ⟳ ⏸ …`) directly in source — they're handled correctly by ratatui.
- For sparkline / spinner glyphs, prefer `'\u{XXXX}'` escapes in `const` arrays so the file stays ASCII-clean.

## 7. Mouse-driven draggable split

Pattern: store the split ratio (`f64` in `[0.0, 1.0]`) and a `dragging: bool` flag on the app. On `Down` start dragging, on `Drag` recompute the ratio from the mouse column, on `Up` stop.

```rust
pub struct App {
    /// Left panel's share of the horizontal split (0.0–1.0). Persisted.
    pub split: f64,
    /// True while the user holds the left mouse button on the divider.
    pub dragging: bool,
    // ...
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

Render side — convert the ratio to integer constraints using percentages:

```rust
let left_pct  = (self.split * 100.0).round().clamp(20.0, 80.0) as u16;
let right_pct = 100 - left_pct;
let cols = Layout::default()
    .direction(Direction::Horizontal)
    .constraints([Constraint::Percentage(left_pct), Constraint::Percentage(right_pct)])
    .split(area);
```

Rules:

- **Always clamp** the ratio (`0.2..=0.8` is a sane default) so a panel can never disappear.
- Reset `dragging = false` whenever the panel closes or focus leaves the splittable view.
- Persist `split` to the same config file as `theme.name` for a consistent restore-on-startup story.
- For vertical splits, swap `column`/`width` for `row`/`height`.

## 8. File / module layout (recommended)

```
src/
├── main.rs              # terminal lifecycle + run_loop only
├── app.rs               # App state, key/mouse handlers, ticks
├── event.rs             # crossterm → Event::{Key,Mouse,Tick,Resize}
├── worker.rs            # background fetches → drain_results()
└── ui/
    ├── mod.rs           # draw() dispatcher + draw_*_layout helpers
    ├── helpers.rs       # size_guard, key_badge, stripe_style, ...
    ├── text.rs          # display_width, truncate_str, highlight_text
    ├── popup.rs         # centered_rect + render_popup variants
    ├── header.rs        # ...one file per panel
    └── footer.rs
```

Keep `app.rs` free of `ratatui::widgets::*` imports beyond stateful widgets (`TableState`, `ListState`); all rendering belongs under `ui/`.

## Reference apps

- [pastel-market](https://github.com/pastel-sketchbook/pastel-market) — full theme system, draggable chart-detail split, multi-overlay (chart + help).
- [kube-log-viewer](https://github.com/pastel-sketchbook/kube-log-viewer) — clean popup module, two-column help overlay, `centered_rect`.
- [yp](https://github.com/pastel-sketchbook/yp) — `display_width` / `truncate_str` / `highlight_text`, PiP minimal layout.
