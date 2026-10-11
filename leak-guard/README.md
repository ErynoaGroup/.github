# leak-guard

Scanner (`scan.sh`), Muster (`patterns.txt`, nur Regex), Selbsttest (`test.sh`) und wiederverwendbarer Workflow (`.github/workflows/leak-guard.yml`).

Exit-Codes: `0` sauber, `1` Treffer, `>=2` Scanner-Fehler (ungültiges Muster, fehlende Datei, kaputte Allowlist). Ausgegeben wird nur `datei:zeile`, nie der Inhalt.

## Allowlist für bewusste Test-Beispiele (`.leak-guard-allow`)

Liegt im **aufrufenden** Repo im Root. Änderungen daran brauchen ein CODEOWNERS-Review, also ein Eintrag wie `/.leak-guard-allow @NiklasJavier` in `.github/CODEOWNERS` plus Branch-Protection „Require review from Code Owners“.

Eintrag je Zeile, Begründung nach `#` ist Pflicht:

```
tests/test_redact_tsnet.py            # Redaction-Fixture, nur Fake-Werte
tests/fixtures/redact_*.txt           # enger Glob im letzten Pfadsegment
tests/x.py:12:<sha256 der Zeile>      # optional: auf genau eine Zeile festnageln
```

Regeln, jeder Verstoß ergibt Exit 2:
- Nur unter `tests/` oder `fixtures/`.
- `*` nur im letzten Pfadsegment und matcht nie über `/` (Verzeichnisteil wird exakt verglichen). Kein nacktes `*`, kein `**`, kein `?`/`[]`, kein `..`.
- Optional `pfad:zeile:sha256(zeileninhalt ohne Umbruch)`: Eine geänderte oder verschobene Zeile ist wieder ein Treffer.

Wirkung und Grenzen:
- Gilt nur für Basis-Muster bei Datei- und `--staged`-Scans.
- Treffer aus `RAGFIT_LEAK_EXTRA` (`LEAK_EXTRA_FILE`) werden **nie** unterdrückt.
- **Nie** für Commit-Messages oder PR-Text (`--stdin`).
- Fixtures enthalten nur dokumentierte Fake-Werte: Tailnet-ID `tail` + sechs Nullen, Adressen aus dem /24 ab `100.64.0.`*n*. Die generischen Netzangaben (ULA-Präfix und das /10-Netz) stehen nicht als Klartext hier, sondern nur als Muster in `fixtures/` des aufrufenden Repos (z.B. `fixtures/redaction-patterns.txt`) bzw. in `patterns.txt`.

## Ausgabe

Nur die Trefferzahl je Datei, keine Zeilennummern und kein Inhalt. Per Allowlist unterdrückte Treffer werden ebenfalls gezählt: je Datei `::notice file=<f>::N allowlisted` plus eine Summenzeile.

## Commit-Scan ohne Base

Ohne nutzbare Base-SHA (erster Push, Force-Push) wird die **ganze History** gescannt. Bis zur History-Bereinigung (Rewrite) ist der Job in diesen Fällen absehbar rot.

## Erlaubte Commit-Autoren (Default)

`59505702+NiklasJavier@users.noreply.github.com`, `noreply@github.com` (Web-Merges), `niklas.klein@erynoa.com`.
