## Build-time syntax highlighting for fenced code blocks. Rewrites the
## `<pre><code class="language-NAME">…</code></pre>` blocks md4c emits into
## `<span class="hl-…">` token spans, for the languages Nim's stdlib `highlite`
## understands. Blocks in an unsupported or absent language are left unchanged.

import std/strutils
import packages/docutils/highlite

const
  preOpen = "<pre><code class=\"language-"
  codeClose = "</code></pre>"

func htmlEscape(s: string): string =
  ## Re-escape source for HTML text, matching the five entities md4c emits.
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#x27;"
    else: result.add c

func htmlUnescape(s: string): string =
  ## Reverse md4c's escaping to recover the original source before tokenizing.
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '&':
      if s.continuesWith("amp;", i + 1): result.add '&'; i += 5
      elif s.continuesWith("lt;", i + 1): result.add '<'; i += 4
      elif s.continuesWith("gt;", i + 1): result.add '>'; i += 4
      elif s.continuesWith("quot;", i + 1): result.add '"'; i += 6
      elif s.continuesWith("#x27;", i + 1): result.add '\''; i += 6
      else: result.add '&'; inc i
    else:
      result.add s[i]; inc i

func cssClass(t: TokenClass): string =
  ## Map a highlite token class to a CSS class ("" = emit the token as plain text).
  case t
  of gtKeyword, gtKey: "hl-keyword" # gtKey is a YAML mapping key
  of gtStringLit, gtLongStringLit, gtCharLit: "hl-string"
  of gtEscapeSequence: "hl-escape"
  of gtDecNumber, gtBinNumber, gtHexNumber, gtOctNumber, gtFloatNumber: "hl-number"
  of gtComment, gtLongComment: "hl-comment"
  of gtOperator: "hl-operator"
  of gtPreprocessor, gtDirective: "hl-preprocessor"
  of gtRegularExpression: "hl-regex"
  of gtProgram: "hl-program" # command/program name in `cmd` blocks
  of gtOption: "hl-option"   # flags, arguments, and quoted strings in `cmd` blocks
  else: ""

proc highlightSource(code: string, lang: SourceLanguage): string =
  ## Tokenize unescaped `code`, wrapping each meaningful token in a span.
  var g: GeneralTokenizer
  g.initGeneralTokenizer(code)
  result = newStringOfCap(code.len + code.len div 2)
  var stalls = 0 # consecutive zero-length tokens, to break a genuinely stuck lexer
  while true:
    g.getNextToken(lang)
    if g.kind == gtEof:
      break
    if g.length == 0:
      # highlite emits zero-length tokens to advance its lexer state without
      # consuming input — YAML primes its state machine this way (and again
      # before quoted scalars). Skip them, but bail after a bounded run so a
      # truly stuck tokenizer can't hang the build.
      inc stalls
      if stalls > 16:
        break
      continue
    stalls = 0
    let text = htmlEscape(code[g.start ..< g.start + g.length])
    let cls = cssClass(g.kind)
    if cls.len == 0:
      result.add text
    else:
      result.add "<span class=\""
      result.add cls
      result.add "\">"
      result.add text
      result.add "</span>"

func resolveLanguage(langName: string): SourceLanguage =
  case langName.toLowerAscii
  of "json": langYaml
  of "bash", "zsh", "sh": langCmd
  else: getSourceLanguage(langName)

proc highlightCodeBlocks*(html: string): string {.gcsafe.} =
  ## Rewrite every `language-NAME` code block highlite understands into token
  ## spans, leaving all other markup untouched.
  result = newStringOfCap(html.len + html.len div 4)
  var i = 0
  while true:
    let open = html.find(preOpen, i)
    if open == -1:
      result.add html[i .. ^1]
      break
    result.add html[i ..< open]

    # md4c escapes `<`/`>` inside code, so `">` and `</code></pre>` below can only
    # be the real tag boundaries, never block content.
    let langStart = open + preOpen.len
    let quotePos = html.find('"', langStart)
    if quotePos == -1 or quotePos + 1 >= html.len or html[quotePos + 1] != '>':
      result.add preOpen
      i = langStart
      continue

    let langName = html[langStart ..< quotePos]
    let contentStart = quotePos + 2
    let closePos = html.find(codeClose, contentStart)
    if closePos == -1:
      result.add html[open .. ^1] # unclosed: keep the remainder verbatim
      break

    let inner = html[contentStart ..< closePos]
    let lang = resolveLanguage(langName)
    result.add preOpen
    result.add langName
    result.add "\">"
    result.add(if lang == langNone: inner
               else: highlightSource(htmlUnescape(inner), lang))
    result.add codeClose
    i = closePos + codeClose.len
