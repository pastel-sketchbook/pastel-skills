#set page(width: 1600pt, height: 900pt, margin: 0pt)
#set text(font: ("BlexMono Nerd Font Propo", "Avenir Next"), fill: rgb("1e232b"))

#let navy = rgb("1e232b")
#let ink = rgb("4a5060")
#let muted = rgb("7c8496")
#let mint = rgb("d8f0e8")
#let peach = rgb("f5efd8")
#let lavender = rgb("e8ecf0")
#let sky = rgb("dceef4")
#let cream = rgb("f5f7fa")
#let panel = rgb("edf0f4")
#let accent = rgb("2a9d84")
#let coral = rgb("c9434e")
#let gold = rgb("c07920")
#let magenta = rgb("c0587a")
#let blue = rgb("3a8ea4")
#let rule = rgb("c9cdd6")

#let deck_title = "Why uv, ruff, and ty are mandatory"
#let deck_subtitle = "A pragmatic Python tooling baseline for fast, safe projects"

#let icon(label, color: accent) = box(width: 92pt, height: 92pt, stroke: 3pt + color, radius: 24pt, inset: 12pt)[
  #align(center + horizon)[#text(size: 34pt, fill: color, weight: "bold")[#label]]
]

#let foot(n) = place(bottom + right, dx: -52pt, dy: -38pt)[#text(size: 22pt, fill: muted)[#n / 12]]

#let slide(n, bg: cream, title: none, body) = page(fill: bg)[
  #place(top + right, dx: -76pt, dy: 58pt)[#box(width: 250pt, height: 250pt, radius: 125pt, stroke: 1pt + rule)]
  #place(bottom + left, dx: 48pt, dy: -98pt)[#box(width: 360pt, height: 92pt, radius: 46pt, stroke: 1pt + rule)]
  #place(top + left, dx: 64pt, dy: 44pt)[#box(width: 120pt, height: 6pt, fill: accent, radius: 3pt)]
  #if title != none [#place(top + left, dx: 64pt, dy: 82pt)[#text(size: 50pt, weight: "bold", fill: navy)[#title]]]
  #place(top + left, dx: 64pt, dy: if title == none { 92pt } else { 170pt })[
    #box(width: 1470pt, height: if title == none { 720pt } else { 650pt })[#body]
  ]
  #foot(n)
]

#let bullets(items) = block(spacing: 18pt)[
  #for item in items [
    #box(width: 713pt, fill: rgb("ffffff"), radius: 22pt, inset: 20pt, stroke: 1.2pt + rule)[
      #text(size: 27pt, fill: ink)[#text(fill: accent, weight: "bold")[•] #item]
    ]
    #v(12pt)
  ]
]

#let bullets-wide(items) = block(spacing: 18pt)[
  #for item in items [
    #box(width: 1470pt)[#text(size: 34pt, fill: ink)[#text(fill: accent)[•] #item]]
    #v(10pt)
  ]
]

#let code-width(width, body) = box(width: width, fill: panel, radius: 26pt, stroke: 1.5pt + rule)[
  #box(width: width, fill: rgb("e2e7ee"), inset: (x: 24pt, y: 14pt), radius: (top-left: 26pt, top-right: 26pt))[
    #text(size: 18pt, fill: muted, weight: "bold")[project shell]
    #h(18pt)
    #text(size: 18pt, fill: coral)[●]
    #h(8pt)
    #text(size: 18pt, fill: gold)[●]
    #h(8pt)
    #text(size: 18pt, fill: accent)[●]
  ]
  #box(width: width, inset: 26pt)[
    #set text(font: ("BlexMono Nerd Font", "Menlo"), size: 25pt, fill: navy)
    #body
  ]
]

#let code(body) = code-width(713pt)[#body]
#let code-wide(body) = code-width(1470pt)[#body]

#let kw(x) = text(fill: coral, weight: "bold")[#x]
#let fnc(x) = text(fill: accent, weight: "bold")[#x]
#let str(x) = text(fill: gold)[#x]
#let typ(x) = text(fill: accent, weight: "bold")[#x]
#let cm(x) = text(fill: muted)[#x]
#let prop(x) = text(fill: magenta)[#x]
#let num(x) = text(fill: gold)[#x]
#let sh(x) = text(fill: blue, weight: "bold")[#x]

#let card(card_title, copy, color: sky) = box(width: 467pt, height: 250pt, fill: color, radius: 32pt, inset: 28pt, stroke: 1.5pt + rule)[
  #box(fill: rgb("ffffff"), radius: 18pt, inset: (x: 18pt, y: 8pt), stroke: 1pt + rule)[#text(size: 30pt, weight: "bold", fill: navy)[#card_title]]
  #v(20pt)
  #text(size: 23pt, fill: ink)[#copy]
]

#let note(label, copy, color: mint) = box(width: 410pt, fill: color, radius: 26pt, inset: 28pt, stroke: 1.5pt + rule)[
  #text(size: 27pt, weight: "bold", fill: navy)[#label]
  #v(18pt)
  #text(size: 23pt, fill: ink)[#copy]
]

#let pill(label, copy, color: mint) = box(width: 430pt, height: 120pt, fill: rgb("ffffff"), radius: 28pt, inset: 18pt, stroke: 2pt + color)[
  #grid(columns: (78pt, 1fr), gutter: 18pt,
    [#icon(label, color: color)],
    [#align(horizon)[#text(size: 23pt, fill: ink)[#copy]]],
  )
]

#let idea(title, copy, color: mint) = box(width: 712pt, height: 208pt, fill: rgb("ffffff"), radius: 28pt, inset: 24pt, stroke: 1.5pt + color)[
  #box(width: 42pt, height: 6pt, fill: color, radius: 3pt)
  #v(14pt)
  #text(size: 28pt, weight: "bold", fill: navy)[#title]
  #v(12pt)
  #text(size: 21pt, fill: ink)[#copy]
]

#let band(copy, color: accent) = box(width: 1470pt, fill: rgb("ffffff"), radius: 28pt, inset: 28pt, stroke: 1.8pt + color)[
  #align(center)[#text(size: 31pt, weight: "bold", fill: navy)[#copy]]
]

#let step(n, title, copy, color: mint) = box(width: 712pt, height: 208pt, fill: rgb("ffffff"), radius: 28pt, inset: 0pt, stroke: 1.5pt + color)[
  #grid(columns: (138pt, 1fr), gutter: 0pt,
    [#box(width: 138pt, height: 208pt, fill: color, radius: (top-left: 28pt, bottom-left: 28pt), inset: 20pt)[
      #align(center + horizon)[#text(size: 54pt, weight: "bold", fill: rgb("ffffff"))[#n]]
    ]],
    [#box(width: 574pt, height: 208pt, inset: 26pt)[
      #text(size: 30pt, weight: "bold", fill: navy)[#title]
      #v(18pt)
      #text(size: 21pt, fill: ink)[#copy]
    ]],
  )
]

#let metric(value, label, color: accent) = box(width: 174pt, height: 146pt, fill: rgb("ffffff"), radius: 28pt, inset: 14pt, stroke: 2pt + color)[
  #align(center + horizon)[#stack(dir: ttb, spacing: 10pt,
    [#text(size: 42pt, weight: "bold", fill: color)[#value]],
    [#text(size: 17pt, fill: ink)[#label]],
  )]
]

#let split-code-note(code_body, note_label, note_copy, note_color: mint) = grid(columns: (1fr, 420pt), gutter: 36pt,
  [#code-width(1014pt)[#code_body]],
  [#note(note_label, note_copy, color: note_color)],
)

#page(fill: lavender)[
  #place(top + left, dx: 64pt, dy: 44pt)[#box(width: 120pt, height: 6pt, fill: accent, radius: 3pt)]
  #foot(1)
  #place(top + right, dx: -78pt, dy: 86pt)[#box(width: 420pt, height: 420pt, radius: 210pt, stroke: 1.2pt + accent)]
  #place(top + right, dx: -166pt, dy: 170pt)[#box(width: 230pt, height: 230pt, radius: 115pt, stroke: 1.2pt + blue)]
  #place(bottom + left, dx: 48pt, dy: -98pt)[#box(width: 360pt, height: 92pt, radius: 46pt, stroke: 1pt + rule)]
  #place(top + left, dx: 64pt, dy: 92pt)[#box(width: 1470pt, height: 720pt)[#grid(columns: (1fr, 520pt), gutter: 56pt,
    [#block[
      #text(size: 24pt, weight: "bold", fill: accent)[PYTHON PROJECT BASELINE]
      #v(26pt)
      #text(font: ("Libertinus Serif", "Georgia"), size: 82pt, weight: "bold", fill: navy)[Why uv, ruff, and ty are]
      #text(font: ("Libertinus Serif", "Georgia"), size: 90pt, weight: "bold", fill: accent)[mandatory]
      #v(34pt)
      #text(size: 34pt, fill: ink)[#deck_subtitle]
      #v(46pt)
      #box(width: 870pt, fill: rgb("ffffff"), radius: 30pt, inset: 30pt, stroke: 1.5pt + rule)[
        #text(size: 27pt, fill: ink)[For teams that want reproducible setup, fast feedback, and safer changes without turning reviews into tooling debates.]
      ]
    ]],
    [#align(center + horizon)[
      #stack(dir: ttb, spacing: 26pt,
        pill("uv", "Reproducible environments", color: accent),
        pill("R", "Fast formatting and linting", color: coral),
        pill("ty", "Visible type contracts", color: blue),
      )
    ]],
  )]]
]

#slide(2, bg: cream, title: "The baseline promise")[
  #grid(columns: (1fr, 1fr, 1fr), gutter: 34pt,
    [#card("uv", "One tool for Python versions, virtualenvs, dependencies, lockfiles, and scripts.", color: mint)],
    [#card("ruff", "Formatter and linter fast enough to run constantly, not just in CI.", color: peach)],
    [#card("ty", "Static type checks that catch integration bugs before runtime.", color: sky)],
  )
  #v(34pt)
  #box(width: 1470pt, fill: rgb("ffffff"), radius: 28pt, inset: 28pt, stroke: 1.5pt + rule)[
    #align(center)[#text(size: 34pt, fill: navy, weight: "bold")[Together: reproducible setup, instant style feedback, and safer refactors.]]
  ]
  #v(28pt)
  #grid(columns: (1fr, 1fr, 1fr), gutter: 34pt,
    [#note("Setup", "One command gets a new checkout ready.", color: mint)],
    [#note("Review", "Formatting and linting stop being subjective.", color: peach)],
    [#note("Change", "Types expose contracts before production.", color: sky)],
  )
]

#slide(3, bg: sky, title: "Why mandatory, not optional?")[
  #grid(columns: (1fr, 1fr), gutter: 34pt, row-gutter: 32pt,
    [#idea("Optional tools create optional quality", "If teams can skip the baseline, every project develops a different failure mode.", color: accent)],
    [#idea("First five minutes should be identical", "Install, sync, lint, typecheck, and test should not require local archaeology.", color: blue)],
    [#idea("Inconsistency compounds", "Onboarding, CI, reviews, and releases all pay for tool drift.", color: coral)],
    [#idea("Automation beats taste debates", "Make quality enforceable by command instead of preference.", color: gold)],
  )
  #v(28pt)
  #band("Mandates turn team preference into repeatable project behavior.", color: blue)
]

#slide(4, bg: mint, title: "uv: make setup boring")[
  #grid(columns: (1fr, 1fr), gutter: 44pt,
    [#bullets((
      "Creates and manages environments quickly.",
      "Locks dependencies for repeatable installs.",
      "Runs commands inside the project environment.",
      "Reduces pip, venv, pyenv, and poetry drift.",
    ))],
    [#code[
      #sh("uv") python install #num("3.12")\
      #sh("uv") init billing-api\
      #sh("uv") add fastapi pydantic\
      #sh("uv") add #raw("--dev") pytest ruff ty\
      #sh("uv") run pytest
    ]],
  )
  #v(36pt)
  #band("The boring path is the scalable path: install, sync, run, repeat.", color: accent)
]

#slide(5, bg: cream, title: "uv gives every contributor the same path")[
  #grid(columns: (1fr, 420pt), gutter: 36pt,
    [#code-width(1014pt)[
      #cm("# pyproject.toml")\
      #prop("[project]")\
      requires-python = #str("\">=3.12\"")\
      dependencies = [#str("\"fastapi\""), #str("\"pydantic\"")]\
      \
      #prop("[dependency-groups]")\
      dev = [#str("\"pytest\""), #str("\"ruff\""), #str("\"ty\"")]
    ]],
    [#note("Why it matters", "A lockfile plus `uv sync` turns onboarding and CI from archaeology into a deterministic step.", color: mint)],
  )
]

#slide(6, bg: peach, title: "ruff: one fast gate for style and defects")[
  #grid(columns: (1fr, 1fr), gutter: 44pt,
    [#code[
      #sh("uv") run ruff format .\
      #sh("uv") run ruff check . #raw("--fix")
    ]],
    [#bullets((
      "Replaces slow stacks of formatters and linters.",
      "Finds unused imports, unsafe patterns, and style drift.",
      "Auto-fixes the boring stuff before review.",
      "Makes formatting a command, not a conversation.",
    ))],
  )
  #v(36pt)
  #band("Reviews should focus on design and behavior, not import order.", color: gold)
]

#slide(7, bg: cream, title: "ruff catches real bugs early")[
  #grid(columns: (1fr, 420pt), gutter: 36pt,
    [#code-width(1014pt)[
      #kw("from") pathlib #kw("import") Path\
      \
      #kw("def") #fnc("load_config")#text[(path: ]#typ("str")#text[) -> ]#typ("dict")#raw("[str, str]:")\
      ····file_path = #fnc("Path")#text[(path)]\
      ····#kw("if") #kw("not") file_path.exists:\
      ········#kw("return") {}\
      ····#kw("return") #fnc("parse_config")#text[(file_path.read_text())]
    ]],
    [#note("Review saved", "Ruff flags suspicious callable misuse, undefined names, unused imports, and common review distractions.", color: peach)],
  )
]

#slide(8, bg: lavender, title: "ty: make contracts visible")[
  #grid(columns: (1fr, 1fr), gutter: 44pt,
    [#bullets((
      "Checks function boundaries and data flow.",
      "Protects refactors across files.",
      "Documents intent without prose comments.",
      "Complements tests; it does not replace them.",
    ))],
    [#code[
      #kw("def") #fnc("total_cents")#text[(items: ]#typ("list")#raw("[int]")#text[) -> ]#typ("int")#text[:]\
      ····#kw("return") #fnc("sum")#text[(items)]\
      \
      subtotal = #fnc("total_cents")#raw("([")#num("1299")#raw(", ")#num("2500")#raw("])")\
      label: #typ("str") = subtotal  #cm("# type error")
    ]],
  )
  #v(36pt)
  #band("Types make incorrect wiring visible before runtime paths are exercised.", color: blue)
]

#slide(9, bg: sky, title: "A practical mandatory workflow")[
  #grid(columns: (1fr, 420pt), gutter: 36pt,
    [#code-width(1014pt)[
      #sh("uv") sync\
      #sh("uv") run ruff format .\
      #sh("uv") run ruff check .\
      #sh("uv") run ty check\
      #sh("uv") run pytest
    ]],
    [#note("Mandate", "Run this locally, optionally in pre-commit, and always in CI before merge.", color: lavender)],
  )
  #v(30pt)
  #grid(columns: (174pt, 174pt, 174pt, 1fr), gutter: 24pt,
    [#metric("1", "local path", color: accent)],
    [#metric("1", "pre-commit", color: coral)],
    [#metric("1", "CI gate", color: blue)],
    [#box(width: 858pt, height: 146pt, fill: rgb("ffffff"), radius: 28pt, inset: 28pt, stroke: 1.5pt + blue)[
      #align(horizon)[#text(size: 31pt, weight: "bold", fill: navy)[Same command path locally, in pre-commit, and in CI.]]
    ]],
  )
]

#slide(10, bg: cream, title: "Common objections")[
  #grid(columns: (1fr, 1fr), gutter: 34pt, row-gutter: 32pt,
    [#idea("Too strict?", "Start small, then tighten. Mandatory does not mean maximal on day one.", color: coral)],
    [#idea("Too new?", "Pin versions and keep upgrade PRs explicit.", color: blue)],
    [#idea("Types slow us down?", "Unclear contracts slow you down later; annotate boundaries first.", color: accent)],
    [#idea("CI already tests?", "Tests check examples; lint and types check broad mistake classes.", color: gold)],
  )
  #v(28pt)
  #band("Adopt progressively, but make the baseline non-negotiable.", color: coral)
]

#slide(11, bg: mint, title: "Adoption checklist")[
  #grid(columns: (1fr, 1fr), gutter: 34pt, row-gutter: 32pt,
    [#step("01", "Declare", "Add `requires-python`, dependencies, and dev dependency group to `pyproject.toml`.", color: accent)],
    [#step("02", "Lock", "Commit the lockfile and document `uv sync` as the setup path.", color: blue)],
    [#step("03", "Gate", "Add `ruff format`, `ruff check`, `ty check`, and tests to CI.", color: coral)],
    [#step("04", "Prevent", "Fix existing findings once; prevent regressions forever.", color: gold)],
  )
  #v(28pt)
  #band("One baseline, one CI gate, one documented path for every project.", color: accent)
]

#slide(12, bg: lavender, title: "Takeaway")[
  #grid(columns: (360pt, 1fr), gutter: 44pt,
    [#stack(dir: ttb, spacing: 24pt,
      metric("uv", "environment", color: accent),
      metric("ruff", "quality", color: coral),
      metric("ty", "contracts", color: blue),
    )],
    [#box(width: 1066pt, fill: rgb("ffffff"), radius: 36pt, inset: 38pt, stroke: 1.8pt + accent)[
      #text(size: 44pt, weight: "bold", fill: navy)[Make the reliable path the default path.]
      #v(24pt)
      #text(size: 31pt, fill: ink)[Mandatory tooling is not bureaucracy. It is the cheapest way to make every Python project easier to trust, review, onboard, and change.]
    ]],
  )
  #v(34pt)
  #band("uv + ruff + ty = reproducible setup, fast feedback, safer change.", color: accent)
]
